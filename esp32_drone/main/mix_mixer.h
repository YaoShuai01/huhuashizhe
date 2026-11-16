/**
 * mix_mixer.h - X 型四旋翼归一化混控（对应 PX4 mixer）
 * 护花使者 ESP32-S3 飞控
 * 符号与 v3 严格一致：俯仰正→前倾，横滚正→右倾，偏航正→右转
 */
#ifndef MIX_MIXER_H
#define MIX_MIXER_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief X 型混控：总推力 + 三轴扭矩 → 四电机归一化输出 [0,1]
 * @param T   总推力 0..1
 * @param r   横滚扭矩 -1..1（正→右倾）
 * @param p   俯仰扭矩 -1..1（正→前倾）
 * @param y   偏航扭矩 -1..1（正→右转）
 * @param motor[4] 输出 {FR, FL, BR, BL} ∈ [0,1]（0=1ms 停转）
 *
 * 饱和处理（推力优先）：任一电机输出 >1 时，按比例压缩扭矩分量，
 * 使最大电机恰好等于 1，保证推力不丢、不会反向。
 */
void mix_apply(float T, float r, float p, float y, float motor[4]);

#ifdef __cplusplus
}
#endif

#endif /* MIX_MIXER_H */
