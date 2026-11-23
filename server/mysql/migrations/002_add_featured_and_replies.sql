-- 迁移：帖子精选标记 + 评论回复
-- 仅已有库需要执行一次；新库直接跑 mysql/schema.sql 即可
USE huhuashizhe;

-- 帖子新增精选标记，推荐分区优先展示精选内容
ALTER TABLE posts
  ADD COLUMN featured TINYINT(1) NOT NULL DEFAULT 0
  COMMENT '是否精选（推荐分区优先展示）' AFTER likes;

-- 回复新增父评论 id，用于「评论回复」
ALTER TABLE replies
  ADD COLUMN parent_id BIGINT UNSIGNED DEFAULT NULL
  COMMENT '回复的评论 id' AFTER user_id,
  ADD KEY idx_replies_parent (parent_id),
  ADD CONSTRAINT fk_replies_parent FOREIGN KEY (parent_id)
    REFERENCES replies (id) ON DELETE CASCADE;
