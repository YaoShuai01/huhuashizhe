# 护花使者 MySQL 数据库

> 面向后续后端服务的共享数据库。当前 `server/schedule-java` 仍使用 SQLite，**MySQL 暂未接入运行中的 Spring/Servlet 服务**；新增功能需要持久化时，按本目录结构直接写服务即可。

## 1. 服务器信息

| 项 | 值 |
|---|---|
| 版本 | MySQL 8.0.29（Windows x64 ZIP 版） |
| 服务名 | `MySQL80`（开机自启） |
| 监听 | `127.0.0.1:3306`（仅本机，不对外开放） |
| 安装目录 | `C:\huhuashizhe\mysql` |
| 数据目录 | `C:\huhuashizhe\mysql-data` |
| 配置文件 | `C:\huhuashizhe\mysql\my.ini` |
| 数据库 | `huhuashizhe` |
| 字符集 | `utf8mb4` / `utf8mb4_unicode_ci` |
| 时区 | 连接默认 `+00:00`，所有 `DATETIME` 存 UTC |

**账号**
- 业务账号：`hhsz_app@localhost`，只对 `huhuashizhe` 库有权限。
- 密码只放在服务器 `C:\huhuashizhe\config\config.properties` 的 `mysql.password`，以及本机 `%USERPROFILE%\.huhuashizhe-schedule\config.properties`；**不要提交到仓库**。
- root 账号仅用于运维，凭据在服务器 `C:\huhuashizhe\config\mysql-root.cnf`（ACL 仅 Administrators/SYSTEM）。

## 2. 目录文件

| 文件 | 用途 |
|---|---|
| `schema.sql` | 建库 + 全部表结构（可重复执行，`CREATE TABLE IF NOT EXISTS`） |
| `seed.sql` | 论坛分区/版块、作物/生育期、土壤/灌溉、农事规则、默认配置（可重复执行） |
| `README.md` | 本说明 |

## 3. 表结构总览

### 成员与轮协
| 表 | 说明 |
|---|---|
| `members` | 轮协成员（姓名唯一、seq 编号、验证状态、角色） |
| `member_presence` | 成员在线心跳（最近在线时间） |
| `member_keys` | 成员专属密钥哈希（预留，禁止存明文） |
| `schedule_meta` | 轮协表元数据，单行 `id=1`，`revision` 乐观锁 |
| `schedule_assignments` | 每日协管安排（`duty_date` → `member_id`） |
| `schedule_rotation` | 顺延序列 |
| `schedule_change_log` / `schedule_change_items` | 变更日志与明细 |

### 匿名留言池（现有 `/schedule/messages`）
| 表 | 说明 |
|---|---|
| `messages` | 匿名留言（`author_anon_id` 不关联成员） |
| `message_replies` | 留言回复，随留言级联删除 |

### 论坛
| 表 | 说明 |
|---|---|
| `forum_categories` / `forum_sections` | 分区与版块（已灌入 App 默认目录） |
| `forum_posts` / `forum_comments` | 帖子与评论（含审核状态） |
| `forum_likes` / `forum_favorites` | 点赞、收藏（每用户一条） |
| `forum_notifications` | 点赞/回复/收藏/公告/审核消息 |
| `forum_moderation_logs` | AI 初审与人工复审记录 |
| `users` / `posts` / `replies` | Node 登录/论坛服务使用（昵称账号、帖子、回复） |

### 飞防预约
| 表 | 说明 |
|---|---|
| `pilots` | 飞手资料（机型、亩单价、评分、接单数） |
| `farm_orders` | 农户预约订单（作物、面积、日期时段、金额、状态） |
| `farm_order_events` | 订单状态流转事件（JSON 详情） |

### 田哨
| 表 | 说明 |
|---|---|
| `sentinel_fields` | 田块登记（作物、亩数、地点、播种时间） |
| `sentinel_alerts` | 天气/病虫害/打药预警，`rule_key` 去重 |
| `agronomy_rules` | 农事规则库（已灌入 App 内置 6 条） |
| `weather_snapshots` | 天气观测快照（供预警与云种植使用） |

### 云种植（v3.8.0）
| 表 | 说明 |
|---|---|
| `crops` / `crop_stages` | 作物档案与生育阶段（已灌入 6 种作物 50 个阶段） |
| `soil_types` / `irrigation_types` | 土壤与灌溉字典 |
| `cloud_plots` | 田块（面积、边界 JSON、墒情节点、收获状态） |
| `cloud_plot_logs` | 田块操作日志 |
| `cloud_settings` | 云种植设置，单行 `id=1` |
| `cloud_chat_messages` | AI 农事助手对话 |
| `cloud_snoozes` | 预警免打扰 |

### 系统
| 表 | 说明 |
|---|---|
| `app_releases` | APP 版本发布审计（`version.json` 仍是更新接口唯一来源） |
| `ai_daily_usage` | AI 代理按日/按 IP 用量 |
| `schema_migrations` | 结构版本记录 |

## 4. 约定

1. **时间**：`DATETIME(3)` 统一存 UTC；`service_date`、`duty_date` 是本地日历日。
2. **用户可见 ID**：沿用 App 现有格式（`m_`、`msg_`、`rpl_`、`p` 等），由业务侧生成。
3. **匿名性**：`messages` / `message_replies` 的 `author_anon_id` 只用于“是否本人”，**不得关联 `members` 反查姓名**。
4. **状态字段**用 `VARCHAR` 而非 `ENUM`，新增状态不需要改表；取值写在注释里。
5. **外键**：帖子/评论/日志等从属数据级联删除；成员被安排轮协时禁止直接删除（先解除安排）。
6. **JSON**：田块边界 `polygon` 使用 `[[lng,lat],...]`；订单事件详情用 JSON。

## 5. 初始化 / 升级

```powershell
# 在服务器上执行（root 凭据文件已存在）
& C:\huhuashizhe\mysql\bin\mysql.exe --defaults-extra-file=C:\huhuashizhe\config\mysql-root.cnf -e "source C:/huhuashizhe/upgrade-staging/schema.sql"
& C:\huhuashizhe\mysql\bin\mysql.exe --defaults-extra-file=C:\huhuashizhe\config\mysql-root.cnf -e "source C:/huhuashizhe/upgrade-staging/seed.sql"
```

Node 服务也可在 `server/` 目录执行 `npm run init`（读取同一份 `schema.sql` / `seed.sql`，可重复执行）。

**已有库升级（v3.10.1 起登录号）**：早期 `users` 表没有 `login_id`，先执行一次迁移，再跑 `npm run init`：

```powershell
& C:\huhuashizhe\mysql\bin\mysql.exe --defaults-extra-file=C:\huhuashizhe\config\mysql-root.cnf -e "source C:/huhuashizhe/forum-server/mysql/migrations/001_add_login_id.sql"
```

迁移会补 `login_id` 列、加唯一索引，并给已有账号按 `id + 10000000` 生成登录号（如 id=1 → `10000001`）。

后续结构变更请新增 `migrations/00X_xxx.sql`，并在 `schema_migrations` 记录版本；不要直接改已上线的列。

## 6. 备份

- 每日 `03:40` 由计划任务 `HHSZ-MySQL-Backup` 执行 `mysqldump`。
- 输出目录：`C:\huhuashizhe\data\mysql-backups\`，保留最近 14 份。
- 与现有 SQLite 的 `03:30` 备份错开。

## 7. 与现有 SQLite 的关系

- 当前线上**轮协/留言**接口仍读写 `C:\huhuashizhe\data\schedule.db`，**不切换、不双写**，避免影响已发布版本。
- **Node 登录/论坛服务**已切换到本 MySQL 库（`users` / `posts` / `replies`）。
- 需要迁移旧 SQLite 数据时，单独写一次性迁移脚本（成员 → `members`，排班 JSON → `schedule_*`，留言 → `messages`），迁移前先备份 SQLite。
- 新服务连接示例（Java）：
  `jdbc:mysql://127.0.0.1:3306/huhuashizhe?useUnicode=true&characterEncoding=utf8&serverTimezone=UTC&useSSL=false`
  驱动：`com.mysql:mysql-connector-j:8.4.0`（或 8.0.x）。

## 8. Node 登录/论坛服务（server/）

| 项 | 值 |
|---|---|
| 技术栈 | Node.js 20+ / Express / mysql2 |
| 端口 | `3000`（公网 `http://121.199.75.235:3000`） |
| 部署目录 | `C:\huhuashizhe\forum-server` |
| 开机自启 | 计划任务 `HuHuaShiZheForum` |
| 数据库 | `huhuashizhe`，账号 `hhsz_app`，配置从 `config.properties` 的 `mysql.*` 读取 |
| 初始化 | `npm run init`（schema.sql + seed.sql） |

接口：
- `POST /api/auth/register` `{nickname,password}` → 返回系统生成的 8 位 `loginId`
- `POST /api/auth/login` `{loginId,password}`
- `GET /api/posts?section=&limit=&offset=`
- `POST /api/posts` `{userId,section,title,content}`

账号规则：注册时填昵称+密码，服务端生成唯一 8 位登录号；登录只用「登录号+密码」，昵称仅用于展示。密码只存 scrypt 加盐哈希。旧的「昵称即账号」登录方式已废弃。

APP 端默认地址在 `lib/features/auth/data/auth_api.dart`，可用 `--dart-define=FORUM_API_BASE=...` 覆盖。

## 9. 安全

- MySQL 只监听 `127.0.0.1`，**不要在阿里云安全组放行 3306**。
- 业务账号只授权 `huhuashizhe.*`；root 不用于应用连接。
- 任何密码、密钥不得写入本目录或提交 Git。
