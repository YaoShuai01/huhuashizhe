-- 演示数据（可重复执行）
USE huhuashizhe;

-- 演示账号：农友小助手，固定登录号 10000001（初始无密码）
INSERT INTO users (login_id, nickname) VALUES ('10000001', '农友小助手')
ON DUPLICATE KEY UPDATE nickname = VALUES(nickname);
