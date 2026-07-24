# 护花使者 APP 测试用例文档

## TC-UNIT: 单元测试用例

### TC-UNIT-01: WeatherData 数据模型
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-01 |
| 测试目标 | WeatherData 模型创建、属性计算、工厂方法 |
| 前置条件 | 无 |
| 步骤 | 1. 创建正常WeatherData 2. 创建empty() 3. 测试isWindWarning边界 4. 测试isRainWarning边界 5. 测试weatherIcon映射 |
| 预期 | 属性正确, 边界值触发正确, 所有天气码对应图标正确 |

### TC-UNIT-02: AiChatMessage 序列化
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-02 |
| 测试目标 | AiChatMessage JSON序列化/反序列化 |
| 步骤 | 1. 创建消息 2. toJson() 3. fromJson() 4. 验证往返一致性 |
| 预期 | 序列化往返后数据一致 |

### TC-UNIT-03: DeviceStatus / BtConnectionState
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-03 |
| 测试目标 | 设备状态模型和蓝牙连接状态枚举 |
| 步骤 | 1. 创建各状态DeviceStatus 2. 验证isConnected 3. 验证各属性 |
| 预期 | 状态判断正确 |

### TC-UNIT-04: CommandFrame 协议
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-04 |
| 测试目标 | 蓝牙命令帧编码和CRC16校验 |
| 步骤 | 1. 创建CommandFrame 2. toBytes() 3. 验证帧头帧尾 4. 验证CRC |
| 预期 | 帧格式正确, CRC16校验正确 |

### TC-UNIT-05: WeatherService 风力等级转换
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-05 |
| 测试目标 | 风力等级字符串转m/s |
| 步骤 | 1. 测试0级~12级 2. 测试无效输入 3. 测试边界 |
| 预期 | 转换结果与风速表一致 |

### TC-UNIT-06: WeatherService 风向文字转角度
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-06 |
| 测试目标 | 风向文字转角度 |
| 步骤 | 1. 测试8个基本方向 2. 测试组合方向 3. 测试无风 |
| 预期 | 角度正确 |

### TC-UNIT-07: UpdateInfo 版本号解析
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-07 |
| 测试目标 | 版本号解析和比较 |
| 步骤 | 1. 解析v1.2.0 → 10200 2. 解析v1.0.0 → 10000 3. 解析v2.0.0 → 20000 |
| 预期 | 版本号解析正确 |

### TC-UNIT-08: LocalDatabase 预设CRUD
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-08 |
| 测试目标 | 预设增删改查 |
| 步骤 | 1. addPreset 2. getPresets 3. updatePreset 4. deletePreset |
| 预期 | CRUD操作正确 |

### TC-UNIT-09: LocalDatabase 设置读写
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-09 |
| 测试目标 | 布尔设置读写 |
| 步骤 | 1. setBool true 2. getBool 3. setBool false 4. getBool |
| 预期 | 读写一致 |

### TC-UNIT-10: LocalDatabase 收藏管理
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-10 |
| 测试目标 | 收藏切换 |
| 步骤 | 1. toggleFavorite 2. getFavorites 3. 再次toggle 4. 验证移除 |
| 预期 | 切换正确 |

### TC-UNIT-11: LocalDatabase 通用KV
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-11 |
| 测试目标 | set/get/remove操作 |
| 步骤 | 1. set 2. get 3. remove 4. get(nil) |
| 预期 | 读写删正确 |

### TC-UNIT-12: AiChatState copyWith
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-12 |
| 测试目标 | AiChatState不可变拷贝 |
| 步骤 | 1. 创建state 2. copyWith部分字段 3. 验证未修改字段不变 |
| 预期 | copyWith正确 |

### TC-UNIT-13: UpdateState 状态机
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-13 |
| 测试目标 | UpdateState各状态转换 |
| 步骤 | 1. 创建idle 2. checking 3. updateAvailable 4. downloading 5. downloaded 6. error |
| 预期 | 状态转换正确 |

### TC-UNIT-14: BluetoothService 状态管理
| 项目 | 内容 |
|------|------|
| 用例ID | TC-UNIT-14 |
| 测试目标 | 蓝牙服务状态流转 |
| 步骤 | 1. 初始状态 2. 更新连接状态 3. 订阅状态流 |
| 预期 | 状态更新正确, 流推送正确 |

## TC-INTG: 集成测试用例

### TC-INTG-01: 天气API真实调用
| 项目 | 内容 |
|------|------|
| 用例ID | TC-INTG-01 |
| 测试目标 | 中国天气网API获取8大城市天气 |
| 步骤 | 对北京、武汉、广州、深圳、杭州、上海、成都、南京分别调用 |
| 预期 | 全部返回有效数据 |

### TC-INTG-02: 天气API城市代码匹配
| 项目 | 内容 |
|------|------|
| 用例ID | TC-INTG-02 |
| 测试目标 | city_codes.json加载和城市匹配 |
| 步骤 | 1. 加载城市代码 2. 匹配北京 3. 匹配武汉 4. 匹配不存在的城市 |
| 预期 | 匹配正确 |

### TC-INTG-03: AI聊天消息持久化
| 项目 | 内容 |
|------|------|
| 用例ID | TC-INTG-03 |
| 测试目标 | AI对话历史本地存储和恢复 |
| 步骤 | 1. 发送消息 2. 保存历史 3. 重新加载 4. 验证消息一致性 |
| 预期 | 持久化恢复正确 |

### TC-INTG-04: 预设Provider完整流程
| 项目 | 内容 |
|------|------|
| 用例ID | TC-INTG-04 |
| 测试目标 | PresetsNotifier增删改查 |
| 步骤 | 1. addPreset 2. 验证state 3. updatePreset 4. 验证state 5. deletePreset 6. 验证空 |
| 预期 | CRUD全流程正确 |

### TC-INTG-05: 更新检测版本比较
| 项目 | 内容 |
|------|------|
| 用例ID | TC-INTG-05 |
| 测试目标 | 版本比较算法 |
| 步骤 | 1. 远程1.2.0 vs 本地1.1.0 → 有更新 2. 远程1.0.0 vs 本地1.2.0 → 无更新 3. 远程1.2.0 vs 本地1.2.0 → 无更新 |
| 预期 | 比较正确 |

## TC-SYS: 系统测试用例

### TC-SYS-01 ~ TC-SYS-25: 页面渲染和交互测试
| 用例ID | 页面 | 验证点 |
|--------|------|--------|
| TC-SYS-01 | SplashPage | Logo居中, 文字显示, 无异常 |
| TC-SYS-02 | SettingsPage | 三个开关存在, 可切换 |
| TC-SYS-03 | ManualPage | 5个文档卡片, 可展开 |
| TC-SYS-04 | FeatureIntroPage | 8个功能介绍卡片 |
| TC-SYS-05 | OpenSourceLicensePage | 11个开源许可 |
| TC-SYS-06 | LegalDetailPage | 标题和内容正确 |
| TC-SYS-07 | NotificationPage | 空状态提示 |
| TC-SYS-08 | MissionHistoryPage | 空状态提示 |
| TC-SYS-09 | AccountPage | 头像、昵称输入、保存按钮 |
| TC-SYS-10 | FeedbackPage | 输入框、上传按钮、提交按钮 |
| TC-SYS-11 | AboutPage | Logo、版本号、功能入口 |
| TC-SYS-12 | HelpPage | 5个FAQ可展开 |
| TC-SYS-13 | LegalPage | 3个法律文书入口 |
| TC-SYS-14 | VersionInfoPage | 版本卡片、更新按钮、更新日志 |
| TC-SYS-15 | AiChatPage | 欢迎页、快速提问、输入框 |
| TC-SYS-16 | ClassroomPage | 搜索框、推荐卡片、分类筛选、课程列表 |
| TC-SYS-17 | PresetsPage | 搜索框、新建按钮、空状态 |
| TC-SYS-18 | HomePage | 天气栏、设备卡片、快捷操作、统计 |
| TC-SYS-19 | MinePage | 头像、菜单项、退出登录 |
| TC-SYS-20 | UpdateDialog | 头部、版本信息、按钮 |
| TC-SYS-21 | AiChatMessage序列化 | toJson/fromJson往返 |
| TC-SYS-22 | WeatherData边界 | isWindWarning 8.0/8.1 |
| TC-SYS-23 | 深色模式 | darkTheme存在 |
| TC-SYS-24 | AppColors | 所有颜色常量非空 |
| TC-SYS-25 | AppVersion | 版本号格式正确 |