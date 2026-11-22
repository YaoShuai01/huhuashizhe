-- 演示数据（可重复执行）
USE huhuashizhe;

-- 演示账号：农友小助手（未设置密码，可在 App「账号登录 → 首次使用？设置密码」补设）
INSERT INTO users (nickname) VALUES ('农友小助手')
ON DUPLICATE KEY UPDATE nickname = VALUES(nickname);

-- 一条演示帖子，仅在不存在时插入
INSERT INTO posts (user_id, section, title, content)
SELECT id, '农友留言区', '飞防作业时段怎么选', '上午露水大，下午风大，大家一般几点起飞？'
FROM users
WHERE nickname = '农友小助手'
  AND NOT EXISTS (
    SELECT 1 FROM posts WHERE title = '飞防作业时段怎么选' LIMIT 1
  );
