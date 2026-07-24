# 护花使者 APP 企业级测试计划

## 1. 测试概述

| 项目 | 说明 |
|------|------|
| 项目名称 | 护花使者 - 智能植保无人机操控APP |
| 测试版本 | v1.2.0 |
| 测试类型 | 单元测试、集成测试、系统测试(Widget测试) |
| 测试框架 | flutter_test, 纯Dart测试 |
| 测试环境 | Windows 11, Flutter 3.27+, Dart 3.7+ |

## 2. 测试范围

### 2.1 功能模块清单

| 编号 | 模块 | 功能点 | 测试级别 |
|------|------|--------|----------|
| M1 | 首页 | 天气卡片、设备连接、快捷操作、最近作业、作业统计 | 系统 |
| M2 | 预设管理 | 预设CRUD、搜索筛选、微调编辑、AI标签 | 单元+集成+系统 |
| M3 | 小课堂 | 分类筛选、课程列表、课程详情、收藏 | 系统 |
| M4 | 我的 | 账户、设备、设置、操作文档、法律文书、帮助、反馈、关于 | 系统 |
| M5 | AI对话 | 消息发送、流式响应、历史持久化、快速提问 | 单元+集成+系统 |
| M6 | 天气服务 | API调用、城市匹配、数据解析、风向风速转换 | 单元+集成 |
| M7 | 更新服务 | 版本检测、APK下载、版本比较 | 单元+集成 |
| M8 | 本地存储 | 预设CRUD、设置读写、收藏管理、数据持久化 | 单元+集成 |
| M9 | 蓝牙服务 | 设备状态、连接管理、命令帧协议 | 单元 |
| M10 | GPS定位 | 位置获取、逆地理编码、缓存 | 单元 |
| M11 | 闪屏页 | Logo显示、文字显示、1.5秒切换 | 系统 |
| M12 | 通知中心 | 空状态提示 | 系统 |
| M13 | 作业记录 | 空状态提示 | 系统 |
| M14 | 版本信息 | 当前版本、检查更新、更新日志 | 系统 |

### 2.2 可点击板块清单

| 板块 | 入口路径 | 目标页面 |
|------|----------|----------|
| 通知中心 | 首页右上角铃铛 → /notification | NotificationPage |
| AI建议 | 首页快捷操作 → /ai-chat | AiChatPage |
| 创建飞行任务 | 首页快捷操作 → /mission/map | MapSelectPage |
| 快速预设 | 首页快捷操作 → /presets | PresetsPage |
| 作业记录 | 首页快捷操作 → /mission/history | MissionHistoryPage |
| 设备连接 | 首页设备卡片 → /mine/device | DeviceScanPage |
| 我的账户 | 我的 → /mine/account | AccountPage |
| 设备连接 | 我的 → /mine/device | DeviceScanPage |
| 设置 | 我的 → /mine/settings | SettingsPage |
| 操作文档 | 我的 → /mine/manual | ManualPage |
| 法律文书 | 我的 → /mine/legal | LegalPage |
| 帮助 | 我的 → /mine/help | HelpPage |
| 反馈 | 我的 → /mine/feedback | FeedbackPage |
| 关于 | 我的 → /mine/about | AboutPage |
| 版本信息 | 关于 → /mine/version | VersionInfoPage |
| 功能介绍 | 关于 → /mine/feature-intro | FeatureIntroPage |
| 开源许可 | 关于 → /mine/license | OpenSourceLicensePage |
| 用户协议 | 法律文书 → /mine/legal-detail | LegalDetailPage |
| 隐私政策 | 法律文书 → /mine/legal-detail | LegalDetailPage |
| 免责声明 | 法律文书 → /mine/legal-detail | LegalDetailPage |
| 退出登录 | 我的底部按钮 | 确认弹窗 |
| 清空对话 | AI对话页右上角 | 确认弹窗 |

## 3. 测试策略

### 3.1 单元测试 (Unit Tests)
- **数据模型**: WeatherData, AiChatMessage, DeviceStatus, CommandFrame, UpdateInfo
- **服务类**: WeatherService(风向/风速转换), UpdateService(版本比较), LocalDatabase(CRUD)
- **工具方法**: 风力等级转m/s, 风向文字转角度, 版本号解析, CRC16校验

### 3.2 集成测试 (Integration Tests)
- **Provider + Service**: WeatherProvider, AiChatProvider, PresetProvider, UpdateProvider
- **数据持久化**: LocalDatabase 读写流程
- **API调用**: WeatherService 城市匹配+天气获取

### 3.3 系统测试 (Widget Tests)
- **页面渲染**: 所有页面能正常创建和渲染
- **交互验证**: 点击、输入、开关等交互
- **状态验证**: 各页面状态管理正确

## 4. 测试通过标准

| 级别 | 通过标准 |
|------|----------|
| 严重 | 0个未修复 |
| 主要 | 0个未修复 |
| 次要 | 允许≤2个 |
| 建议 | 记录即可 |

## 5. 测试排期

| 阶段 | 内容 | 预计用例数 |
|------|------|------------|
| 第一阶段 | 单元测试 | 35+ |
| 第二阶段 | 集成测试 | 15+ |
| 第三阶段 | 系统测试 | 25+ |
| 合计 | | 75+ |