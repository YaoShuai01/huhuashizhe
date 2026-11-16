/**
 * mix_mixer.c - X 型四旋翼归一化混控
 * 护花使者 ESP32-S3 飞控
 *
 * 电机布局（俯视图）：
 *   FL(CCW) ---- FR(CW)
 *     |    X     |
 *   BL(CW) ---- BR(CCW)
 *
 * 混控方程（与 v3 验证过的符号严格一致）：
 *   fr = T + p - r - y
 *   fl = T + p + r + y
 *   br = T - p - r + y
 *   bl = T - p + r - y
 */
#include <math.h>
#include "mix_mixer.h"

void mix_apply(float T, float r, float p, float y, float motor[4])
{
    // 限幅输入
    if (T < 0.0f) T = 0.0f;
    if (T > 1.0f) T = 1.0f;
    if (r < -1.0f) r = -1.0f;
    if (r >  1.0f) r =  1.0f;
    if (p < -1.0f) p = -1.0f;
    if (p >  1.0f) p =  1.0f;
    if (y < -1.0f) y = -1.0f;
    if (y >  1.0f) y =  1.0f;

    float fr = T + p - r - y;
    float fl = T + p + r + y;
    float br = T - p - r + y;
    float bl = T - p + r - y;

    // 推力优先饱和处理
    float mx = fmaxf(fmaxf(fr, fl), fmaxf(br, bl));
    if (mx > 1.0f && T < 1.0f) {
        // 压缩扭矩分量，使最大电机恰好=1
        float k = (1.0f - T) / (mx - T);
        r *= k;
        p *= k;
        y *= k;
        fr = T + p - r - y;
        fl = T + p + r + y;
        br = T - p - r + y;
        bl = T - p + r - y;
    }

    // 最终限幅
    motor[0] = fr < 0.0f ? 0.0f : (fr > 1.0f ? 1.0f : fr);   // FR
    motor[1] = fl < 0.0f ? 0.0f : (fl > 1.0f ? 1.0f : fl);   // FL
    motor[2] = br < 0.0f ? 0.0f : (br > 1.0f ? 1.0f : br);   // BR
    motor[3] = bl < 0.0f ? 0.0f : (bl > 1.0f ? 1.0f : bl);   // BL
}
