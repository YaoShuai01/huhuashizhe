-- ============================================================
-- 护花使者 MySQL 数据库结构 v1
-- 适用：MySQL 8.0.29+ / InnoDB / utf8mb4
-- 约定：
--   1) 所有 DATETIME 存 UTC（服务端 my.ini 设置 default-time-zone='+00:00'）
--   2) service_date / duty_date 等业务日期存本地日历日（Asia/Shanghai）
--   3) 用户可见 ID 使用 VARCHAR（m_/msg_/rpl_/p 前缀），日志类使用自增 BIGINT
--   4) 匿名留言池不关联真实成员，禁止把 author_anon_id 反查为成员姓名
-- ============================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS huhuashizhe
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE huhuashizhe;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version INT NOT NULL COMMENT '结构版本号',
  description VARCHAR(255) NOT NULL,
  applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='数据库结构版本';

-- ------------------------------------------------------------
-- 一、成员与认证
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS members (
  id VARCHAR(64) NOT NULL COMMENT '成员 ID，如 m_xxx',
  name VARCHAR(64) NOT NULL COMMENT '成员姓名（唯一）',
  seq INT NOT NULL COMMENT '成员编号，按加入顺序分配',
  active TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否在岗',
  verified TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已通过身份验证',
  verified_at DATETIME(3) NULL COMMENT '首次验证时间（UTC）',
  role VARCHAR(16) NOT NULL DEFAULT 'member' COMMENT 'member/admin',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_members_name (name),
  UNIQUE KEY uk_members_seq (seq)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='轮协成员';

CREATE TABLE IF NOT EXISTS member_presence (
  member_id VARCHAR(64) NOT NULL,
  last_seen_at DATETIME(3) NOT NULL COMMENT '最近一次在线心跳（UTC）',
  client_ip VARCHAR(64) NULL COMMENT '预留：来源 IP',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (member_id),
  KEY idx_presence_seen (last_seen_at),
  CONSTRAINT fk_presence_member FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='成员在线心跳';

CREATE TABLE IF NOT EXISTS member_keys (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  member_id VARCHAR(64) NOT NULL,
  key_hash CHAR(64) NOT NULL COMMENT 'SHA-256(key) 的十六进制，禁止存明文',
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  expires_at DATETIME(3) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_member_keys_hash (key_hash),
  KEY idx_member_keys_member (member_id),
  CONSTRAINT fk_member_keys_member FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='成员专属密钥（只存哈希）';

-- ------------------------------------------------------------
-- 二、轮协排班
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS schedule_meta (
  id TINYINT NOT NULL,
  schema_version INT NOT NULL DEFAULT 1,
  revision BIGINT NOT NULL DEFAULT 1 COMMENT '乐观锁版本号',
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_by VARCHAR(64) NOT NULL DEFAULT 'system',
  PRIMARY KEY (id),
  CONSTRAINT chk_schedule_meta_singleton CHECK (id = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='轮协表元数据（单行）';

CREATE TABLE IF NOT EXISTS schedule_assignments (
  duty_date DATE NOT NULL COMMENT '协管日期（本地日历日）',
  member_id VARCHAR(64) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (duty_date),
  KEY idx_assignments_member (member_id),
  CONSTRAINT fk_assignments_member FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='每日协管安排';

CREATE TABLE IF NOT EXISTS schedule_rotation (
  position INT NOT NULL COMMENT '顺延序号，从 1 开始',
  member_id VARCHAR(64) NOT NULL,
  PRIMARY KEY (position),
  UNIQUE KEY uk_rotation_member (member_id),
  CONSTRAINT fk_rotation_member FOREIGN KEY (member_id) REFERENCES members (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='轮协顺延序列';

CREATE TABLE IF NOT EXISTS schedule_change_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  changed_at DATETIME(3) NOT NULL,
  changed_by VARCHAR(64) NOT NULL,
  truncated TINYINT(1) NOT NULL DEFAULT 0 COMMENT '变更过多时被截断',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_change_log_time (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='轮协变更日志';

CREATE TABLE IF NOT EXISTS schedule_change_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  change_log_id BIGINT UNSIGNED NOT NULL,
  duty_date DATE NOT NULL,
  from_member_id VARCHAR(64) NULL,
  to_member_id VARCHAR(64) NULL,
  PRIMARY KEY (id),
  KEY idx_change_items_log (change_log_id),
  CONSTRAINT fk_change_items_log FOREIGN KEY (change_log_id) REFERENCES schedule_change_log (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='轮协变更明细';

-- ------------------------------------------------------------
-- 三、匿名留言池（现有 /schedule/messages）
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS messages (
  id VARCHAR(64) NOT NULL COMMENT 'msg_xxx',
  author_anon_id VARCHAR(128) NOT NULL COMMENT '匿名标识，不关联成员表',
  content VARCHAR(1000) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_messages_created (created_at),
  KEY idx_messages_author (author_anon_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='匿名留言池';

CREATE TABLE IF NOT EXISTS message_replies (
  id VARCHAR(64) NOT NULL COMMENT 'rpl_xxx',
  message_id VARCHAR(64) NOT NULL,
  author_anon_id VARCHAR(128) NOT NULL,
  content VARCHAR(1000) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_replies_message (message_id, created_at),
  CONSTRAINT fk_replies_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='匿名留言回复';

-- ------------------------------------------------------------
-- 四、论坛（分区 / 版块 / 帖子 / 评论 / 点赞 / 收藏 / 通知 / 审核）
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS forum_categories (
  id INT NOT NULL AUTO_INCREMENT,
  name VARCHAR(32) NOT NULL,
  icon VARCHAR(64) NULL COMMENT 'Flutter IconData 名称',
  sort_order INT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_forum_categories_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='论坛分区';

CREATE TABLE IF NOT EXISTS forum_sections (
  id INT NOT NULL AUTO_INCREMENT,
  category_id INT NOT NULL,
  title VARCHAR(64) NOT NULL,
  description VARCHAR(255) NULL,
  hot TINYINT(1) NOT NULL DEFAULT 0,
  sort_order INT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_forum_sections_title (title),
  KEY idx_forum_sections_category (category_id, sort_order),
  CONSTRAINT fk_forum_sections_category FOREIGN KEY (category_id) REFERENCES forum_categories (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='论坛版块';

CREATE TABLE IF NOT EXISTS forum_posts (
  id VARCHAR(64) NOT NULL,
  section_id INT NOT NULL,
  author_id VARCHAR(128) NULL COMMENT '匿名 ID 或成员 ID',
  author_name VARCHAR(64) NOT NULL,
  title VARCHAR(200) NOT NULL,
  content MEDIUMTEXT NOT NULL,
  like_count INT NOT NULL DEFAULT 0,
  favorite_count INT NOT NULL DEFAULT 0,
  comment_count INT NOT NULL DEFAULT 0,
  status VARCHAR(16) NOT NULL DEFAULT 'published' COMMENT 'published/pending_review/hidden/deleted',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_posts_section (section_id, status, created_at),
  KEY idx_posts_author (author_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='论坛帖子';

CREATE TABLE IF NOT EXISTS forum_comments (
  id VARCHAR(64) NOT NULL,
  post_id VARCHAR(64) NOT NULL,
  author_id VARCHAR(128) NULL,
  author_name VARCHAR(64) NOT NULL,
  content TEXT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'published',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_comments_post (post_id, status, created_at),
  CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES forum_posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='论坛评论';

CREATE TABLE IF NOT EXISTS forum_likes (
  post_id VARCHAR(64) NOT NULL,
  user_id VARCHAR(128) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (post_id, user_id),
  KEY idx_likes_user (user_id, created_at),
  CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES forum_posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='帖子点赞（每用户一次）';

CREATE TABLE IF NOT EXISTS forum_favorites (
  post_id VARCHAR(64) NOT NULL,
  user_id VARCHAR(128) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (post_id, user_id),
  KEY idx_favorites_user (user_id, created_at),
  CONSTRAINT fk_favorites_post FOREIGN KEY (post_id) REFERENCES forum_posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='帖子收藏';

CREATE TABLE IF NOT EXISTS forum_notifications (
  id VARCHAR(64) NOT NULL,
  user_id VARCHAR(128) NOT NULL COMMENT '接收者匿名 ID 或成员 ID',
  kind VARCHAR(16) NOT NULL COMMENT 'like/reply/favorite/announcement/moderation',
  title VARCHAR(200) NOT NULL,
  body TEXT NULL,
  post_id VARCHAR(64) NULL,
  comment_id VARCHAR(64) NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_notifications_user (user_id, is_read, created_at),
  CONSTRAINT fk_notifications_post FOREIGN KEY (post_id) REFERENCES forum_posts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='论坛消息通知';

CREATE TABLE IF NOT EXISTS forum_moderation_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  target_type VARCHAR(16) NOT NULL COMMENT 'post/comment',
  target_id VARCHAR(64) NOT NULL,
  verdict VARCHAR(16) NOT NULL COMMENT 'pass/review/reject',
  reason VARCHAR(500) NULL,
  reviewer VARCHAR(64) NULL COMMENT 'NULL 表示 AI 初审',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_moderation_target (target_type, target_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='论坛内容审核记录';

-- ------------------------------------------------------------
-- 五、飞防预约与飞手
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS pilots (
  id VARCHAR(64) NOT NULL,
  name VARCHAR(64) NOT NULL,
  phone VARCHAR(32) NULL,
  region VARCHAR(128) NULL,
  drone_model VARCHAR(64) NULL,
  price_per_mu DECIMAL(10,2) NOT NULL DEFAULT 0 COMMENT '元/亩',
  years INT NOT NULL DEFAULT 0,
  rating DECIMAL(3,2) NOT NULL DEFAULT 5.00,
  order_count INT NOT NULL DEFAULT 0,
  status VARCHAR(16) NOT NULL DEFAULT 'available' COMMENT 'available/busy/offline',
  verified TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_pilots_status (status),
  KEY idx_pilots_region (region)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='飞手资料';

CREATE TABLE IF NOT EXISTS farm_orders (
  id VARCHAR(64) NOT NULL,
  farmer_name VARCHAR(64) NOT NULL,
  farmer_phone VARCHAR(32) NOT NULL,
  crop VARCHAR(32) NOT NULL,
  crop_custom VARCHAR(32) NULL COMMENT '作物选择“其他”时的自定义名称',
  area_mu DECIMAL(10,2) NOT NULL,
  address VARCHAR(255) NOT NULL,
  service_date DATE NOT NULL,
  service_period VARCHAR(16) NOT NULL COMMENT '上午/下午',
  price_per_mu DECIMAL(10,2) NOT NULL,
  estimated_amount DECIMAL(12,2) NOT NULL,
  note VARCHAR(500) NULL,
  pilot_id VARCHAR(64) NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending' COMMENT 'pending/accepted/in_progress/completed/cancelled',
  accepted_at DATETIME(3) NULL,
  cancelled_at DATETIME(3) NULL,
  cancel_fee DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '接单 12 小时后取消的 2% 费用',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_orders_status_date (status, service_date),
  KEY idx_orders_pilot (pilot_id, status),
  KEY idx_orders_farmer_phone (farmer_phone),
  CONSTRAINT fk_orders_pilot FOREIGN KEY (pilot_id) REFERENCES pilots (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='飞防预约订单';

CREATE TABLE IF NOT EXISTS farm_order_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id VARCHAR(64) NOT NULL,
  event_type VARCHAR(32) NOT NULL COMMENT 'created/accepted/cancelled/completed 等',
  actor VARCHAR(64) NULL,
  detail JSON NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_order_events_order (order_id, created_at),
  CONSTRAINT fk_order_events_order FOREIGN KEY (order_id) REFERENCES farm_orders (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='订单事件/状态流转';

-- ------------------------------------------------------------
-- 六、田哨（田块登记 / 预警 / 农事规则 / 天气快照）
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sentinel_fields (
  id VARCHAR(64) NOT NULL,
  owner VARCHAR(64) NOT NULL DEFAULT '演示农户',
  crop VARCHAR(32) NOT NULL COMMENT 'rapeseed/cabbage/rice',
  area_mu DECIMAL(10,2) NOT NULL,
  location VARCHAR(255) NOT NULL,
  planted_at DATETIME(3) NOT NULL,
  game_plot INT NOT NULL DEFAULT 0 COMMENT '同步到云种植游戏的田块编号',
  status VARCHAR(16) NOT NULL DEFAULT 'growing' COMMENT 'growing/harvested/archived',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_fields_owner (owner, status),
  KEY idx_fields_crop (crop, planted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='田哨田块登记';

CREATE TABLE IF NOT EXISTS sentinel_alerts (
  id VARCHAR(64) NOT NULL,
  rule_key VARCHAR(128) NOT NULL COMMENT '去重键，同一规则同一田块只提醒一次',
  field_id VARCHAR(64) NULL,
  type VARCHAR(32) NOT NULL COMMENT 'coldWave/highWind/heavyRain/sprayReminder/pestRisk',
  severity VARCHAR(16) NOT NULL COMMENT 'info/warning/urgent',
  title VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  recommendation TEXT NULL,
  crop_label VARCHAR(32) NULL,
  handled TINYINT(1) NOT NULL DEFAULT 0,
  handled_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_alerts_rule (rule_key),
  KEY idx_alerts_field (field_id, created_at),
  KEY idx_alerts_handled (handled, created_at),
  CONSTRAINT fk_alerts_field FOREIGN KEY (field_id) REFERENCES sentinel_fields (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='田哨预警';

CREATE TABLE IF NOT EXISTS agronomy_rules (
  id VARCHAR(64) NOT NULL,
  crop VARCHAR(32) NOT NULL,
  day_from INT NOT NULL,
  day_to INT NOT NULL,
  title VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  recommendation TEXT NOT NULL,
  severity VARCHAR(16) NOT NULL DEFAULT 'warning',
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_rules_crop (crop, day_from, day_to, enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='农事规则库';

CREATE TABLE IF NOT EXISTS weather_snapshots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  location VARCHAR(255) NULL,
  lat DECIMAL(9,6) NULL,
  lng DECIMAL(9,6) NULL,
  temperature DECIMAL(5,2) NULL,
  humidity INT NULL,
  wind_speed DECIMAL(5,2) NULL,
  precipitation_prob INT NULL,
  pressure DECIMAL(7,2) NULL,
  observed_at DATETIME(3) NOT NULL,
  raw_json JSON NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_weather_time (observed_at),
  KEY idx_weather_location (location, observed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='天气观测快照';

-- ------------------------------------------------------------
-- 七、云种植（v3.8.0）
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS crops (
  id VARCHAR(64) NOT NULL,
  name VARCHAR(64) NOT NULL,
  variety VARCHAR(64) NULL,
  season VARCHAR(32) NULL,
  sow_window VARCHAR(64) NULL,
  cycle_days INT NOT NULL COMMENT '全生育期天数',
  density INT NULL COMMENT '亩株数',
  yield_kg INT NULL COMMENT '亩产 kg',
  water_need VARCHAR(32) NULL,
  suitability INT NULL COMMENT '适宜度 0-100',
  pattern VARCHAR(64) NULL,
  suitable VARCHAR(64) NULL,
  reason TEXT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_crops_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='云种植作物档案';

CREATE TABLE IF NOT EXISTS crop_stages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  crop_id VARCHAR(64) NOT NULL,
  stage_index INT NOT NULL COMMENT '从 0 开始',
  name VARCHAR(32) NOT NULL,
  start_day INT NOT NULL,
  end_day INT NOT NULL,
  start_pct INT NOT NULL,
  end_pct INT NOT NULL,
  tip VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_crop_stage (crop_id, stage_index),
  CONSTRAINT fk_crop_stages_crop FOREIGN KEY (crop_id) REFERENCES crops (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='作物生育阶段';

CREATE TABLE IF NOT EXISTS soil_types (
  id VARCHAR(32) NOT NULL,
  name VARCHAR(32) NOT NULL,
  base_moisture INT NOT NULL COMMENT '基础墒情百分比',
  description VARCHAR(255) NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='土壤类型';

CREATE TABLE IF NOT EXISTS irrigation_types (
  id VARCHAR(32) NOT NULL,
  name VARCHAR(32) NOT NULL,
  moisture_bonus INT NOT NULL COMMENT '墒情加成',
  description VARCHAR(255) NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='灌溉方式';

CREATE TABLE IF NOT EXISTS cloud_plots (
  id VARCHAR(64) NOT NULL,
  name VARCHAR(64) NOT NULL,
  crop_id VARCHAR(64) NULL,
  area_mu DECIMAL(10,2) NOT NULL DEFAULT 0,
  planted_at DATETIME(3) NULL,
  polygon JSON NULL COMMENT '[[lng,lat],...] 田块边界',
  soil_id VARCHAR(32) NOT NULL DEFAULT 'loam',
  irrigation_id VARCHAR(32) NOT NULL DEFAULT 'none',
  fertilizer VARCHAR(64) NOT NULL DEFAULT '未施肥',
  last_water_at DATETIME(3) NULL,
  last_fert_at DATETIME(3) NULL,
  last_calibrated_at DATETIME(3) NULL,
  last_pest_at DATETIME(3) NULL,
  last_sensed_at DATETIME(3) NULL,
  sync_mode VARCHAR(16) NOT NULL DEFAULT 'auto',
  build_source VARCHAR(64) NOT NULL DEFAULT 'GPS 圈地',
  harvested TINYINT(1) NOT NULL DEFAULT 0,
  pct_offset DECIMAL(6,3) NOT NULL DEFAULT 0,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_cloud_plots_crop (crop_id),
  KEY idx_cloud_plots_harvested (harvested),
  CONSTRAINT fk_cloud_plots_crop FOREIGN KEY (crop_id) REFERENCES crops (id) ON DELETE SET NULL,
  CONSTRAINT fk_cloud_plots_soil FOREIGN KEY (soil_id) REFERENCES soil_types (id) ON DELETE RESTRICT,
  CONSTRAINT fk_cloud_plots_irrigation FOREIGN KEY (irrigation_id) REFERENCES irrigation_types (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='云种植田块';

CREATE TABLE IF NOT EXISTS cloud_plot_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  plot_id VARCHAR(64) NOT NULL,
  log_type VARCHAR(32) NOT NULL,
  title VARCHAR(200) NOT NULL,
  description TEXT NULL,
  logged_at DATETIME(3) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_plot_logs (plot_id, logged_at),
  CONSTRAINT fk_plot_logs_plot FOREIGN KEY (plot_id) REFERENCES cloud_plots (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='云种植田块日志';

CREATE TABLE IF NOT EXISTS cloud_settings (
  id TINYINT NOT NULL,
  moisture_threshold INT NOT NULL DEFAULT 55,
  calibrate_days INT NOT NULL DEFAULT 7,
  remind_hour INT NOT NULL DEFAULT 8,
  auto_sync TINYINT(1) NOT NULL DEFAULT 1,
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  CONSTRAINT chk_cloud_settings_singleton CHECK (id = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='云种植设置（单行）';

CREATE TABLE IF NOT EXISTS cloud_chat_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  session_id VARCHAR(64) NOT NULL COMMENT '用户/会话标识',
  role VARCHAR(8) NOT NULL COMMENT 'me/ai',
  content TEXT NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_cloud_chat (session_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='云种植 AI 农事助手对话';

CREATE TABLE IF NOT EXISTS cloud_snoozes (
  alert_key VARCHAR(128) NOT NULL,
  snoozed_until DATETIME(3) NOT NULL,
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (alert_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='预警免打扰';

-- ------------------------------------------------------------
-- 八、系统与运维
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS app_releases (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  version_name VARCHAR(16) NOT NULL,
  version_code INT NOT NULL,
  release_notes TEXT NULL,
  download_url VARCHAR(500) NOT NULL,
  file_size BIGINT UNSIGNED NULL,
  published_by VARCHAR(64) NULL,
  published_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_release_version (version_name, version_code),
  KEY idx_releases_time (published_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='APP 版本发布记录';

CREATE TABLE IF NOT EXISTS ai_daily_usage (
  usage_date DATE NOT NULL,
  scope VARCHAR(16) NOT NULL COMMENT 'global/ip',
  scope_key VARCHAR(64) NOT NULL,
  request_count INT NOT NULL DEFAULT 0,
  token_count INT NOT NULL DEFAULT 0,
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (usage_date, scope, scope_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI 代理每日用量';

-- ------------------------------------------------------------
-- 九、Node 论坛/登录服务（server/index.js，端口 3000）
-- 与上面的 forum_* 完整论坛模型并存：当前 Node 服务使用 users/posts/replies
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  login_id CHAR(8) DEFAULT NULL COMMENT '8 位系统登录号（唯一）',
  nickname VARCHAR(20) NOT NULL COMMENT '昵称仅用于展示',
  password_hash VARCHAR(255) DEFAULT NULL COMMENT 'scrypt 盐:哈希；未设置密码时为空',
  avatar VARCHAR(255) DEFAULT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_login_id (login_id),
  UNIQUE KEY uk_users_nickname (nickname)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Node 论坛用户';

CREATE TABLE IF NOT EXISTS posts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  section VARCHAR(50) NOT NULL COMMENT '版块名称',
  title VARCHAR(120) NOT NULL,
  content TEXT NOT NULL,
  images TEXT DEFAULT NULL COMMENT '配图 JSON 数组，最多 3 张',
  likes INT NOT NULL DEFAULT 0,
  featured TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否精选（推荐分区优先展示）',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_posts_section_created (section, created_at DESC),
  KEY idx_posts_user (user_id),
  CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Node 论坛帖子';

CREATE TABLE IF NOT EXISTS replies (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  post_id BIGINT UNSIGNED NOT NULL,
  user_id INT UNSIGNED NOT NULL,
  parent_id BIGINT UNSIGNED DEFAULT NULL COMMENT '回复的评论 id',
  content TEXT NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_replies_post (post_id, created_at),
  KEY idx_replies_user (user_id),
  KEY idx_replies_parent (parent_id),
  CONSTRAINT fk_replies_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
  CONSTRAINT fk_replies_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_replies_parent FOREIGN KEY (parent_id) REFERENCES replies (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Node 论坛回复';

INSERT IGNORE INTO schema_migrations (version, description)
VALUES (1, '初始结构：成员/轮协/留言/论坛/飞防/田哨/云种植/系统');

INSERT IGNORE INTO schema_migrations (version, description)
VALUES (2, 'Node 论坛/登录：users/posts/replies');
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
