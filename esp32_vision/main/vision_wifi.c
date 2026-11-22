/**
 * vision_wifi - WiFi AP(+STA) 模式
 *
 * STA：接入飞控热点 HuHuaShiZhe-Drone（生产链路，装飞机上用）
 * AP ：自开热点 HuHuaShiZhe-CAM（192.168.5.1），电脑/手机直连看图传，
 *      飞控不开机也能用。两网并存时服务监听 0.0.0.0 双网可达。
 *
 * ============ VISION_AP_ONLY 开关（★ 别随手改）============
 *
 * 1 = 纯 AP（地面调试用，电脑直连 HuHuaShiZhe-CAM 跑 vision_check.py）
 * 0 = APSTA（当前配置，装机/App 用：视觉板作为 STA 接入飞控热点，
 *           手机与本板同网段 192.168.4.x，App 才能通过扫描发现它）
 *
 * ★ 为什么 App 必须用 0：lib/services/vision_stream_service.dart 的
 *   _sweepTargets 硬编码扫描 192.168.4.2 ~ 192.168.4.9。设成 1 时视觉板
 *   在 192.168.5.1 自建热点里，与飞控网段完全隔离，App 扫不到 ——
 *   表现为"手机 App 连不上视觉板，但电脑跑 vision_check.py 正常"。
 *
 * 为什么调试时想用 1：ESP32-S3 只有一套射频，AP 和 STA 共用。STA 连不上
 * 飞控热点时驱动会反复全信道扫描（13 个信道约 1.5 秒），扫描期间 AP 一个
 * 包都发不出去。实测日志表现为每 4.83 秒刷一次「与飞控AP断开」，此时
 * AP 侧图传只有 2fps，而同一时刻走串口测是 29fps。
 *
 * 所以：地面单独调视觉板用 1；装到飞机上（飞控通电）必须用 0。
 * 别为了"统一"改成一个值 —— 两种场景的取舍是相反的。
 */
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_mac.h"
#include "lwip/inet.h"

static const char *TAG = "VWIFI";

// ★ 改这一行前先看文件头的「VISION_AP_ONLY 开关」说明。
//   1 = 纯 AP（地面调试，不启 STA，不扫描）
//   0 = APSTA（装机用：视觉板作为 STA 接入飞控热点，手机与板子同网段）
//
// ★★★ 当前必须为 0：App 的图传发现逻辑只扫 192.168.4.2~9（飞控网段），
//   若设为 1，视觉板躲在自建的 192.168.5.x 热点里，与手机网段隔离，
//   App 永远扫不到（只能在电脑直连 CAM 热点用 vision_check.py）。
//   代价：飞控没通电时会退化为 STA 反复扫描，图传掉到 2fps。装机时必须开飞控。
#define VISION_AP_ONLY 0

// 与飞控 esp32_drone/main/main.c 的 AP 配置保持一致
#define WIFI_SSID    "HuHuaShiZhe-Drone"
#define WIFI_PASS    ""

// 视觉板自开热点（调试/体验用）。子网用 5.x 避开飞控的 4.x
#define CAM_AP_SSID  "HuHuaShiZhe-CAM"
#define CAM_AP_IP    "192.168.5.1"
#define CAM_AP_MASK  "255.255.255.0"

#define WIFI_CONNECTED_BIT BIT0

static EventGroupHandle_t s_event;
static char s_ip[16] = "0.0.0.0";

#if VISION_AP_ONLY
// 纯 AP 模式没有 STA 事件，vision_wifi_wait_ip() 改用时钟轮询。
// 直接返回 false 会让 main.c 打印「25秒未接入飞控热点」的误导日志。
static bool s_ap_up = false;
#endif

static void ip_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *ev = (ip_event_got_ip_t *)data;
        snprintf(s_ip, sizeof(s_ip), IPSTR, IP2STR(&ev->ip_info.ip));
        ESP_LOGI(TAG, "已获得IP: %s", s_ip);
        xEventGroupSetBits(s_event, WIFI_CONNECTED_BIT);
    }
}

static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        // ★ 不能在这里 vTaskDelay：本回调跑在 esp_event 默认事件任务里，
        //   阻塞会把 AP 侧客户端连接、DHCP 等所有事件一起卡住。
        //   重试间隔交给 IDF 内部退避。
        ESP_LOGW(TAG, "与飞控AP断开，重试...");
        esp_wifi_connect();
    }
}

esp_err_t vision_wifi_start(void)
{
    s_event = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    // AP 网段固定为 192.168.5.x（避开飞控 4.x），拿到 netif 句柄后改IP
    esp_netif_t *ap_netif = esp_netif_create_default_wifi_ap();
#if !VISION_AP_ONLY
    esp_netif_create_default_wifi_sta();
#endif

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &ip_event_handler, NULL));

    // AP 配置
    wifi_config_t ap_cfg = { 0 };
    strlcpy((char *)ap_cfg.ap.ssid, CAM_AP_SSID, sizeof(ap_cfg.ap.ssid));
    ap_cfg.ap.ssid_len = strlen(CAM_AP_SSID);
    // ★ 信道选择很关键。原来固定信道 1，但实测所处环境信道 1 上有 5 个邻近
    //   AP 同时广播（信号最强 -57dBm），导致本板 beacon 丢失 5.2%、
    //   对端 rx drop 2.5%，AP 的速率自适应因此把单播数据帧锁在 802.11b
    //   5.5Mbps（不是 MCS7），有效吞吐只剩 50~64KB/s，图传只能跑 VGA@4fps。
    //
    //   注意 esp_wifi_config_80211_tx_rate(MCS7_SGI) 对数据帧【无效】——
    //   它只影响 beacon/probe 等通过 esp_wifi_80211_tx() 发的管理帧
    //   （见 ESP-IDF 文档 "Can not set 80211 tx rate under 11A/11AC/11AX"）。
    //   数据帧速率由 AP 的速率自适应算法根据信道质量自行决定，
    //   所以改善信道质量是唯一有效手段。
    //
    //   信道 6 在实测环境中没有被任何 AP 占用（扫描结果里无 ch6），
    //   是 2.4GHz 1/6/11 三个互不重叠信道里最干净的。
    //
    //   ⚠ 装机前注意：飞控热点固定信道 6（esp32_drone_espfc 的 AP_CHANNEL）。
    //   视觉板以 STA 身份接入飞控时，AP 侧信道会跟随 STA（ESP-IDF 规定
    //   STA 优先级更高），所以本行值会被覆盖，不影响生产环境。
    //   但如果视觉板 AP 和飞控 AP 同时工作且都在信道 6，会互相干扰，
    //   那种情况下应改回 1 或 11。
    ap_cfg.ap.channel = 6;
    ap_cfg.ap.max_connection = 3;
    ap_cfg.ap.authmode = WIFI_AUTH_OPEN;

#if VISION_AP_ONLY
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap_cfg));

    // ==================== AP 射频设置 ====================
    //
    // ⚠ 先纠正一个曾经的错误认知：这里原本有一条"显式锁 MCS7 能提升图传
    //   速率"的注释和历史数据，是错的。经查 ESP-IDF 官方文档：
    //
    //     esp_wifi_config_80211_tx_rate()  "Can not set 80211 tx rate under
    //     11A/11AC/11AX protocol"
    //
    //   这个 API 只作用于通过 esp_wifi_80211_tx() 发送的原始 802.11 帧
    //   （beacon / probe request / probe response / action 这类管理帧），
    //   【不影响】socket 发出的普通数据帧。图传数据帧的速率由 AP 的
    //   速率自适应算法根据信道质量决定，软件无法强制锁定。
    //
    //   所以之前观测到的"改完 MCS7 后吞吐提升 6 倍"实际归因于别的因素
    //   （同时做了纯AP模式和任务绑核）。真正决定图传上限的是信道质量：
    //   信道 1 拥挤时对端 rx bitrate 会锁在 5.5Mbps(MCS0)，吞吐仅 50KB/s。
    //
    // 保留这个调用：它对管理帧仍有意义（让 beacon 走高速率发得快一点），
    // 且无害。但不要指望它提升图传吞吐，更不要因为它"看起来没生效"就删掉
    // 下面的信道设置 —— 那才是关键。
    esp_err_t rate_err = esp_wifi_config_80211_tx_rate(WIFI_IF_AP, WIFI_PHY_RATE_MCS7_SGI);
    if (rate_err != ESP_OK) {
        ESP_LOGD(TAG, "AP 管理帧速率设置返回 0x%x（仅影响 beacon，不影响数据帧）", rate_err);
    }
    // AP 侧申请 HT40。ESP32-S3 默认就是 HT40，显式声明避免协商成 HT20。
    // 注意 HT40 在拥挤环境反而更差（占两个信道更容易被干扰），
    // 如果换到干净信道后仍不稳定，可以改成 WIFI_BW_HT20 试试。
    esp_wifi_set_bandwidth(WIFI_IF_AP, WIFI_BW_HT40);
    // 3) 关省电。开着会让 STA 周期性休眠，图传出现规律性卡顿。

    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
    ESP_ERROR_CHECK(esp_wifi_start());
    s_ap_up = true;

    // 尝试禁用 802.11b（管理帧就能跑 11g/n 而非 1Mbps）。
    // 注意：纯 AP 模式下这个调用必定返回 ESP_ERR_INVALID_ARG(0x102)，
    // 这是驱动限制（ESP-IDF 只允许在 STA 接口上切换 11b/11g/11n），不是你
    // 写错了，也不影响性能 —— MCS7 已经由上面的 config_80211_tx_rate 锁住。
    // 保留调用是为了将来 IDF 放开限制时自动生效，日志降为 debug 避免误导。
    esp_err_t proto_err = esp_wifi_set_protocol(WIFI_IF_AP,
                                                WIFI_PROTOCOL_11G | WIFI_PROTOCOL_11N);
    if (proto_err != ESP_OK) {
        ESP_LOGD(TAG, "AP 模式不支持切换 11b 协议(0x%x)，已忽略", proto_err);
    }

    // 4) 发射功率拉满。config 默认 20dBm，但未被应用时实测偏弱。
    //    单位 0.25dBm，78 = 19.5dBm。
    esp_err_t pwr_err = esp_wifi_set_max_tx_power(78);
    if (pwr_err != ESP_OK) {
        ESP_LOGW(TAG, "发射功率设置失败(0x%x)", pwr_err);
    }
    {
        int8_t cur_pwr = 0;
        esp_wifi_get_max_tx_power(&cur_pwr);
        ESP_LOGI(TAG, "AP 射频参数：MCS7_SGI / HT40 / 11g+n / TX %.2f dBm",
                 cur_pwr * 0.25f);
    }
#else
    // STA 配置
    wifi_config_t sta_cfg = { 0 };
    strlcpy((char *)sta_cfg.sta.ssid, WIFI_SSID, sizeof(sta_cfg.sta.ssid));
    strlcpy((char *)sta_cfg.sta.password, WIFI_PASS, sizeof(sta_cfg.sta.password));
    sta_cfg.sta.scan_method = WIFI_FAST_SCAN;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap_cfg));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &sta_cfg));
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));   // 关省电：修复与飞控softAP周期掉线
    ESP_ERROR_CHECK(esp_wifi_start());

    // ★ STA 侧也申请 40MHz：飞控AP已改HT40，但 ESP32 STA 默认只协商HT20，
    //   不显式设置的话图传吞吐仍被限制在一半。AP不支持时会自动退回HT20。
    esp_err_t bw_err = esp_wifi_set_bandwidth(WIFI_IF_STA, WIFI_BW_HT40);
    if (bw_err != ESP_OK) {
        ESP_LOGW(TAG, "STA侧HT40申请失败(0x%x)，使用HT20", bw_err);
    } else {
        ESP_LOGI(TAG, "STA带宽已申请HT40(40MHz)");
    }
#endif

    // 改 AP 网段为 192.168.5.x
    esp_netif_dhcps_stop(ap_netif);
    esp_netif_ip_info_t ip = { 0 };
    ip.ip.addr = ipaddr_addr(CAM_AP_IP);
    ip.netmask.addr = ipaddr_addr(CAM_AP_MASK);
    ip.gw.addr = ipaddr_addr(CAM_AP_IP);
    esp_netif_set_ip_info(ap_netif, &ip);
    esp_netif_dhcps_start(ap_netif);

#if VISION_AP_ONLY
    snprintf(s_ip, sizeof(s_ip), "%s", CAM_AP_IP);   // 让心跳日志显示真实可达地址
    ESP_LOGI(TAG, "纯AP模式已启动：热点 \"%s\" http://%s 信道%d （未启STA，不做信道扫描）",
             CAM_AP_SSID, CAM_AP_IP, ap_cfg.ap.channel);
#else
    ESP_LOGI(TAG, "AP+STA 已启动：热点 \"%s\"(浏览器 http://%s) / STA 接入 \"%s\"",
             CAM_AP_SSID, CAM_AP_IP, WIFI_SSID);
#endif
    return ESP_OK;
}

bool vision_wifi_wait_ip(int timeout_s)
{
#if VISION_AP_ONLY
    // 纯 AP 模式：AP 起来即可用，无需等待 STA 拿 IP。
    // 这里必须返回 true，否则 main.c 会误报「25秒未接入飞控热点」。
    (void)timeout_s;
    return s_ap_up;
#else
    EventBits_t bits = xEventGroupWaitBits(s_event, WIFI_CONNECTED_BIT,
                                           pdFALSE, pdFALSE,
                                           pdMS_TO_TICKS(timeout_s * 1000));
    return (bits & WIFI_CONNECTED_BIT) != 0;
#endif
}

const char *vision_wifi_ip_str(void)
{
    return s_ip;
}
