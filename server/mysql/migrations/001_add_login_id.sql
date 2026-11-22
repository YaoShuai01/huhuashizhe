-- 迁移：登录方式从「昵称」改为「系统生成的登录号」
-- 仅已有库需要执行一次；新库直接跑 mysql/schema.sql 即可
USE huhuashizhe;

ALTER TABLE users
  ADD COLUMN login_id CHAR(8) DEFAULT NULL AFTER id;

ALTER TABLE users
  ADD UNIQUE KEY uk_users_login_id (login_id);

-- 已有账号按 id 生成固定的 8 位登录号，例如 id=1 → 10000001
UPDATE users
SET login_id = LPAD(id + 10000000, 8, '0')
WHERE login_id IS NULL;
