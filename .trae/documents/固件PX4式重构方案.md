# 护花使者 ESP32-S3 固件 PX4 工程思维重构方案

## Context（背景与目标）

当前固件是单文件"事件驱动开环"结构：UDP 收到指令 → 直接改全局变量 → 立即混控输出 PWM，无传感器反馈、无固定控制频率、无模块化分层。用户希望借鉴 PX4 的工程思维重构：**模块化分层 + 固定频率控制环 + 传感器反馈闭环**（姿态自稳）。

用户已提供 **MPU6050** 模块（芯片本身为 6 轴：3 轴陀螺 + 3 轴加速度计，即使按 3 轴陀螺使用也可拿到加速度计做姿态融合），接口未定 → 本方案推荐 **I2C**。

**硬性约束（必须保持兼容）：**
- UDP 协议键名/范围/语义不变（App 端零改动，App 为纯发送）
- X 型混控符号不变（fr=+P−R−Y 等），与现有试飞验证一致
- 电调 PWM：50Hz/14bit，1ms 停~2ms 最大，上电必须输出 1ms 最低油门
- 水泵：GPIO18，5kHz/8bit，6 档力度 {0,115,140,166,191,224,255}
- 飞行状态机语义不变；心跳 3s 超时/WiFi 断开 → 紧急停机
- 高度无气压计，继续模拟（油门 → 模拟高度 → 推力）

## 硬件接线（新增 MPU6050）

| MPU6050 引脚 | ESP32-S3 引脚 | 说明 |
|---|---|---|
| VCC | 3V3 | 与 S3 共地，同 3.3V 电源 |
| GND | GND | 共地 |
| SDA | GPIO8 | I2C 数据线 |
| SCL | GPIO9 | I2C 时钟线 |
| AD0 | GND（悬空） | 地址 0x68 |
| XDA/XCL/INT | 不接 | 本项目不用 |

注：GPIO8/9 非 strapping 引脚（S3 仅 GPIO0/3/45/46 为 strapping），是 I2C 标准安全选择。GY-521 模块自带 4.7k 上拉；I2C 与电机 PWM 线避免平行走线。

## 目标架构（main/ 下 10 个文件）

| 文件 | 职责 | 对应 PX4 概念 |
|---|---|---|
| `drone_types.h` | 共享数据类型（imu/attitude/setpoint/rc/状态枚举） | uORB 消息定义 |
| `prm_params.c/.h` | PX4 风格参数表（PID 增益、死区、最大倾角、悬停油门，编译期默认值） | parameters |
| `drv_mpu6050.c/.h` | I2C 驱动（v5.3 i2c_master API）、寄存器配置、静止标定 | Sensors 驱动 |
| `est_attitude.c/.h` | Mahony 互补滤波，四元数→欧拉角，输出体轴角速度 | attitude_estimator_q |
| `ctl_controller.c/.h` | 外环姿态 P + 内环速率 PID，250Hz，输出三轴扭矩 | mc_att_control / mc_rate_control |
| `mix_mixer.c/.h` | X 型归一化混控 + 饱和处理（推力优先） | mixer |
| `cmd_commander.c/.h` | 状态机、解锁逻辑、摇杆→设定值映射 | commander |
| `rc_udp.c/.h` | UDP 收包、K=V; 解析、通道死区/限幅 | rc_update |
| `out_pwm.c/.h` | LEDC 输出（电调 50Hz/14bit、水泵 5kHz/8bit）、1ms 安全油门 | actuator_outputs |
| `main.c` | 仅保留：NVS、WiFi AP、模块初始化、任务创建 | 系统启动 |

## 模块间数据流

```
 App (50Hz UDP, 只发不收)
   │  ARM/PIT/ROL/THR/YAW/SPR/TAKEOFF/LAND
   ▼
┌─ udp_server_task (prio5, core0)  → rc_parse → rc_input_t [互斥锁]
│        ▼
│  commander_task (prio7, core1, 100Hz) → 状态机+摇杆→设定值 → ctl_setpoint_t [互斥锁]
└─────────────────────────────────┘
 MPU6050 (I2C 400kHz, 1kHz esp_timer 信号量)
   ▼
┌─ imu_task (prio9, core1, 1kHz) → mpu6050_read → 去偏移 → Mahony → attitude_data_t
└────────────────────────────────────────┘
        ▼
┌─ ctl_task (prio8, core1, 250Hz) → 姿态环P → 速率环PID → 扭矩 → mix_apply → out_set_motors
└──────────────────────────── LEDC 硬件 50Hz 波形 → 4×电调 + 泵
 heartbeat_task (prio4, core0, 2Hz) + wifi_event_handler → 紧急停机通知
```

任务划分：imu(9, 4096B, 1kHz) / ctl(8, 4096B, 250Hz) / commander(7, 2048B, 100Hz) / udp(5, 4096B, 事件) / heartbeat(4, 2048B, 2Hz)。

**数据流组织：共享结构体 + 互斥锁**（非 FreeRTOS 队列）：传感器帧/摇杆设定值属"最新值"语义，PX4 uORB 即覆盖式；互斥锁临界区仅一次 memcpy，250Hz 下开销可忽略。ISR 只 `xSemaphoreGiveFromISR`，I2C 事务只在任务上下文（i2c_master API 阻塞）。

## 关键算法

### Mahony（est_attitude，dt=1ms，β=0.2）
```
v = R(q)ᵀ·(0,0,1)          # 四元数预测重力
e = a_meas × v             # 加速度计修正
ω = ω_gyro + β·e           # 修正角速度（+可选积分项 ki≈0.01）
q̇ = 0.5·q⊗(0,ω);  q += q̇·dt;  归一化
```
欧拉角：pitch≈2(qw·qy−qz·qx)，roll≈2(qw·qx+qy·qz)，yaw=atan2(...)（限倾角 25° 小角度近似）。**yaw 不做角度环**（无磁力计会漂），摇杆直接给 yaw 角速率。

### 串级控制（ctl_step，250Hz）
```
外环：sp_rate = Kp_att·(tilt_setpoint − tilt_est)     # Kp_att≈4~6
       yaw: sp_yaw_rate = yaw_rate_cmd（摇杆直接）
内环：e = sp_rate − gyro_rate
      I += e·dt（限幅 ±0.25；非飞行态/饱和时冻结）
      τ = Kp·e + Ki·I − Kd·gyro_ratė（D 作用测量微分，高通）
      yaw 环只用 P：τ_yaw = yaw_rate_p·e
扭矩→混控单位：mix_* = clamp(τ·torque_scale, −1, 1)
```

### 混控（mix_mixer，符号与原版严格一致）
```
fr = T + p − r − y;  fl = T + p + r + y
br = T − p − r + y;  bl = T − p + r − y      # T∈[0,1] 推力
```
饱和处理（推力优先）：任一电机 >1 时，取超额 max_excess，k=(1−T)/max_excess，r/p/y 全乘 k 重算，再 clamp [0,1]。`out_set_motors(0)` = 输出 1ms（非 0 占空比），紧急停机即全 1ms。

### 摇杆映射（cmd_commander）
```
v_db = 死区(8)：|v|≤8 → 0，超出按比例线性（非阶跃）
tilt_pitch = (v_db_pit/100)·max_tilt(25°=0.4363rad)
tilt_roll  = (v_db_rol/100)·max_tilt
yaw_rate   = (v_db_yaw/100)·max_yaw_rate(2.5 rad/s)
油门→模拟高度（沿用 ALT_RATE_SCALE=2，dt=10ms 在 commander 积分）：
  alt_target += (v_db_thr/100)·2·(dt/1000)；clamp(hover_alt=50, max_alt=200)
T = hover_thrust(0.13) + (alt_target−50)/150·(1−0.13)
```

## MPU6050 初始化要点（ESP-IDF v5.3 i2c_master API）

```
i2c_new_master_bus({i2c_port=I2C_NUM_0, sda=GPIO8, scl=GPIO9,
                    glitch_ignore_cnt=7, 内部上拉按需});
i2c_master_bus_add_device(dev_addr=0x68, scl_speed=400000);
寄存器：PWR_MGMT_1(0x6B)=0x01（清SLEEP，时钟选PLL Z轴陀螺）
        SMPLRT_DIV(0x19)=0（DLPF开时陀螺1kHz）
        CONFIG(0x1A)=0x02（DLPF=94Hz）
        GYRO_CONFIG(0x1B)=0x08（±500dps，65.5 LSB/dps）
        ACCEL_CONFIG(0x1C)=0x00（±2g，16384 LSB/g）
WHO_AM_I(0x75)==0x68 校验；自 0x3B 突发读 14 字节（ACCEL 6B+TEMP 2B+GYRO 6B）
标定：上电静止采 200 帧，gyro_off=mean(raw)，accel_off=mean(raw)−(0,0,16384)，存 RAM
```

## sdkconfig 必改

- `CONFIG_ESPTOOLPY_FLASHSIZE` 2MB → **16MB**（板子 N16R8 实际 16MB，分区表随之重建，app 偏移仍 0x10000，烧录命令不变）
- `CONFIG_FREERTOS_HZ` 100 → **1000**（否则 vTaskDelayUntil 最小粒度 10ms，无法实现 1kHz IMU / 250Hz 控制环）
- `main/CMakeLists.txt` SRCS 改为全部 10 个 .c

## 安全机制（保留 + 新增）

**保留**：上电 1ms 最低油门（out_init 最先执行，含电调自检）；心跳 3s → EMERGENCY；WiFi 断开 → EMERGENCY；失锁/急停全 1ms；油门 ≤−80 自动降落；手动/一键起飞降落语义。

**新增**：
- IMU 无效禁止解锁（WHO_AM_I 失败 / 标定失败 / 连续 >20 帧读失败 → cmd_notify_imu_invalid；飞行中 IMU 失效立即 EMERGENCY）
- 积分器管理：非 FLYING/HOVERING 清零、饱和冻结
- 上锁时复位姿态参考（est_attitude_reset），防止下次解锁带残余倾角误差

**注意（兼容性决策）**：喷洒不新增"仅解锁可用"门控，保持原行为（任何时候可喷），避免超出本次重构范围的行为变更。

## 实施步骤

1. **sdkconfig + CMakeLists**：FLASHSIZE=16MB、FREERTOS_HZ=1000、SRCS 登记全部模块
2. **写 drone_types.h + prm_params**：共享类型与参数表（编译期默认值）
3. **写 drv_mpu6050 + est_attitude**：I2C 驱动 + Mahony 姿态解算
4. **写 ctl_controller + mix_mixer + out_pwm**：串级 PID + 归一化混控 + LEDC 输出（out_pwm 保留现有 1ms 安全逻辑）
5. **写 rc_udp + cmd_commander**：UDP 解析（沿用现有 parse_command 逻辑改造）+ 状态机 + 摇杆映射
6. **重写 main.c**：模块初始化 + 5 个任务创建
7. **同步 + 编译**：将 main/ 全部文件复制到 C:\esp32_esc_src（独立副本，非联接点），在 ASCII 路径编译
8. **烧录 + 验证**（见下）

## 验证

**编译验证**：`C:\esp32_esc_src` 下 idf.py build 通过，产物 3 个 bin 生成。

**烧录**：COM6（原生 USB-OTG），--flash_size 16MB，命令沿用：
```
esptool --chip esp32s3 -p COM6 -b 460800 --before default_reset --after hard_reset \
  write_flash --flash_mode dio --flash_size 16MB --flash_freq 80m \
  0x0 bootloader.bin  0x8000 partition-table.bin  0x10000 esp32_drone.bin
```

**串口日志验证**（USB-OTG 口自带 USB Serial/JTAG 日志）：
1. 启动日志：WHO_AM_I=0x68 校验通过；标定完成（陀螺零偏数值合理）；WiFi AP 启动
2. 静止时：roll/pitch ≈ 0（±1°内），晃动板子姿态方向跟随正确
3. 拆桨手持：推摇杆解锁，小油门测试电机响应方向正确、无振荡
4. 安全路径：断开 App（心跳超时 3s）、关闭 WiFi 热点 → 日志显示 EMERGENCY，电机输出 1ms
5. 喷洒：SPR 1~6 挡位对应 PWM 占空比正确

**App 端**：无需改动（协议 100% 兼容），直接连接 `HuHuaShiZhe-Drone` 联调。

## 风险与注意

- PID 参数（Kp_att、rate Kp/Ki/Kd、torque_scale）为初始经验值，需地面试飞整定；所有电机测试必须拆桨
- 无磁力计 → yaw 用速率控制规避漂移，App 表现与原版一致
- 1kHz tick 带来约 2~4% CPU 开销，可接受；imu/ctl 固定 core1
- 每次编译需先同步到 C:\esp32_esc_src 再构建
