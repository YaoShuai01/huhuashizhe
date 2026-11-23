-- 论坛数据库结构（MySQL 8.0）
-- 初始化：mysql -h127.0.0.1 -uroot -p < schema.sql

CREATE DATABASE IF NOT EXISTS huhuashizhe
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE huhuashizhe;

-- 用户：登录号由系统自动生成，昵称仅用于展示
CREATE TABLE IF NOT EXISTS users (
  id            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  login_id      CHAR(8)                  DEFAULT NULL,
  nickname      VARCHAR(20)     NOT NULL,
  password_hash VARCHAR(255)             DEFAULT NULL,
  avatar        VARCHAR(255)             DEFAULT NULL,
  created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_login_id (login_id),
  UNIQUE KEY uk_users_nickname (nickname)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '用户';

-- 帖子
CREATE TABLE IF NOT EXISTS posts (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    INT UNSIGNED    NOT NULL,
  section    VARCHAR(50)     NOT NULL,
  title      VARCHAR(120)    NOT NULL,
  content    TEXT            NOT NULL,
  images     TEXT                     DEFAULT NULL COMMENT '配图 JSON 数组，最多 3 张',
  likes      INT             NOT NULL DEFAULT 0,
  featured   TINYINT(1)      NOT NULL DEFAULT 0 COMMENT '是否精选（推荐分区优先展示）',
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_posts_section_created (section, created_at DESC),
  KEY idx_posts_user (user_id),
  CONSTRAINT fk_posts_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '帖子';

-- 回复
CREATE TABLE IF NOT EXISTS replies (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  post_id    BIGINT UNSIGNED NOT NULL,
  user_id    INT UNSIGNED    NOT NULL,
  parent_id  BIGINT UNSIGNED          DEFAULT NULL COMMENT '回复的评论 id',
  content    TEXT            NOT NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_replies_post (post_id, created_at),
  KEY idx_replies_user (user_id),
  KEY idx_replies_parent (parent_id),
  CONSTRAINT fk_replies_post FOREIGN KEY (post_id)
    REFERENCES posts (id) ON DELETE CASCADE,
  CONSTRAINT fk_replies_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_replies_parent FOREIGN KEY (parent_id)
    REFERENCES replies (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '回复';

-- 点赞（同一用户对同一帖子只保留一条）
CREATE TABLE IF NOT EXISTS post_likes (
  post_id    BIGINT UNSIGNED NOT NULL,
  user_id    INT UNSIGNED    NOT NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (post_id, user_id),
  KEY idx_post_likes_user (user_id),
  CONSTRAINT fk_post_likes_post FOREIGN KEY (post_id)
    REFERENCES posts (id) ON DELETE CASCADE,
  CONSTRAINT fk_post_likes_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '帖子点赞';

-- 收藏（同一用户对同一帖子只保留一条）
CREATE TABLE IF NOT EXISTS post_favorites (
  post_id    BIGINT UNSIGNED NOT NULL,
  user_id    INT UNSIGNED    NOT NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (post_id, user_id),
  KEY idx_post_favorites_user (user_id),
  CONSTRAINT fk_post_favorites_post FOREIGN KEY (post_id)
    REFERENCES posts (id) ON DELETE CASCADE,
  CONSTRAINT fk_post_favorites_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '帖子收藏';

-- 消息提醒：评论 / 点赞 / 收藏，仅通知帖子作者
CREATE TABLE IF NOT EXISTS forum_messages (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    INT UNSIGNED    NOT NULL COMMENT '接收者',
  actor_id   INT UNSIGNED             DEFAULT NULL COMMENT '触发者',
  kind       ENUM('like', 'reply', 'favorite') NOT NULL,
  post_id    BIGINT UNSIGNED          DEFAULT NULL,
  title      VARCHAR(120)    NOT NULL,
  body       VARCHAR(255)    NOT NULL,
  created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  read_at    DATETIME                 DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_messages_user (user_id, created_at DESC),
  CONSTRAINT fk_messages_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '消息提醒';

-- 投诉记录：同一用户对同一内容只保留一条
CREATE TABLE IF NOT EXISTS reports (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  target_type ENUM('post', 'reply') NOT NULL,
  target_id   BIGINT UNSIGNED NOT NULL,
  user_id     INT UNSIGNED    NOT NULL,
  reason      VARCHAR(50)     NOT NULL,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_reports_user_target (user_id, target_type, target_id),
  KEY idx_reports_target (target_type, target_id),
  CONSTRAINT fk_reports_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '投诉记录';
