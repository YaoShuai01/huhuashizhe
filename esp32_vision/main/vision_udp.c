/**
 * vision_udp - UDP 服务实现（命令解析 + 推流任务 + 分段发送）
 */
#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_psram.h"
#include "lwip/sockets.h"

#include "vision_udp.h"
#include "vision_cam.h"
#include "vision_wifi.h"

static const char *TAG = "VUDP";

#define SEG_MAX        1400    // 单段payload上限（≤MTU，避免IP分片：
                               // 48KB大包要切30+个IP分片，任一分片丢失整帧皆失）
// 每发几个包让出一次 CPU，给 WiFi 任务排空发送队列的机会。
//
// 这个值要保守：设成 4 会让帧率明显下降（实测 VGA 从 3.6fps 掉到 0.2fps），
// 因为 taskYIELD 在高频调用下自身开销不可忽略，且打断了发送流水。
// 设成 16（等于一整轮静态 TX 缓冲的容量）既能避免灌满，又不干扰流水。
#define SEND_BURST     16
#define RX_BUF_SIZE    128
#define SEND_FLAG_START 0x01

enum { FRAME_TYPE_STREAM = 0x01, FRAME_TYPE_SNAPSHOT = 0x02 };

static int  s_sock = -1;
static struct sockaddr_in s_client;      // 最近命令来源
static bool s_has_client = false;

static volatile bool s_streaming = false;
static uint32_t s_frame_seq = 0;
static uint32_t s_photo_id = 0;

// ==================== 分段发送 ====================
// FEC：每 FEC_GROUP 个数据段生成 1 个 XOR 校验段，
// 接收端丢 1 个分段时可用校验段恢复该帧，避免"丢一段废一帧"——
// 720p一帧约65段，1%丢包时整帧成功率仅52%；加FEC后可达95%以上。
#define FEC_GROUP      8
#define FEC_FLAG       0x02    // flags bit1：本包是FEC校验段

// ==================== 发送（含拍照帧的 ENOMEM 重试 + 冗余重发）====================
//
// 为什么拍照需要特殊处理：
//   5MP 照片约 150KB，要切成 110 数据段 + 14 FEC 段 = 124 个 UDP 包。
//   而 WiFi 驱动的静态 TX 缓冲只有 CONFIG_ESP_WIFI_STATIC_TX_BUFFER_NUM 个
//   （本机 16 个，每个约 1.6KB）。sendto 是「交给驱动就返回」，真正空口
//   发送是异步的，所以连续调用十几次就会把缓冲灌满，之后返回
//   errno=12 (ENOMEM)。
//
//   流帧遇到这种情况可以丢弃（下一帧马上补上），但照片只有一次机会：
//   早先的实现直接放弃整张照片，客户端收到 16/110 段永远拼不齐，
//   2 秒后超时丢弃 —— 表现就是"点拍照没反应"。
//   实测：流畅档小概率失败，高清档大概率失败（高清档本身已接近码率上限，
//   TX 缓冲长期处于高位，拍照突发时更容易瞬间打满）。
//
// ★ 三层保障（缺一不可）：
//   1) 拍照前固定等待 1 秒（SNAPSHOT_DRAIN_MS）：停推流后让驱动把
//      TX 缓冲彻底排空。曾尝试用探针做自适应等待，但小包能进队列、
//      大包才失败，探针不可靠，实测导致拍照 100% 失败，故改回固定等待。
//   2) 主动让速：每 SNAPSHOT_BURST 个包 delay 2ms，从源头不去挤满缓冲。
//   3) ENOMEM 重试：单个包发送失败时等 10ms 再试同一个包，最多 20 次。
//      注意重试的是【同一个包】，不是把整帧重发一遍 —— 客户端按
//      (frame_seq, seg_idx) 存储，同一段多发几次只会覆盖，不会重复计数。
//
// ⚠ 不要改成「整帧重发两遍」来提升成功率：客户端每拼齐一次就会触发
//   photoNotifier，整帧重发会导致同一张照片被保存两次（实测已确认）。
//   提升可靠性要靠上面三层的「单包级」手段，不能靠帧级冗余。
//
//   代价：照片流量 150KB，发送耗时约 0.4~0.9 秒。拍照本来就暂停推流，
//   这个延迟可以接受。
#define SNAPSHOT_BURST        8     // 拍照帧每发几个包主动让出一次
#define SNAPSHOT_YIELD_MS     2     // 让出时长：足够 WiFi 排空，又不至于太慢
#define SNAPSHOT_RETRY_MAX    20    // ENOMEM 最大重试次数（约 200ms）

// 拍照前固定等待时长。
//
// 为什么不再用「自适应探测」：曾尝试用 sendto 探针判断 TX 缓冲是否腾空，
// 但小包很容易挤进队列、大包才失败，探针返回成功并不代表 1400 字节的
// 数据段能发出去。实测该方案导致拍照 100% 失败（探针第一发就"成功"，
// 等于零等待，直接撞满缓冲）。改成固定 1 秒，简单可靠。
//
// 1 秒的依据：照片要突发 124 个包（约 174KB），WiFi 静态 TX 缓冲只有
// 16 个 × 1.6KB = 25.6KB，按实测 400KB/s 的空口速率排空 25.6KB 约需
// 65ms，留足余量取 1 秒，足以覆盖拥塞抖动。
#define SNAPSHOT_DRAIN_MS 1000

// 发送一个包。is_snapshot=true 时对 ENOMEM 做等待重试。
// 返回 0 成功，-1 失败。*retried 累加重试次数（可为 NULL）。
static int send_one_packet(const uint8_t *buf, int len, bool is_snapshot, int *retried)
{
    int sent = sendto(s_sock, buf, len, 0,
                      (struct sockaddr *)&s_client, sizeof(s_client));
    if (sent >= 0) return 0;
    if (!is_snapshot) return -1;

    const int saved_errno = errno;
    // 只有 ENOMEM 值得重试：它表示 TX 缓冲暂时占满，等一会儿就恢复。
    // ENOBUFS/EAGAIN 同理。其它错误（如网络不可达）重试也没用。
    if (saved_errno != ENOMEM && saved_errno != ENOBUFS && saved_errno != EAGAIN) {
        return -1;
    }

    for (int i = 0; i < SNAPSHOT_RETRY_MAX; i++) {
        vTaskDelay(pdMS_TO_TICKS(10));
        sent = sendto(s_sock, buf, len, 0,
                      (struct sockaddr *)&s_client, sizeof(s_client));
        if (retried) (*retried)++;
        if (sent >= 0) return 0;
    }
    // 重试用尽，把最后的 errno 留给调用方打印
    errno = saved_errno;
    return -1;
}

// 发送一遍数据段（不含 FEC）。返回 0 成功，-1 失败。
// seq 取自 s_frame_seq，由 send_segments 在整帧结束后统一递增。
static int send_data_pass(int type, uint32_t photo_id, const uint8_t *jpg,
                          uint32_t total, uint16_t seg_cnt, int *retried)
{
    uint8_t buf[22 + SEG_MAX];
    const bool is_snap = (type == FRAME_TYPE_SNAPSHOT);

    for (uint16_t seg = 0; seg < seg_cnt; seg++) {
        // ★ 必须是 uint32：UXGA一帧约200KB，uint16在第47段就会回绕，
        //   导致后续分段全部重复发送文件开头的数据，画面大面积花屏
        uint32_t off = (uint32_t)seg * SEG_MAX;
        uint16_t seg_len = (uint16_t)((total - off) > SEG_MAX ? SEG_MAX : (total - off));

        buf[0] = 'H'; buf[1] = 'V';
        buf[2] = (uint8_t)type;
        buf[3] = (seg == 0) ? SEND_FLAG_START : 0;
        buf[4]  = (uint8_t)(photo_id);
        buf[5]  = (uint8_t)(photo_id >> 8);
        buf[6]  = (uint8_t)(photo_id >> 16);
        buf[7]  = (uint8_t)(photo_id >> 24);
        uint32_t seq = s_frame_seq;
        buf[8]  = (uint8_t)(seq);
        buf[9]  = (uint8_t)(seq >> 8);
        buf[10] = (uint8_t)(seq >> 16);
        buf[11] = (uint8_t)(seq >> 24);
        buf[12] = (uint8_t)(seg);
        buf[13] = (uint8_t)(seg >> 8);
        buf[14] = (uint8_t)(seg_cnt);
        buf[15] = (uint8_t)(seg_cnt >> 8);
        buf[16] = (uint8_t)(total);
        buf[17] = (uint8_t)(total >> 8);
        buf[18] = (uint8_t)(total >> 16);
        buf[19] = (uint8_t)(total >> 24);
        buf[20] = (uint8_t)(seg_len);
        buf[21] = (uint8_t)(seg_len >> 8);
        memcpy(buf + 22, jpg + off, seg_len);

        if (send_one_packet(buf, 22 + seg_len, is_snap, retried) < 0) {
            ESP_LOGW(TAG, "sendto 失败 errno=%d（%s seq=%u seg=%u/%u 已重试%d次）",
                     errno, is_snap ? "照片" : "帧",
                     (unsigned)seq, (unsigned)seg, (unsigned)seg_cnt,
                     retried ? *retried : 0);
            return -1;
        }

        // ★ 让出 CPU 给 WiFi 任务排空 TX 缓冲。
        //   流帧用 taskYIELD（不引入固定延迟，保护帧率）；
        //   拍照帧用短 delay（照片不赶时间，宁可慢也要发完）。
        if (is_snap) {
            if ((seg % SNAPSHOT_BURST) == (SNAPSHOT_BURST - 1)) {
                vTaskDelay(pdMS_TO_TICKS(SNAPSHOT_YIELD_MS));
            }
        } else if ((seg & (SEND_BURST - 1)) == (SEND_BURST - 1)) {
            taskYIELD();
        }
    }
    return 0;
}

// 发送一遍 FEC 校验段（仅流帧需要；照片帧靠多遍重发数据段，不重复发校验）。
static int send_fec_pass(int type, uint32_t photo_id, const uint8_t *jpg,
                         uint32_t total, uint16_t seg_cnt, int *retried)
{
    uint8_t buf[22 + SEG_MAX];
    uint8_t fec_acc[SEG_MAX];
    int fec_in_group = 0;
    uint16_t fec_group = 0;
    memset(fec_acc, 0, SEG_MAX);

    for (uint16_t seg = 0; seg < seg_cnt; seg++) {
        uint32_t off = (uint32_t)seg * SEG_MAX;
        uint16_t seg_len = (uint16_t)((total - off) > SEG_MAX ? SEG_MAX : (total - off));

        if (fec_in_group == 0) memset(fec_acc, 0, SEG_MAX);
        for (uint16_t i = 0; i < seg_len; i++) fec_acc[i] ^= jpg[off + i];
        fec_in_group++;

        if (fec_in_group == FEC_GROUP || seg == seg_cnt - 1) {
            uint32_t seq = s_frame_seq;
            buf[0] = 'H'; buf[1] = 'V';
            buf[2] = (uint8_t)type;
            buf[3] = FEC_FLAG;
            buf[4]  = (uint8_t)(photo_id);
            buf[5]  = (uint8_t)(photo_id >> 8);
            buf[6]  = (uint8_t)(photo_id >> 16);
            buf[7]  = (uint8_t)(photo_id >> 24);
            buf[8]  = (uint8_t)(seq);
            buf[9]  = (uint8_t)(seq >> 8);
            buf[10] = (uint8_t)(seq >> 16);
            buf[11] = (uint8_t)(seq >> 24);
            buf[12] = (uint8_t)(fec_group);
            buf[13] = (uint8_t)(fec_group >> 8);
            buf[14] = (uint8_t)(seg_cnt);
            buf[15] = (uint8_t)(seg_cnt >> 8);
            buf[16] = (uint8_t)(total);
            buf[17] = (uint8_t)(total >> 8);
            buf[18] = (uint8_t)(total >> 16);
            buf[19] = (uint8_t)(total >> 24);
            buf[20] = (uint8_t)(SEG_MAX);
            buf[21] = (uint8_t)(SEG_MAX >> 8);
            memcpy(buf + 22, fec_acc, SEG_MAX);

            if (send_one_packet(buf, 22 + SEG_MAX, type == FRAME_TYPE_SNAPSHOT, retried) < 0) {
                ESP_LOGW(TAG, "sendto(FEC) 失败 errno=%d（丢弃帧 seq=%u 已重试%d次）",
                         errno, (unsigned)seq, retried ? *retried : 0);
                return -1;
            }
            fec_group++;
            fec_in_group = 0;
        }
    }
    return 0;
}

static int send_segments(int type, uint32_t photo_id, const uint8_t *jpg, uint32_t total)
{
    if (!s_has_client) return -1;

    const uint16_t seg_cnt = (uint16_t)((total + SEG_MAX - 1) / SEG_MAX);
    int retried = 0;

    // 数据段 + FEC 各发一遍。客户端每拼齐一帧就通知一次，所以绝不能发两遍
    // （否则同一张照片会被保存两次）。
    if (send_data_pass(type, photo_id, jpg, total, seg_cnt, &retried) < 0) {
        // 失败也要递增帧序号：否则下一帧复用同一 seq，接收端会把它和这次
        // 残缺的数据混在一起。
        s_frame_seq++;
        return -1;
    }

    if (send_fec_pass(type, photo_id, jpg, total, seg_cnt, &retried) < 0) {
        s_frame_seq++;
        return -1;
    }

    s_frame_seq++;
    return 0;
}

// ==================== 采集/发送流水线 ====================
// 采集与发送拆成两个任务：采集完立即把帧投递到队列去采下一帧，
// 发送任务并行把上一帧发出去。
// 原来单任务串行"采集→发完几十个包→再采集"，发送耗时全部串进帧周期，
// 是实际帧率只有设定值一半左右的核心原因。
#define FB_QUEUE_LEN 2
static QueueHandle_t s_fb_q = NULL;

// ==================== 码率控制（帧率优先，质量让路）====================
//
// 目标：整条图传通道的【载荷码率】始终控制在 400 KB/s，峰值不超过 450。
//
// 为什么按「每秒字节数」而不是「单帧大小」来判断：
//   单帧大小和帧率是乘数关系。早先按 35KB/帧 判断，20fps 时就是 700KB/s
//   （早就超了），8fps 时只有 280KB/s（反而安全），同一个阈值在不同帧率下
//   含义完全不同。改成每秒统计总量后与帧率解耦。
//
// ★ 优先级（用户明确要求）：帧率 > 画面质量
//   码率超标时先牺牲质量（提高 JPEG 量化值 q）；
//   质量已到底（q=22）才降帧率。
//   码率富余时先恢复帧率，帧率到顶才恢复质量。
//
// ★ 防振荡（这是关键，否则会陷入 450→压→350→回升→450 的死循环）：
//   1) 滞回区间：350~450 之间【完全不动】。区间宽 100KB/s，大于单次
//      调整带来的变化量，所以降一次一般就落进区间内停手。
//   2) 不对称：降级快（1 秒触发）、恢复慢（5 秒触发）。
//   3) 冷却：降级后 3 秒、恢复后 5 秒内不再调整。
//   4) 每秒最多调整一次。
//
// 注意：区间只有 100KB/s，比早先的 250KB/s 窄，单次 q+3 的变化量有可能
// 直接从 460 掉到 320（穿出下沿）。若观察到此现象，把 RATE_Q_STEP_DOWN
// 改成 2，或把 RATE_RECOVER_KBPS 降到 320 即可。
#define RATE_HARD_LIMIT_KBPS    450   // 峰值上限：超过即降级（不可逾越的红线）
#define RATE_RECOVER_KBPS       350   // 低于此值才考虑恢复（滞回下沿）
#define RATE_DOWN_HOLD_MS       1000  // 超标持续多久才降（快速响应）
#define RATE_UP_HOLD_MS         5000  // 富余持续多久才升（缓慢恢复）
#define RATE_DOWN_COOLDOWN_MS   3000  // 一次降级后的静默期
#define RATE_UP_COOLDOWN_MS     5000  // 一次恢复后的静默期
#define RATE_Q_STEP_DOWN        2     // 降级时 q 增量。
                                      // 从 3 改成 2：滞回区间只有 100KB/s，
                                      // q+3 常让码率从 460 直接掉到 320（穿出
                                      // 下沿 350），反而触发恢复 → 形成振荡。
                                      // 降幅越小越平滑，逼近 400 的目标值。
#define RATE_Q_STEP_UP          1     // 恢复时 q 减少量（越小越稳）

// 帧率阶梯（双向可调，离散档位避免抖动）。
// 各档位的上下限由 profile 决定（见下方 s_fps_min / s_fps_max）。
static const int k_fps_ladder[] = { 8, 10, 12, 15, 20, 25, 30 };
static const int k_fps_ladder_n = sizeof(k_fps_ladder) / sizeof(k_fps_ladder[0]);
#define ADAPT_Q_BEST    6          // 最好画质（q 越小越清晰）
#define ADAPT_Q_WORST   22         // 最差画质（q 到顶仍超限就只能降帧率）

// ==================== 各档位的控制策略 ====================
//
// 不同画质档位的取舍完全不同，不能用同一套参数：
//
//   流畅档（res_idx=2，XGA）：
//     用户要的是"操控跟手"，画质可以牺牲到底。
//     → 质量【固定 q22，永不调整】（s_lock_quality=true）
//     → 帧率【无上限】，能升多高升多高（s_fps_max=30，不设天花板）
//     → 帧率下限 10fps
//     码率超标时因为质量不能再降，只能降帧率；一旦有余量就拼命升帧率。
//
//   均衡档（res_idx=3，HD）：
//     → 质量可调（q 6~22）
//     → 帧率下限提到 10fps（8fps 太卡，操控明显迟钝），上限=用户设定 15
//
//   高清档（res_idx=5，UXGA）及其它：
//     → 质量可调
//     → 帧率下限 8fps，上限=用户设定值
//
// 实现方式：控制器的两个上限/下限都是变量，由 apply_profile_policy()
// 在每次 VSTART 时按 res_idx 设置。
static int  s_fps_min = 8;          // 当前档位的帧率下限
static int  s_fps_max = 20;         // 当前档位的帧率上限（不受用户设定约束）
static bool s_lock_quality = false; // true = 质量锁死，控制器不碰

// 对外统计/状态
static volatile uint32_t s_rate_kbps = 0;       // 最近 1 秒实测码率
static uint32_t s_rate_acc_bytes = 0;           // 本秒累计字节
static int64_t  s_rate_sec_start = 0;           // 本秒起点

// 控制器内部状态
static int      s_fps_ceiling = 0;              // 用户设定的帧率（仅 /status 展示）
                                                 // 实际上下限用 s_fps_min/s_fps_max
static int64_t  s_over_since = 0;               // 开始超标的时刻（0=未超标）
static int64_t  s_under_since = 0;              // 开始富余的时刻
static int64_t  s_last_action = 0;              // 上次调整时刻
static int      s_last_was_down = 0;            // 上次调整方向（1降 0升 -1无），仅日志用

static uint32_t s_adapt_downed = 0;             // 累计降级次数（含降帧率）
static uint32_t s_adapt_raised = 0;             // 累计恢复次数
static bool     s_adapt_warned = false;         // 「到底了还是超」告警只打一次
static int      s_adapt_q_base = -1;            // 用户期望质量（仅记录/展示）

// ==================== 对外统计（供 HTTP /status 与验收脚本用）====================
static volatile uint32_t s_stat_frames_total = 0;    // 累计成功入队帧数
static volatile uint32_t s_stat_last_kb = 0;         // 最近一帧 KB
static volatile uint32_t s_stat_avg_kb = 0;          // 最近窗口平均 KB
static volatile uint32_t s_stat_dropped = 0;         // 因队列满丢弃帧数
static volatile uint32_t s_stat_null = 0;            // 取帧失败次数

void vision_udp_get_stats(vision_udp_stats_t *out)
{
    if (!out) return;
    out->frames_total = s_stat_frames_total;
    out->last_kb = s_stat_last_kb;
    out->avg_kb = s_stat_avg_kb;
    out->dropped = s_stat_dropped;
    out->null_frames = s_stat_null;
    out->queue_depth = s_fb_q ? (uint32_t)uxQueueMessagesWaiting(s_fb_q) : 0;
    out->adapt_down_count = s_adapt_downed;
    out->adapt_up_count = s_adapt_raised;
    out->quality = cam_get_quality();
    out->quality_base = s_adapt_q_base;
    out->fps = cam_get_fps();
    out->fps_ceiling = s_fps_ceiling;
    out->res_idx = cam_get_stream_res();
    out->rate_kbps = s_rate_kbps;
    out->streaming = s_streaming;
}

static void capture_task(void *pv)
{
    // 帧率统计：每 5 秒打一次，区分"采集到几帧"和"丢了几帧"
    uint32_t stat_frames = 0, stat_dropped = 0, stat_null = 0;
    int64_t stat_t0 = esp_timer_get_time();

    while (1) {
        if (!s_streaming || !s_has_client) {
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }

        int64_t t0 = esp_timer_get_time();
        camera_fb_t *fb = cam_capture();
        if (!fb) {
            stat_null++;
            s_stat_null++;              // 对外统计：取帧失败
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }
        stat_frames++;
        s_stat_last_kb = fb->len / 1024;

        // 队列满说明网络发不出去：直接丢这帧，避免延迟越积越大
        if (xQueueSend(s_fb_q, &fb, 0) != pdTRUE) {
            stat_dropped++;
            s_stat_dropped++;           // 对外统计：队列满丢帧
            cam_release(fb);
        } else {
            s_stat_frames_total++;      // 对外统计：成功入队
        }

        // 按 fps 定拍，采集耗时计入间隔
        int interval_ms = 1000 / cam_get_fps();
        int elapsed_ms = (int)((esp_timer_get_time() - t0) / 1000);
        int remain = interval_ms - elapsed_ms;
        if (remain > 0) vTaskDelay(pdMS_TO_TICKS(remain));

        // 每 5 秒汇报：采集数 / 因队列满丢弃数 / 取帧失败数
        if (esp_timer_get_time() - stat_t0 >= 5000000) {
            ESP_LOGI(TAG, "采集 %.1ffps  丢弃%u  空帧%u  队列%d/%d",
                     stat_frames / 5.0f, (unsigned)stat_dropped,
                     (unsigned)stat_null,
                     (int)uxQueueMessagesWaiting(s_fb_q), FB_QUEUE_LEN);
            stat_frames = stat_dropped = stat_null = 0;
            stat_t0 = esp_timer_get_time();
        }
    }
}

/// 码率自适应：根据最近若干帧的平均大小调整 JPEG 质量。
/// 必须在 send_task（core 1）里调用，避免与其他任务并发改传感器寄存器。
/// 在帧率阶梯中找下一个更低/更高的档位。返回 -1 表示已到底/顶。
/// 按分辨率档位设置控制策略。每次 VSTART 调用一次。
/// res_idx 见 k_cam_res[]：2=XGA(流畅) 3=HD(均衡) 5=UXGA(高清)
static void apply_profile_policy(int res_idx, int user_fps)
{
    s_fps_ceiling = user_fps;
    s_lock_quality = false;
    s_fps_min = 8;

    switch (res_idx) {
        case 2:   // ★ 流畅档：XGA
            // 画质锁死最差，全部预算让给帧率。
            // 用户明确要求：流畅档不限制帧率上限、画质固定最低。
            s_lock_quality = true;
            s_fps_min = 10;          // 下限 10fps
            s_fps_max = 30;          // 无实际上限（阶梯最高就是 30）
            break;

        case 3:   // ★ 均衡档：HD 720p
            // 帧率下限提到 10：8fps 操控明显迟钝，用户要求均衡档不低于 10。
            s_fps_min = 10;
            s_fps_max = user_fps;
            break;

        default:  // 高清档及其它：以画质优先，帧率下限 8
            s_fps_min = 8;
            s_fps_max = user_fps;
            break;
    }

    ESP_LOGI(TAG, "档位策略 res=%s: 帧率 %d~%d，质量%s",
             k_cam_res[res_idx].name, s_fps_min, s_fps_max,
             s_lock_quality ? "锁定q22" : "可调");
}

static int ladder_step(int cur_fps, int dir)
{
    // 找到不超过 cur_fps 的最大档位
    int idx = 0;
    for (int i = 0; i < k_fps_ladder_n; i++) {
        if (k_fps_ladder[i] <= cur_fps) idx = i;
    }
    if (dir < 0) {
        // 若用户设的帧率不在阶梯上（如 25），先降到不超过它的最高档（20），
        // 而不是直接跳到倒数第二档（15）——否则会白丢一档。
        if (k_fps_ladder[idx] < cur_fps) return k_fps_ladder[idx];
        return idx > 0 ? k_fps_ladder[idx - 1] : -1;
    }
    // 向上：下一档（是否超过上限由调用方用 s_fps_max 校验）
    return (idx + 1 < k_fps_ladder_n) ? k_fps_ladder[idx + 1] : -1;
}

/// 码率控制器：每秒结算一次，按「帧率优先、质量让路」调整。
/// 在 send_task（core 1）里调用，与发送串行，避免并发改传感器寄存器。
static void rate_control(uint32_t kbps)
{
    const int64_t now = esp_timer_get_time();

    // 统计超标/富余的起始时刻
    if (kbps > RATE_HARD_LIMIT_KBPS) {
        s_under_since = 0;
        if (s_over_since == 0) s_over_since = now;
    } else if (kbps < RATE_RECOVER_KBPS) {
        s_over_since = 0;
        if (s_under_since == 0) s_under_since = now;
    } else {
        // 落在滞回区间（300~550）：什么都不做，清空计时
        s_over_since = 0;
        s_under_since = 0;
        return;
    }

    const int q = cam_get_quality();
    const int fps = cam_get_fps();

    // ---------------- 降级：帧率优先，先牺牲质量 ----------------
    if (s_over_since && (now - s_over_since) >= RATE_DOWN_HOLD_MS * 1000) {
        // 冷却期检查（不再区分方向：3 秒内动过手就等，避免连续追打）
        if ((now - s_last_action) < RATE_DOWN_COOLDOWN_MS * 1000) {
            return;
        }

        // 质量未锁死且还有余量 → 降质量保帧率。
        // 流畅档 s_lock_quality=true，直接跳过这一段去降帧率。
        if (!s_lock_quality && q < ADAPT_Q_WORST) {
            // 还有质量余量 → 降质量保帧率
            int want = q + RATE_Q_STEP_DOWN;
            if (want > ADAPT_Q_WORST) want = ADAPT_Q_WORST;
            const int applied = cam_set_quality_only(want);
            if (applied != q) {
                s_adapt_downed++;
                s_last_action = now;
                s_last_was_down = 1;
                s_over_since = 0;      // 重置计时，重新观察效果
                ESP_LOGI(TAG, "码率%uKB/s超限→降质量 q%d→q%d（帧率保持%d）",
                         (unsigned)kbps, q, applied, fps);
                return;
            }
        }

        // 质量已到底（或锁死）→ 只能降帧率
        const int nf = ladder_step(fps, -1);
        if (nf > 0 && nf >= s_fps_min) {
            cam_set_fps_only(nf);
            s_adapt_downed++;
            s_last_action = now;
            s_last_was_down = 1;
            s_over_since = 0;
            ESP_LOGW(TAG, "码率%uKB/s超限%s→降帧率 %d→%dfps",
                     (unsigned)kbps,
                     s_lock_quality ? "(画质已锁定)" : "(画质已到底)",
                     fps, nf);
        } else if (!s_adapt_warned) {
            s_adapt_warned = true;
            ESP_LOGW(TAG, "码率%uKB/s超限，质量q%d与帧率%dfps均已到底："
                          "当前分辨率超出链路能力，请降低推流分辨率",
                     (unsigned)kbps, q, fps);
        }
        return;
    }

    // ---------------- 恢复：先恢复帧率，帧率到顶才恢复质量 ----------------
    if (s_under_since && (now - s_under_since) >= RATE_UP_HOLD_MS * 1000) {
        // ★ 刚降过级就跌到下沿的情况（降过头）不要立刻回升 —— 否则
        //   降→回升→再降 会形成慢速振荡。这里强制至少等满恢复冷却期，
        //   与「上次是降级」无关，只要 RATE_UP_COOLDOWN_MS 内动过手就不升。
        if ((now - s_last_action) < RATE_UP_COOLDOWN_MS * 1000) {
            return;
        }

        // 优先恢复帧率。上限用 s_fps_max（流畅档是 30，其它档=用户设定值）
        const int nf = ladder_step(fps, +1);
        if (nf > 0 && nf <= s_fps_max) {
            cam_set_fps_only(nf);
            s_adapt_raised++;
            s_last_action = now;
            s_last_was_down = 0;
            s_under_since = 0;
            ESP_LOGI(TAG, "码率%uKB/s富余→恢复帧率 %d→%dfps（质量q%d不变）",
                     (unsigned)kbps, fps, nf, q);
            return;
        }

        // 帧率已到上限，恢复质量。流畅档质量锁死，永远不走这一步。
        if (!s_lock_quality && q > ADAPT_Q_BEST) {
            int want = q - RATE_Q_STEP_UP;
            if (want < ADAPT_Q_BEST) want = ADAPT_Q_BEST;
            const int applied = cam_set_quality_only(want);
            if (applied != q) {
                s_adapt_raised++;
                s_last_action = now;
                s_last_was_down = 0;
                s_under_since = 0;
                s_adapt_warned = false;
                ESP_LOGI(TAG, "码率%uKB/s富余→恢复质量 q%d→q%d（帧率%d已达上限）",
                         (unsigned)kbps, q, applied, fps);
            }
        }
    }
}

/// 每秒结算一次码率并驱动控制器。在 send_task 里逐帧累加字节。
static void rate_account(uint32_t frame_bytes)
{
    s_rate_acc_bytes += frame_bytes;
    const int64_t now = esp_timer_get_time();
    if (s_rate_sec_start == 0) {
        s_rate_sec_start = now;
        return;
    }
    if (now - s_rate_sec_start >= 1000000) {
        const uint32_t kbps = s_rate_acc_bytes / 1024;
        s_rate_kbps = kbps;
        // 平均帧大小 ≈ 每秒码率 / 实际帧率，供 /status 显示
        const int f = cam_get_fps();
        s_stat_avg_kb = f > 0 ? kbps / (uint32_t)f : 0;
        s_rate_acc_bytes = 0;
        s_rate_sec_start = now;
        rate_control(kbps);
    }
}

static void send_task(void *pv)
{
    camera_fb_t *fb = NULL;
    while (1) {
        if (xQueueReceive(s_fb_q, &fb, pdMS_TO_TICKS(200)) == pdTRUE && fb) {
            // 码率结算必须在发送前：先累加本帧字节，必要时调整下一帧的
            // 质量/帧率。注意这里统计的是「准备发送」的字节数，接近实际
            // 空口载荷（失败丢帧会略微高估，对限速而言偏保守，可接受）。
            rate_account(fb->len);
            send_segments(FRAME_TYPE_STREAM, 0, fb->buf, fb->len);
            cam_release(fb);
            fb = NULL;
        }
    }
}

/// 清空待发送队列，把帧缓冲立即还给摄像头（拍照/切档前调用）
void vision_udp_drain_fb_queue(void);

static void drain_fb_queue(void)
{
    camera_fb_t *stale = NULL;
    while (s_fb_q && xQueueReceive(s_fb_q, &stale, 0) == pdTRUE) {
        if (stale) cam_release(stale);
        stale = NULL;
    }
}

void vision_udp_drain_fb_queue(void)
{
    drain_fb_queue();
}

// ==================== 命令处理 ====================
static void send_text(const char *msg)
{
    if (!s_has_client) return;
    sendto(s_sock, msg, strlen(msg), 0,
           (struct sockaddr *)&s_client, sizeof(s_client));
}

static void do_snapshot(int res_idx)
{
    if (res_idx < 0 || res_idx >= k_cam_res_count) res_idx = 7;   // 默认5MP

    int saved_res = cam_get_stream_res();
    bool was_streaming = s_streaming;
    s_streaming = false;                    // 拍照期间暂停推流，释放帧缓冲

    // 先把手上的待发帧还给摄像头，再固定等待 1 秒让驱动 TX 缓冲排空。
    // 顺序不能反：队列里的帧如果还占着，会给缓冲造成额外占用。
    // 为什么用固定等待而不是探测：见 SNAPSHOT_DRAIN_MS 的注释。
    drain_fb_queue();
    vTaskDelay(pdMS_TO_TICKS(SNAPSHOT_DRAIN_MS));

    // ★ 拍照走 cam_set_snapshot_res()：不受推流 clamp 的 UXGA 上限约束，
    //   否则 res_idx=7 会被静默压成 5，但日志/ACK 仍报 QSXGA —— 谎报分辨率。
    const int actual_res = cam_set_snapshot_res(res_idx);
    if (actual_res < 0) {
        send_text("VERR SNAPSHOT_BAD_RES");
        cam_set_stream_res(saved_res);
        s_streaming = was_streaming;
        return;
    }

    int64_t t0 = esp_timer_get_time();
    camera_fb_t *fb = cam_capture();
    if (!fb) {
        send_text("VERR SNAPSHOT_FAIL");
        cam_set_stream_res(saved_res);
        s_streaming = was_streaming;
        return;
    }

    uint32_t id = ++s_photo_id;
    ESP_LOGI(TAG, "拍照抓帧 %s %u字节 (%.1fMB) 耗时%dms",
             k_cam_res[actual_res].name, (unsigned)fb->len, fb->len / 1048576.0,
             (int)((esp_timer_get_time() - t0) / 1000));

    const int64_t tx0 = esp_timer_get_time();
    int rc = send_segments(FRAME_TYPE_SNAPSHOT, id, fb->buf, fb->len);
    const int tx_ms = (int)((esp_timer_get_time() - tx0) / 1000);
    cam_release(fb);

    // ★ 先把 ACK 发出去，再恢复推流。
    //
    // 原来顺序反了（先 s_streaming=true 再 send_text），推流帧会立刻涌进
    // TX 缓冲，ACK 排在后面很容易发不出去，App 侧就一直停在"拍照中..."。
    // 现在拍照期间 s_streaming 仍是 false，缓冲是空的，ACK 必达。
    char ack[80];
    snprintf(ack, sizeof(ack), "VOK SNAP id=%u res=%s rc=%d tx=%dms",
             (unsigned)id, k_cam_res[actual_res].name, rc, tx_ms);
    send_text(ack);

    cam_set_stream_res(saved_res);          // 恢复推流分辨率
    s_streaming = was_streaming;            // 最后才恢复推流

    // 发送耗时是判断"照片为什么会失败"的关键：正常约 300~900ms，
    // 若接近或超过 2000ms 说明大量重试，链路太拥挤。
    if (rc == 0) {
        ESP_LOGI(TAG, "拍照发送完成 id=%u 发送耗时%dms", (unsigned)id, tx_ms);
    } else {
        ESP_LOGW(TAG, "拍照发送失败 id=%u 发送耗时%dms（客户端收不全，2秒后会被丢弃）",
                 (unsigned)id, tx_ms);
    }
}

static void handle_command(char *cmd, int len)
{
    cmd[len] = '\0';
    ESP_LOGI(TAG, "命令: %s", cmd);

    char ack[160];

    if (!strncmp(cmd, "VSTART", 6)) {
        int res = 2, fps = 12, q = 12;
        int n = sscanf(cmd, "VSTART %d %d %d", &res, &fps, &q);
        if (n >= 1) {
            if (res < 0 || res >= k_cam_res_count) res = 2;
            if (fps < 2 || fps > 30) fps = 12;   // 上限30fps（VGA/XGA可跑到）
            if (q < 6 || q > 25) q = 12;
        }
        // 切分辨率会重启传感器PLL：先停采、清空队列，再改配置
        s_streaming = false;
        vTaskDelay(pdMS_TO_TICKS(80));
        drain_fb_queue();
        cam_set_stream_res(res);

        // ★ 按分辨率档位套用控制策略（流畅档锁质量无帧率上限、
        //   均衡档帧率下限 10 等）。必须在 cam_set_stream_params 之前调用，
        //   因为策略会决定初始质量。
        apply_profile_policy(res, fps);

        // ★ 从最低质量起步，再靠码率控制器逐步升上来。
        //
        // 为什么不直接用用户给的 q：刚连上时不知道链路状态（APSTA 下飞控
        // 转发带宽可能很窄），若直接以高质量起步，头几秒必然严重超限、
        // 大量丢帧、客户端拼不齐整帧 —— 用户看到的是"连上了但没画面"。
        // 从最差画质 q22 起步，第一秒码率必然很低，控制器在 5 秒内逐步
        // 恢复帧率与画质，画面从糊到清，全程不超限。
        //
        // 流畅档本来就锁死 q22，等于起点即终点，无需恢复画质。
        const int start_q = ADAPT_Q_WORST;
        cam_set_stream_params(s_fps_min, start_q);
        // 帧率也从下限起步，避免一上来就超限
        cam_set_fps_only(s_fps_min);

        // 记录状态
        s_adapt_q_base = q;         // 用户期望的质量（仅记录，不直接使用）
        s_adapt_downed = 0;
        s_adapt_raised = 0;
        s_adapt_warned = false;
        s_over_since = 0;
        s_under_since = 0;
        s_last_action = 0;
        s_last_was_down = -1;
        s_rate_acc_bytes = 0;
        s_rate_sec_start = 0;
        s_rate_kbps = 0;

        s_streaming = true;
        snprintf(ack, sizeof(ack),
                 "VOK STREAM %s fps%d~%d q%d(%s) 目标≤%dKB/s",
                 k_cam_res[res].name, s_fps_min, s_fps_max, start_q,
                 s_lock_quality ? "锁定" : "自动", RATE_TARGET_KBPS);
        send_text(ack);

    } else if (!strncmp(cmd, "VSTOP", 5)) {
        s_streaming = false;
        send_text("VOK STOP");

    } else if (!strncmp(cmd, "VSNAP", 5)) {
        int res = 7;
        sscanf(cmd, "VSNAP %d", &res);
        do_snapshot(res);

    } else if (!strncmp(cmd, "VINFO", 5)) {
        snprintf(ack, sizeof(ack),
                 "VOK INFO sensor=%s res=%s fps=%d q=%d streaming=%d ip=%s psram=%dKB qbase=%d adown=%u",
                 cam_sensor_name(),
                 k_cam_res[cam_get_stream_res()].name,
                 cam_get_fps(), cam_get_quality(),
                 (int)s_streaming, vision_wifi_ip_str(),
                 (int)(esp_psram_get_size() / 1024),
                 s_adapt_q_base, (unsigned)s_adapt_downed);
        send_text(ack);

    } else if (!strncmp(cmd, "VSET", 4)) {
        int fps = 0, q = 0;
        sscanf(cmd, "VSET %d %d", &fps, &q);
        // VSET 只改参数。若用户指定帧率，重新按当前档位套用策略，
        // 使帧率上限跟着更新（流畅档仍不受限，其它档跟用户设定走）。
        if (fps >= 2 && fps <= 30) {
            apply_profile_policy(cam_get_stream_res(), fps);
        }
        // 流畅档质量锁死，忽略传入的 q
        cam_set_stream_params(fps, s_lock_quality ? ADAPT_Q_WORST : q);
        if (q >= 6 && q <= 25) s_adapt_q_base = q;
        s_over_since = 0;
        s_under_since = 0;
        s_rate_acc_bytes = 0;
        s_rate_sec_start = 0;
        snprintf(ack, sizeof(ack), "VOK SET %dfps q%d %s",
                 cam_get_fps(), cam_get_quality(),
                 s_lock_quality ? "(质量锁定)" : "");
        send_text(ack);

    } else if (!strncmp(cmd, "VFLIP", 5)) {
        int on = 0;
        sscanf(cmd, "VFLIP %d", &on);
        cam_set_vflip(on);
        send_text(on ? "VOK FLIP 1" : "VOK FLIP 0");

    } else if (!strncmp(cmd, "VMIR", 4)) {
        int on = 0;
        sscanf(cmd, "VMIR %d", &on);
        cam_set_hmirror(on);
        send_text(on ? "VOK MIR 1" : "VOK MIR 0");

    } else {
        send_text("VERR UNKNOWN_CMD");
    }
}

// ==================== UDP 服务任务 ====================
static void udp_server_task(void *pv)
{
    uint8_t rx[RX_BUF_SIZE];
    struct sockaddr_in addr = { 0 };
    socklen_t addr_len = sizeof(addr);

    s_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s_sock < 0) {
        ESP_LOGE(TAG, "socket 创建失败 errno=%d", errno);
        vTaskDelete(NULL);
        return;
    }

    struct timeval tv = { .tv_sec = 0, .tv_usec = 500000 };
    setsockopt(s_sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    // ★ 不要设置 SO_SNDBUF。曾在这里请求 128KB（注释还写着"48000字节分段"，
    //   但分段早已降到 1400 字节，那是旧代码遗留）。在 WiFi TX 缓冲为静态
    //   分配的情况下，这个 128KB 会把内存吃光，导致后续 sendto 返回
    //   errno=12 (ENOMEM)，表现为：整帧发不出去 → 帧序号不递增 →
    //   无限重发同一帧的前几段 → 客户端永远拼不齐 → 花屏 + 帧率骤降。
    //   实测 12 秒只出 1 个 seq，seg=0 被重复收到 111 次。
    //   UDP 无连接、无重传，默认发送缓冲足够；要调就调 sdkconfig 里的
    //   WIFI_DYNAMIC_TX_BUFFER_NUM，不要在这里抢内存。

    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(VISION_UDP_PORT);
    if (bind(s_sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        ESP_LOGE(TAG, "bind %d 失败 errno=%d", VISION_UDP_PORT, errno);
        close(s_sock);
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "图传服务就绪，端口 %d，等待手机指令...", VISION_UDP_PORT);

    while (1) {
        int len = recvfrom(s_sock, rx, RX_BUF_SIZE - 1, 0,
                           (struct sockaddr *)&s_client, &addr_len);
        if (len <= 0) continue;
        s_has_client = true;
        handle_command((char *)rx, len);
    }
}

esp_err_t vision_udp_start(void)
{
    s_fb_q = xQueueCreate(FB_QUEUE_LEN, sizeof(camera_fb_t *));
    if (!s_fb_q) {
        ESP_LOGE(TAG, "帧队列创建失败");
        return ESP_FAIL;
    }

    // ==================== 任务绑核（★ 别改）====================
    //
    // WiFi/lwIP 协议栈固定在 core 0（CONFIG_ESP_WIFI_TASK_PINNED_TO_CORE_0），
    // 收发任务绝不能和它抢 core 0。
    //
    // 曾经 send_task 绑在 core 0（"贴近 WiFi 更高效"的直觉），结果是反的：
    // send_task 优先级 6 高于 WiFi 任务，忙等 socket 写入时把协议栈饿死，
    // 触发速率自适应一路降级 —— 实测对端 rx bitrate 从 150Mbps 掉到
    // 6~13.5 Mbps (MCS0)，整个链路吞吐只剩 78 KB/s。
    //
    //   capture（JPEG 编码，CPU 密集）→ core 1
    //   send（socket 写入，I/O 密集）  → core 1，与 capture 共享，都让开 WiFi
    //   udp_server（命令解析，极轻）   → core 0，与 WiFi 同核但几乎不占 CPU
    //
    // 别把 send 挪回 core 0，也不要"为了负载均衡"把 capture 和 send 分到两个核
    // 而把其中一个放到 core 0。core 0 只留给 WiFi 和极轻的命令任务。
    if (xTaskCreatePinnedToCore(capture_task, "vcapture", 4096, NULL, 5, NULL, 1) != pdPASS ||
        xTaskCreatePinnedToCore(send_task, "vsend", 8192, NULL, 6, NULL, 1) != pdPASS ||
        xTaskCreatePinnedToCore(udp_server_task, "vudp", 8192, NULL, 4, NULL, 0) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

bool vision_udp_streaming(void)
{
    return s_streaming;
}

bool vision_udp_set_streaming(bool on)
{
    bool old = s_streaming;
    s_streaming = on;
    return old;
}
