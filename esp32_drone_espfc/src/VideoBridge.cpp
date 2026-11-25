// P4 → 飞控 SPI 图传桥（UDP 单播版）
// 接线：P4 GPIO20/21/22 (SCLK/MOSI/CS) → 飞控 GPIO13/14/11，必须共地
// 输入：P4 发 'H''V' + type(2) + len32 + H.264 Annex-B
// 输出：手机 APP 每秒发一次订阅包 "HVS1" 到 8889，飞控把视频按 1400 字节分段单播回手机
//
// 为什么不用 TCP：ESP32 lwIP 的 TCP 发送窗口只有 5744 字节，手机省电模式下 RTT 约 50ms，
// 实测吞吐被锁在 0.4~0.9Mbps，扛不住 3Mbps 视频（每 5 秒丢 4000+ 段，画面只剩彩色竖线）。
// UDP 没有窗口限制，手机端重组后本地喂给解码器。

#include "VideoBridge.h"

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <string.h>
#include "driver/spi_slave.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#define VB_SCLK      13
#define VB_MOSI      14
#define VB_CS        11
#define VB_CHUNK     2048
#define VB_QUEUE     4
#define VB_UDP_PORT  8889
#define VB_SEG_MAX   1400
#define VB_TXQ_LEN   16
#define VB_PEER_TTL  3000   // 手机 3 秒没发订阅就停发视频

// 18 字节分片头：'H''V' 0x03 | seq(4) | idx(2) | cnt(2) | nal_len(4) | seg_len(2) | 0
#define VB_UDP_HDR   18

// 由 main.cpp 在 espfc.begin()（内部启动 WiFi AP）之后置位。
// 图传任务必须等 WiFi 就绪后才能建 socket：lwIP 未初始化时 socket 调用会断言重启。
volatile bool g_wifiReady = false;

typedef struct {
    uint32_t seq;        // 第几个 NAL
    uint32_t nal_len;    // 本 NAL 总字节
    uint16_t idx;        // 第几段
    uint16_t cnt;        // 总段数
    uint16_t len;        // 本段字节
    uint8_t  data[VB_SEG_MAX];
} VbSeg;

static QueueHandle_t s_txq = nullptr;
static IPAddress s_peer;
static volatile uint32_t s_peerMs = 0;

static uint8_t  s_hdr[8];
static int      s_hdr_n = 0;
static uint32_t s_nal_len = 0;
static uint32_t s_nal_pos = 0;
static uint16_t s_seg_idx = 0;
static uint16_t s_seg_cnt = 0;
static uint8_t  s_seg[VB_SEG_MAX];
static int      s_seg_n = 0;
static uint32_t s_frame_seq = 0;
static volatile uint32_t s_drop_segs = 0;

static void send_seg()
{
    if (s_seg_n <= 0 || !s_txq) {
        return;
    }
    static VbSeg txseg;
    txseg.seq = s_frame_seq;
    txseg.nal_len = s_nal_len;
    txseg.idx = s_seg_idx;
    txseg.cnt = s_seg_cnt;
    txseg.len = (uint16_t)s_seg_n;
    memcpy(txseg.data, s_seg, s_seg_n);
    if (xQueueSend(s_txq, &txseg, 0) != pdTRUE) {
        s_drop_segs++;   // 队列满就丢这一段，避免拖死 SPI
    }
}

// UDP 发送任务：收手机订阅包、单播视频
static void videoTxTask(void* arg)
{
    (void)arg;
    while (!g_wifiReady) {
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    vTaskDelay(pdMS_TO_TICKS(500));   // AP 配置生效后会重启一次，等它稳定

    WiFiUDP udp;
    if (!udp.begin(VB_UDP_PORT)) {
        printf("[VB] udp bind %d failed, video disabled\n", VB_UDP_PORT);
        fflush(stdout);
        vTaskDelete(nullptr);
        return;
    }
    printf("[VB] udp ready port=%d heap=%u\n", VB_UDP_PORT, (unsigned)ESP.getFreeHeap());
    fflush(stdout);

    bool peerValid = false;
    uint32_t statT = millis();
    uint32_t statBytes = 0;
    uint32_t statPkts = 0;
    static VbSeg seg;

    while (true) {
        const int n = udp.parsePacket();
        if (n > 0) {
            uint8_t buf[16];
            const int len = udp.read(buf, sizeof(buf));
            if (len >= 4 && buf[0] == 'H' && buf[1] == 'V' && buf[2] == 'S' && buf[3] == '1') {
                const IPAddress ip = udp.remoteIP();
                if (!peerValid || ip != s_peer) {
                    printf("[VB] udp peer %s\n", ip.toString().c_str());
                    fflush(stdout);
                }
                s_peer = ip;
                s_peerMs = millis();
                peerValid = true;
            }
        }

        if (xQueueReceive(s_txq, &seg, pdMS_TO_TICKS(10)) == pdTRUE) {
            if (peerValid && millis() - s_peerMs <= VB_PEER_TTL) {
                uint8_t uh[VB_UDP_HDR] = {
                    'H', 'V', 0x03,
                    (uint8_t)(seg.seq), (uint8_t)(seg.seq >> 8),
                    (uint8_t)(seg.seq >> 16), (uint8_t)(seg.seq >> 24),
                    (uint8_t)(seg.idx), (uint8_t)(seg.idx >> 8),
                    (uint8_t)(seg.cnt), (uint8_t)(seg.cnt >> 8),
                    (uint8_t)(seg.nal_len), (uint8_t)(seg.nal_len >> 8),
                    (uint8_t)(seg.nal_len >> 16), (uint8_t)(seg.nal_len >> 24),
                    (uint8_t)(seg.len), (uint8_t)(seg.len >> 8),
                    0
                };
                udp.beginPacket(s_peer, VB_UDP_PORT);
                udp.write(uh, sizeof(uh));
                udp.write(seg.data, seg.len);
                udp.endPacket();
                statBytes += seg.len;
                statPkts++;
            } else if (peerValid) {
                peerValid = false;
                printf("[VB] udp peer timeout, video paused\n");
                fflush(stdout);
            }
        }

        // 每 5 秒打印 UDP 出口速率和丢段数
        const uint32_t nowMs = millis();
        if (nowMs - statT >= 5000) {
            printf("[VB] udp %u B/s %u pkt/s drop=%u heap=%u\n",
                   (unsigned)(statBytes * 1000 / (nowMs - statT)),
                   (unsigned)(statPkts * 1000 / (nowMs - statT)),
                   (unsigned)s_drop_segs,
                   (unsigned)ESP.getFreeHeap());
            fflush(stdout);
            statT = nowMs;
            statBytes = 0;
            statPkts = 0;
        }
    }
}

static void feed_byte(uint8_t b)
{
    if (s_hdr_n < 8) {
        if (s_hdr_n == 0) {
            if (b == 'H') {
                s_hdr[0] = b;
                s_hdr_n = 1;
            }
            return;
        }
        if (s_hdr_n == 1) {
            if (b == 'V') {
                s_hdr[1] = b;
                s_hdr_n = 2;
            } else if (b != 'H') {
                s_hdr_n = 0;
            }
            return;
        }
        s_hdr[s_hdr_n++] = b;
        if (s_hdr_n == 8) {
            if (s_hdr[2] != 0x02) {
                s_hdr_n = 0;
                return;
            }
            s_nal_len = (uint32_t)s_hdr[3] | ((uint32_t)s_hdr[4] << 8) |
                        ((uint32_t)s_hdr[5] << 16) | ((uint32_t)s_hdr[6] << 24);
            if (s_nal_len == 0 || s_nal_len > 500000) {
                s_hdr_n = 0;
                return;
            }
            s_nal_pos = 0;
            s_seg_idx = 0;
            s_seg_cnt = (uint16_t)((s_nal_len + VB_SEG_MAX - 1) / VB_SEG_MAX);
            s_seg_n = 0;
        }
        return;
    }

    s_seg[s_seg_n++] = b;
    s_nal_pos++;
    if (s_seg_n == VB_SEG_MAX || s_nal_pos == s_nal_len) {
        send_seg();
        s_seg_n = 0;
        s_seg_idx++;
        if (s_nal_pos == s_nal_len) {
            s_frame_seq++;
            s_hdr_n = 0;
        }
    }
}

static void videoBridgeTask(void* arg)
{
    (void)arg;

    spi_bus_config_t buscfg = {};
    buscfg.mosi_io_num = VB_MOSI;
    buscfg.miso_io_num = -1;
    buscfg.sclk_io_num = VB_SCLK;
    buscfg.quadwp_io_num = -1;
    buscfg.quadhd_io_num = -1;
    buscfg.max_transfer_sz = VB_CHUNK;

    spi_slave_interface_config_t slvcfg = {};
    slvcfg.spics_io_num = VB_CS;
    slvcfg.flags = 0;
    slvcfg.queue_size = VB_QUEUE;
    slvcfg.mode = 0;

    if (spi_slave_initialize(SPI2_HOST, &buscfg, &slvcfg, SPI_DMA_CH_AUTO) != ESP_OK) {
        printf("[VB] spi_slave_initialize failed\n");
        vTaskDelete(nullptr);
        return;
    }

    uint8_t* bufs[VB_QUEUE] = {};
    spi_slave_transaction_t trans[VB_QUEUE] = {};

    for (int i = 0; i < VB_QUEUE; i++) {
        bufs[i] = (uint8_t*)heap_caps_malloc(VB_CHUNK, MALLOC_CAP_DMA);
        if (!bufs[i]) {
            vTaskDelete(nullptr);
            return;
        }
        trans[i].length = VB_CHUNK * 8;
        trans[i].rx_buffer = bufs[i];
        spi_slave_queue_trans(SPI2_HOST, &trans[i], portMAX_DELAY);
    }
    printf("[VB] spi ready heap=%u dma=%u\n",
           (unsigned)ESP.getFreeHeap(),
           (unsigned)heap_caps_get_free_size(MALLOC_CAP_DMA));

    uint32_t statT = millis();
    uint32_t statBytes = 0;

    while (true) {
        spi_slave_transaction_t* r = nullptr;
        if (spi_slave_get_trans_result(SPI2_HOST, &r, pdMS_TO_TICKS(100)) == ESP_OK && r) {
            const int n = (int)(r->trans_len / 8);
            const uint8_t* p = (const uint8_t*)r->rx_buffer;
            for (int i = 0; i < n; i++) {
                feed_byte(p[i]);
            }
            statBytes += (uint32_t)n;
            spi_slave_queue_trans(SPI2_HOST, r, portMAX_DELAY);
        }

        // 每 5 秒打印 SPI 吞吐：0 表示 P4 没在推流（未上电/没接好）
        const uint32_t nowMs = millis();
        if (nowMs - statT >= 5000) {
            printf("[VB] spi %u B/s heap=%u dma=%u\n",
                   (unsigned)(statBytes * 1000 / (nowMs - statT)),
                   (unsigned)ESP.getFreeHeap(),
                   (unsigned)heap_caps_get_free_size(MALLOC_CAP_DMA));
            fflush(stdout);
            statT = nowMs;
            statBytes = 0;
        }
    }
}

void videoBridgeBegin()
{
    if (!s_txq) {
        s_txq = xQueueCreate(VB_TXQ_LEN, sizeof(VbSeg));
    }
    if (!s_txq) {
        printf("[VB] tx queue alloc failed, video disabled\n");
        fflush(stdout);
        return;
    }
    printf("[VB] tx queue %u seg, heap=%u\n", (unsigned)VB_TXQ_LEN, (unsigned)ESP.getFreeHeap());
    fflush(stdout);
    xTaskCreatePinnedToCore(videoTxTask, "video_tx", 5120, nullptr, 1, nullptr, 0);
    // SPI 接收任务优先级更高，保证 20MHz 下事务总能及时重新入队
    xTaskCreatePinnedToCore(videoBridgeTask, "video_bridge", 5120, nullptr, 2, nullptr, 0);
}
