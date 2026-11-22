# 论坛后端 · MySQL 说明

## 目录

```
server/
├─ mysql/
│  ├─ schema.sql   # 建库 + 三张表（可重复执行）
│  ├─ seed.sql     # 演示数据（幂等）
│  ├─ README.md    # 本文件
│  └─ migrations/  # 已有库的结构变更
├─ db.js           # 连接池（环境变量可覆盖）
├─ init.js         # 一次性执行 schema.sql + seed.sql
├─ auth.js         # 注册 / 登录接口
└─ index.js        # 帖子列表 / 发帖接口
```

## 连接信息

| 项 | 值 |
| --- | --- |
| 地址 | `127.0.0.1:3306` |
| 账号 / 密码 | `root` / `123456` |
| 数据库 | `huhuashizhe` |
| 字符集 | `utf8mb4` / `utf8mb4_unicode_ci` |
| 版本 | MySQL 8.0（本机实测 8.0.39） |

JDBC 连接串：

```
jdbc:mysql://127.0.0.1:3306/huhuashizhe?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai
```

Node 侧连接串（mysql2 使用）：

```
mysql://root:123456@127.0.0.1:3306/huhuashizhe
```

可用环境变量覆盖：`DB_HOST`、`DB_PORT`、`DB_USER`、`DB_PASSWORD`、`DB_NAME`。

## 初始化

```bash
cd server
npm install
npm run init     # 执行 mysql/schema.sql 与 mysql/seed.sql
npm start        # http://localhost:3000
```

也可以手工导入：

```bash
mysql -h127.0.0.1 -uroot -p < mysql/schema.sql
mysql -h127.0.0.1 -uroot -p < mysql/seed.sql
```

## 账号与登录规则

- **注册**：填昵称 + 设置密码，服务端自动生成一个唯一的 8 位数字**登录号**（如 `30219845`），返回给用户自行保存
- **登录**：用登录号 + 密码，昵称只用于帖子与回复展示，不参与登录
- 昵称仍然唯一（重复注册会返回 409），登录号冲突时服务端自动换号重试
- 密码只存 `scrypt` 加盐哈希，不存明文；`password_hash` 为空表示该账号还没设置密码

接口：

```
POST /api/auth/register  {"nickname":"农友阿芳","password":"123456"}
  → 201 {"id":3,"loginId":"30219845","nickname":"农友阿芳"}

POST /api/auth/login     {"loginId":"30219845","password":"123456"}
  → 200 {"id":3,"loginId":"30219845","nickname":"农友阿芳"}
```

## 已有库升级

早期的库（登录号字段还不存在）执行一次：

```bash
mysql --host=127.0.0.1 --user=root --password=123456 < mysql/migrations/001_add_login_id.sql
```

迁移会补 `login_id` 列、加唯一索引，并给已有账号按 `id + 10000000` 生成登录号（如 id=1 → `10000001`）。

## 表分组

- **账号**：`users` —— `login_id` 为系统生成的 8 位登录号（唯一），`nickname` 仅用于展示（也保持唯一）；密码只存 `scrypt` 加盐哈希
- **内容**：`posts`（帖子）、`replies`（回复），都带 `user_id` 外键并级联删除
- **索引**：`posts(section, created_at)` 支持版块内按时间倒序；`replies(post_id, created_at)` 支持回复列表

## 时间与展示约定

- 所有 `created_at` 均为 `DATETIME`，取数据库服务器本地时间（本机即北京时间），接口统一格式化为 `YYYY-MM-DD HH:MM:SS`
- 接口只返回昵称与 id，不返回 `password_hash`；前端展示统一用昵称，不额外做匿名化处理
- 列表默认按 `created_at DESC, id DESC` 排序，分页参数 `limit`（最大 100）、`offset`

## 备份与恢复

```bash
# 备份
mysqldump -h127.0.0.1 -uroot -p --single-transaction huhuashizhe > backup.sql

# 恢复
mysql -h127.0.0.1 -uroot -p huhuashizhe < backup.sql
```

建议在 `schema.sql` 变更前先备份一次。

## 远程联调

本机 MySQL 当前 `bind_address = *`（监听所有网卡）。队友直连前请确认：

- 若只想本机访问：把 `my.ini` 的 `bind-address` 改为 `127.0.0.1` 后重启服务
- 若允许局域网访问：保持现状，并在防火墙放行 3306，队友用 `电脑IP:3306` 连接
- 走公网时不要直接暴露 3306，建议 SSH 隧道：

```bash
ssh -L 3306:127.0.0.1:3306 用户名@服务器地址
```

隧道建立后，本地按 `127.0.0.1:3306` 连接即可；也可以直接把 `mysql/schema.sql` 拿到自己机器上跑一份本地库。
