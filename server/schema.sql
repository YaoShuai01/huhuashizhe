-- 论坛数据库表结构（SQLite）
-- 三张表：users / posts / replies

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  nickname      TEXT    NOT NULL,
  password_hash TEXT,
  avatar        TEXT,
  created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_nickname ON users(nickname);

CREATE TABLE IF NOT EXISTS posts (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  section    TEXT    NOT NULL,
  title      TEXT    NOT NULL,
  content    TEXT    NOT NULL,
  likes      INTEGER NOT NULL DEFAULT 0,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS replies (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  post_id    INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content    TEXT    NOT NULL,
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- 版块/时间排序、回复统计用到的索引
CREATE INDEX IF NOT EXISTS idx_posts_section_created ON posts(section, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_created         ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_replies_post          ON replies(post_id, created_at ASC);
