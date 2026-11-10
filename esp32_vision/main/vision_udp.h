/**
 * vision_udp - 图传协议与UDP服务（端口 8889）
 *
 * ==================== 协议定义（手机端按此实现） ====================
 *
 * 【命令】手机 → 视觉板，ASCII 文本，每条一条（不需要\r\n结尾）：
 *   VSTART [res] [fps] [q]   开始推流。res=k_cam_res索引(0~5,默认2=XGA)
 *                            fps=2~20(默认12) q=6~25(默认12)
 *   VSTOP                    停止推流
 *   VSNAP [res]              拍高清照片。res默认7=QSXGA(5MP)，拍完自动恢复推流分辨率
 *   VINFO                    查询信息 → 文本回复 VOK INFO ...
 *   VSET fps q               只改参数不换分辨率
 *   VFLIP 0|1                垂直翻转
 *   VMIR  0|1                水平镜像
 *
 * 【ACK】视觉板 → 手机，ASCII 文本：
 *   VOK <内容>  /  VERR <原因>
 *
 * 【帧数据】视觉板 → 手机，二进制，统一分段格式（推流帧通常1段，拍照大图分多段）：
 *   偏移  长度  含义
 *   0     2     魔数 0x48 0x56 ('H','V')
 *   2     1     类型：0x01=推流帧  0x02=拍照图
 *   3     1     flags：bit0=本帧起始段
 *   4     4     photo_id（u32 小端；拍照自增，推流=0）
 *   8     4     frame_seq（u32 小端，全局递增序号，用于丢帧统计）
 *   12    2     seg_idx（u16 小端，当前段号，从0起）
 *   14    2     seg_cnt（u16 小端，总段数）
 *   16    4     total_len（u32 小端，完整JPEG总字节数）
 *   20    2     seg_len（u16 小端，本段payload字节数）
 *   22    N     JPEG数据（N=seg_len，单段≤48000字节）
 *
 * 【丢包策略】UDP不重传。手机端按 (类型,photo_id,frame_seq) 拼包，
 *   seg_cnt 段收齐才算完整帧；超时(如500ms)未收齐则丢弃该帧。推流可容忍丢帧。
 *
 * 【寻址】视觉板把帧发回"最近一条命令的来源IP:端口"（手机固定用同一端口发命令即可）。
 * ==================================================================
 */
#pragma once

#include <stdbool.h>
#include "esp_err.h"

#define VISION_UDP_PORT  8889

esp_err_t vision_udp_start(void);

/** 当前是否在推流（心跳日志用） */
bool vision_udp_streaming(void);
