// P4 → 飞控 SPI 图传桥
// 接线：P4 GPIO20/21/22 (SCLK/MOSI/CS) → 飞控 GPIO13/14/15，必须共地
// 协议：P4 发 'H''V' + type(2) + len32 + H.264 Annex-B
// 本桥按 1400 字节分段，UDP 8889 广播给手机/电脑

#include "VideoBridge.h"

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <string.h>
#include "driver/spi_slave.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define VB_SCLK      13
#define VB_MOSI      14
#define VB_CS        11
#define VB_CHUNK     2048
#define VB_QUEUE     4
#define VB_UDP_PORT  8889
#define VB_SEG_MAX   1400
#define VB_HTTP_PORT 8080

static WiFiServer s_http(VB_HTTP_PORT);
static WiFiClient s_http_client;

static uint8_t  s_hdr[8];
static int      s_hdr_n = 0;
static uint32_t s_nal_len = 0;
static uint32_t s_nal_pos = 0;
static uint16_t s_seg_idx = 0;
static uint16_t s_seg_cnt = 0;
static uint8_t  s_seg[VB_SEG_MAX];
static int      s_seg_n = 0;
static uint32_t s_frame_seq = 0;

static void send_seg(WiFiUDP& udp, const IPAddress& bc)
{
    if (s_seg_n <= 0 || bc[0] == 0) {
        return;
    }
    uint8_t uh[18] = {
        'H', 'V', 0x03,
        (uint8_t)(s_frame_seq), (uint8_t)(s_frame_seq >> 8),
        (uint8_t)(s_frame_seq >> 16), (uint8_t)(s_frame_seq >> 24),
        (uint8_t)(s_seg_idx), (uint8_t)(s_seg_idx >> 8),
        (uint8_t)(s_seg_cnt), (uint8_t)(s_seg_cnt >> 8),
        (uint8_t)(s_nal_len), (uint8_t)(s_nal_len >> 8),
        (uint8_t)(s_nal_len >> 16), (uint8_t)(s_nal_len >> 24),
        (uint8_t)(s_seg_n), (uint8_t)(s_seg_n >> 8),
        0
    };
    udp.beginPacket(bc, VB_UDP_PORT);
    udp.write(uh, sizeof(uh));
    udp.write(s_seg, s_seg_n);
    udp.endPacket();

    // 手机 VLC / 浏览器 HTTP 直连（裸 H.264 Annex-B）
    if (s_http_client && s_http_client.connected()) {
        if (s_http_client.write(s_seg, s_seg_n) != (size_t)s_seg_n) {
            s_http_client.stop();
        }
    }
}

static void feed_byte(uint8_t b, WiFiUDP& udp, const IPAddress& bc)
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
        send_seg(udp, bc);
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
    vTaskDelay(pdMS_TO_TICKS(1200));   // 等 WiFi AP 起来

    WiFiUDP udp;
    udp.begin(VB_UDP_PORT);
    s_http.begin();
    s_http.setNoDelay(true);

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

    while (true) {
        const IPAddress ip = WiFi.softAPIP();
        const IPAddress bc(ip[0], ip[1], ip[2], 255);

        WiFiClient nc = s_http.available();
        if (nc) {
            if (s_http_client) {
                s_http_client.stop();
            }
            nc.setNoDelay(true);
            // 丢弃 HTTP 请求头（最多等 200ms）
            uint32_t t0 = millis();
            while (nc.connected() && millis() - t0 < 200) {
                if (nc.available()) {
                    String line = nc.readStringUntil('\n');
                    if (line == "\r" || line.length() == 0) break;
                } else {
                    delay(5);
                }
            }
            nc.print("HTTP/1.1 200 OK\r\n"
                     "Content-Type: video/h264\r\n"
                     "Cache-Control: no-cache\r\n"
                     "Connection: close\r\n\r\n");
            s_http_client = nc;
        }

        spi_slave_transaction_t* r = nullptr;
        if (spi_slave_get_trans_result(SPI2_HOST, &r, pdMS_TO_TICKS(100)) == ESP_OK && r) {
            const int n = (int)(r->trans_len / 8);
            const uint8_t* p = (const uint8_t*)r->rx_buffer;
            for (int i = 0; i < n; i++) {
                feed_byte(p[i], udp, bc);
            }
            spi_slave_queue_trans(SPI2_HOST, r, portMAX_DELAY);
        }
    }
}

void videoBridgeBegin()
{
    xTaskCreatePinnedToCore(videoBridgeTask, "video_bridge", 6144, nullptr, 1, nullptr, 0);
}
