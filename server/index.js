import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import express from 'express';

import authRouter from './auth.js';
import { pool } from './db.js';

const app = express();
// 图片以 base64 放在 JSON 里上传，最大 8MB 图片约 11MB，留出余量
app.use(express.json({ limit: '15mb' }));

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const UPLOAD_DIR = path.join(__dirname, 'uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });
app.use('/uploads', express.static(UPLOAD_DIR));

// 允许 Flutter Web 跨域调用本服务
app.use((req, res, next) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  res.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

app.use('/api/auth', authRouter);

const POST_FIELDS = `
  p.id,
  p.section,
  p.title,
  p.content,
  p.images,
  p.likes,
  p.featured,
  DATE_FORMAT(p.created_at, '%Y-%m-%d %H:%i:%s') AS created_at,
  u.id       AS author_id,
  u.nickname AS author,
  (SELECT COUNT(*) FROM replies r WHERE r.post_id = p.id) AS reply_count
`;

const POST_FROM = `
  FROM posts p
  JOIN users u ON u.id = p.user_id
`;

const REPLY_FIELDS = `
  r.id,
  r.post_id,
  r.parent_id,
  r.content,
  DATE_FORMAT(r.created_at, '%Y-%m-%d %H:%i:%s') AS created_at,
  u.id       AS author_id,
  u.nickname AS author,
  pu.nickname AS parent_author
`;

const REPLY_FROM = `
  FROM replies r
  JOIN users u ON u.id = r.user_id
  LEFT JOIN replies pr ON pr.id = r.parent_id
  LEFT JOIN users pu ON pu.id = pr.user_id
`;

const asyncHandler = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch(next);

function parsePositiveInt(value, fallback) {
  const n = Number.parseInt(value, 10);
  return Number.isInteger(n) && n >= 0 ? n : fallback;
}

// 数据库里保存的是 JSON 字符串，返回给客户端时还原成数组
function parseImages(value) {
  if (!value) return [];
  try {
    const arr = typeof value === 'string' ? JSON.parse(value) : value;
    if (!Array.isArray(arr)) return [];
    return arr
      .filter((url) => typeof url === 'string' && /^\/uploads\/[\w.-]+$/.test(url))
      .slice(0, 3);
  } catch {
    return [];
  }
}

// 只接受本服务上传接口生成的 /uploads/ 路径，非法时返回 null
function normalizeImages(value) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 3) return null;
  const result = [];
  for (const item of value) {
    if (typeof item !== 'string' || !/^\/uploads\/[\w.-]+$/.test(item)) {
      return null;
    }
    result.push(item);
  }
  return result;
}

function withParsedImages(row) {
  return {
    ...row,
    images: parseImages(row.images),
    liked: Boolean(row.liked),
    favorited: Boolean(row.favorited),
    featured: Boolean(row.featured),
  };
}

// 消息正文只存摘要，避免超长
function clip(text, max = 120) {
  const value = String(text ?? '').trim();
  return value.length > max ? `${value.slice(0, max)}…` : value;
}

// 给帖子作者写一条消息提醒，自己的操作不提醒自己。
// 消息只是提醒，写入失败不能影响点赞 / 收藏 / 评论本身。
async function notifyPostAuthor({ authorId, actorId, kind, postId, title, body }) {
  if (!authorId || authorId === actorId) return;
  try {
    // 点赞 / 收藏重复触发时不重复提醒（评论每次都提醒）
    if (kind !== 'reply') {
      const [exists] = await pool.execute(
        `SELECT id FROM forum_messages
         WHERE user_id = ? AND actor_id = ? AND kind = ? AND post_id = ?
         LIMIT 1`,
        [authorId, actorId, kind, postId],
      );
      if (exists.length > 0) return;
    }
    await pool.execute(
      `INSERT INTO forum_messages (user_id, actor_id, kind, post_id, title, body)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [authorId, actorId, kind, postId, clip(title, 120), clip(body, 255)],
    );
  } catch (error) {
    console.error('消息提醒写入失败:', error.message);
  }
}

const ALLOWED_IMAGE_EXT = new Set(['jpg', 'jpeg', 'png', 'webp']);
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

// POST /api/uploads
// body: { userId, ext, data(base64) }
app.post(
  '/api/uploads',
  asyncHandler(async (req, res) => {
    const body = req.body ?? {};
    const userId = Number(body.userId);
    const ext =
      typeof body.ext === 'string'
        ? body.ext.toLowerCase().replace(/^\./, '')
        : '';
    const data = typeof body.data === 'string' ? body.data : '';

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }
    if (!ALLOWED_IMAGE_EXT.has(ext)) {
      return res.status(400).json({ error: '仅支持 jpg/jpeg/png/webp 图片' });
    }
    if (!data) {
      return res.status(400).json({ error: '图片数据不能为空' });
    }

    let buffer;
    try {
      buffer = Buffer.from(data, 'base64');
    } catch {
      return res.status(400).json({ error: '图片数据格式错误' });
    }
    if (buffer.length === 0) {
      return res.status(400).json({ error: '图片数据格式错误' });
    }
    if (buffer.length > MAX_IMAGE_BYTES) {
      return res.status(400).json({ error: '图片不能超过 8MB' });
    }

    const [users] = await pool.execute(
      'SELECT id FROM users WHERE id = ?',
      [userId],
    );
    if (users.length === 0) {
      return res.status(404).json({ error: '用户不存在' });
    }

    const fileName = `${randomUUID()}.${ext === 'jpeg' ? 'jpg' : ext}`;
    await fs.promises.writeFile(path.join(UPLOAD_DIR, fileName), buffer);
    res.status(201).json({ url: `/uploads/${fileName}` });
  }),
);

// GET /api/posts?section=农友留言区&limit=20&offset=0&userId=1
app.get(
  '/api/posts',
  asyncHandler(async (req, res) => {
    const section =
      typeof req.query.section === 'string' ? req.query.section.trim() : '';
    const limit = Math.min(parsePositiveInt(req.query.limit, 20) || 20, 100);
    const offset = parsePositiveInt(req.query.offset, 0);
    const rawUserId = Number(req.query.userId);
    const userId =
      Number.isInteger(rawUserId) && rawUserId > 0 ? rawUserId : null;

    // 传入 userId 时顺带返回该用户是否点过赞 / 收藏过
    const userFields = userId
      ? `EXISTS(SELECT 1 FROM post_likes pl
                WHERE pl.post_id = p.id AND pl.user_id = ?) AS liked,
         EXISTS(SELECT 1 FROM post_favorites pf
                WHERE pf.post_id = p.id AND pf.user_id = ?) AS favorited`
      : '0 AS liked, 0 AS favorited';

    const where = section ? 'WHERE p.section = ?' : '';
    const params = userId ? [userId, userId] : [];
    if (section) params.push(section);
    params.push(limit, offset);

    // 全部走占位符，杜绝 SQL 注入
    const [items] = await pool.execute(
      `SELECT ${POST_FIELDS}, ${userFields} ${POST_FROM} ${where}
       ORDER BY p.created_at DESC, p.id DESC
       LIMIT ? OFFSET ?`,
      params,
    );
    const [countRows] = await pool.execute(
      `SELECT COUNT(*) AS total FROM posts p ${where}`,
      section ? [section] : [],
    );

    res.json({
      total: countRows[0].total,
      limit,
      offset,
      items: items.map(withParsedImages),
    });
  }),
);

// POST /api/posts
// body: { userId, section, title, content, images?: string[] }
app.post(
  '/api/posts',
  asyncHandler(async (req, res) => {
    const body = req.body ?? {};
    const userId = Number(body.userId);
    const section = typeof body.section === 'string' ? body.section.trim() : '';
    const title = typeof body.title === 'string' ? body.title.trim() : '';
    const content = typeof body.content === 'string' ? body.content.trim() : '';
    const images = normalizeImages(body.images);

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }
    if (!section || section.length > 50) {
      return res.status(400).json({ error: 'section 不能为空且不超过 50 字' });
    }
    if (!title || title.length > 120) {
      return res.status(400).json({ error: 'title 不能为空且不超过 120 字' });
    }
    if (!content || content.length > 5000) {
      return res.status(400).json({ error: 'content 不能为空且不超过 5000 字' });
    }
    if (images === null) {
      return res
        .status(400)
        .json({ error: 'images 最多 3 张且必须是已上传的图片地址' });
    }

    const [users] = await pool.execute(
      'SELECT id FROM users WHERE id = ?',
      [userId],
    );
    if (users.length === 0) {
      return res.status(404).json({ error: '用户不存在' });
    }

    const [result] = await pool.execute(
      'INSERT INTO posts (user_id, section, title, content, images) VALUES (?, ?, ?, ?, ?)',
      [
        userId,
        section,
        title,
        content,
        images.length > 0 ? JSON.stringify(images) : null,
      ],
    );

    const [rows] = await pool.execute(
      `SELECT ${POST_FIELDS} ${POST_FROM} WHERE p.id = ?`,
      [result.insertId],
    );

    res.status(201).json(withParsedImages(rows[0]));
  }),
);

// GET /api/posts/:id/replies
app.get(
  '/api/posts/:id/replies',
  asyncHandler(async (req, res) => {
    const postId = Number(req.params.id);
    if (!Number.isInteger(postId) || postId <= 0) {
      return res.status(400).json({ error: '帖子 id 不合法' });
    }

    const [items] = await pool.execute(
      `SELECT ${REPLY_FIELDS} ${REPLY_FROM}
       WHERE r.post_id = ?
       ORDER BY r.created_at ASC, r.id ASC`,
      [postId],
    );

    res.json({ items });
  }),
);

// POST /api/posts/:id/replies
// body: { userId, content, parentId? }，parentId 表示回复某条评论
app.post(
  '/api/posts/:id/replies',
  asyncHandler(async (req, res) => {
    const postId = Number(req.params.id);
    const body = req.body ?? {};
    const userId = Number(body.userId);
    const content =
      typeof body.content === 'string' ? body.content.trim() : '';
    const parentId = body.parentId == null ? null : Number(body.parentId);

    if (!Number.isInteger(postId) || postId <= 0) {
      return res.status(400).json({ error: '帖子 id 不合法' });
    }
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }
    if (!content || content.length > 450) {
      return res.status(400).json({ error: '评论不能为空且不超过 450 字' });
    }
    if (parentId != null && (!Number.isInteger(parentId) || parentId <= 0)) {
      return res.status(400).json({ error: '回复的评论 id 不合法' });
    }

    const [posts] = await pool.execute(
      'SELECT id, user_id, title FROM posts WHERE id = ?',
      [postId],
    );
    if (posts.length === 0) {
      return res.status(404).json({ error: '帖子不存在' });
    }

    const [users] = await pool.execute(
      'SELECT id, nickname FROM users WHERE id = ?',
      [userId],
    );
    if (users.length === 0) {
      return res.status(404).json({ error: '用户不存在' });
    }

    // 校验被回复的评论存在且属于同一帖子
    let parent = null;
    if (parentId != null) {
      const [parents] = await pool.execute(
        'SELECT id, post_id, user_id FROM replies WHERE id = ?',
        [parentId],
      );
      if (parents.length === 0) {
        return res.status(404).json({ error: '回复的评论不存在' });
      }
      if (Number(parents[0].post_id) !== postId) {
        return res.status(400).json({ error: '回复的评论不属于该帖子' });
      }
      parent = parents[0];
    }

    const [result] = await pool.execute(
      'INSERT INTO replies (post_id, user_id, parent_id, content) VALUES (?, ?, ?, ?)',
      [postId, userId, parentId, content],
    );

    // 评论后给帖子作者发一条消息提醒
    await notifyPostAuthor({
      authorId: posts[0].user_id,
      actorId: userId,
      kind: 'reply',
      postId,
      title: `${users[0].nickname} 评论了你的帖子`,
      body: `「${posts[0].title}」${content}`,
    });

    // 回复的是别人的评论时，同时提醒被回复人
    if (parent && Number(parent.user_id) !== Number(posts[0].user_id)) {
      await notifyPostAuthor({
        authorId: parent.user_id,
        actorId: userId,
        kind: 'reply',
        postId,
        title: `${users[0].nickname} 回复了你的评论`,
        body: `「${posts[0].title}」${content}`,
      });
    }

    const [rows] = await pool.execute(
      `SELECT ${REPLY_FIELDS} ${REPLY_FROM} WHERE r.id = ?`,
      [result.insertId],
    );

    res.status(201).json(rows[0]);
  }),
);

// POST /api/posts/:id/like
// body: { userId, liked: boolean }，liked 为目标状态，重复请求不会叠加
app.post(
  '/api/posts/:id/like',
  asyncHandler(async (req, res) => {
    const postId = Number(req.params.id);
    const userId = Number(req.body?.userId);
    const liked = req.body?.liked === true;

    if (!Number.isInteger(postId) || postId <= 0) {
      return res.status(400).json({ error: '帖子 id 不合法' });
    }
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }

    const [posts] = await pool.execute(
      'SELECT id, user_id, title FROM posts WHERE id = ?',
      [postId],
    );
    if (posts.length === 0) {
      return res.status(404).json({ error: '帖子不存在' });
    }
    const [users] = await pool.execute(
      'SELECT id, nickname FROM users WHERE id = ?',
      [userId],
    );
    if (users.length === 0) {
      return res.status(404).json({ error: '用户不存在' });
    }

    if (liked) {
      await pool.execute(
        'INSERT IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)',
        [postId, userId],
      );
      await notifyPostAuthor({
        authorId: posts[0].user_id,
        actorId: userId,
        kind: 'like',
        postId,
        title: `${users[0].nickname} 赞了你的帖子`,
        body: `「${posts[0].title}」`,
      });
    } else {
      await pool.execute(
        'DELETE FROM post_likes WHERE post_id = ? AND user_id = ?',
        [postId, userId],
      );
    }

    const [countRows] = await pool.execute(
      'SELECT COUNT(*) AS total FROM post_likes WHERE post_id = ?',
      [postId],
    );
    await pool.execute('UPDATE posts SET likes = ? WHERE id = ?', [
      countRows[0].total,
      postId,
    ]);

    res.json({ liked, likes: countRows[0].total });
  }),
);

// POST /api/posts/:id/favorite
// body: { userId, favorited: boolean }
app.post(
  '/api/posts/:id/favorite',
  asyncHandler(async (req, res) => {
    const postId = Number(req.params.id);
    const userId = Number(req.body?.userId);
    const favorited = req.body?.favorited === true;

    if (!Number.isInteger(postId) || postId <= 0) {
      return res.status(400).json({ error: '帖子 id 不合法' });
    }
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }

    const [posts] = await pool.execute(
      'SELECT id, user_id, title FROM posts WHERE id = ?',
      [postId],
    );
    if (posts.length === 0) {
      return res.status(404).json({ error: '帖子不存在' });
    }
    const [users] = await pool.execute(
      'SELECT id, nickname FROM users WHERE id = ?',
      [userId],
    );
    if (users.length === 0) {
      return res.status(404).json({ error: '用户不存在' });
    }

    if (favorited) {
      await pool.execute(
        'INSERT IGNORE INTO post_favorites (post_id, user_id) VALUES (?, ?)',
        [postId, userId],
      );
      await notifyPostAuthor({
        authorId: posts[0].user_id,
        actorId: userId,
        kind: 'favorite',
        postId,
        title: `${users[0].nickname} 收藏了你的帖子`,
        body: `「${posts[0].title}」`,
      });
    } else {
      await pool.execute(
        'DELETE FROM post_favorites WHERE post_id = ? AND user_id = ?',
        [postId, userId],
      );
    }

    res.json({ favorited });
  }),
);

// POST /api/posts/:id/feature
// body: { userId, featured: boolean }，仅作者可设置自己的帖子为精选
app.post(
  '/api/posts/:id/feature',
  asyncHandler(async (req, res) => {
    const postId = Number(req.params.id);
    const userId = Number(req.body?.userId);
    const featured = req.body?.featured === true;

    if (!Number.isInteger(postId) || postId <= 0) {
      return res.status(400).json({ error: '帖子 id 不合法' });
    }
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }

    const [posts] = await pool.execute(
      'SELECT id, user_id FROM posts WHERE id = ?',
      [postId],
    );
    if (posts.length === 0) {
      return res.status(404).json({ error: '帖子不存在' });
    }
    if (Number(posts[0].user_id) !== userId) {
      return res.status(403).json({ error: '只能将自己的帖子设为精选' });
    }

    await pool.execute('UPDATE posts SET featured = ? WHERE id = ?', [
      featured ? 1 : 0,
      postId,
    ]);

    res.json({ featured });
  }),
);

// DELETE /api/posts/:id?userId=1，仅作者可删除自己的帖子
app.delete(
  '/api/posts/:id',
  asyncHandler(async (req, res) => {
    const postId = Number(req.params.id);
    const userId = Number(req.query.userId);

    if (!Number.isInteger(postId) || postId <= 0) {
      return res.status(400).json({ error: '帖子 id 不合法' });
    }
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }

    const [posts] = await pool.execute(
      'SELECT id, user_id FROM posts WHERE id = ?',
      [postId],
    );
    if (posts.length === 0) {
      return res.status(404).json({ error: '帖子不存在' });
    }
    if (Number(posts[0].user_id) !== userId) {
      return res.status(403).json({ error: '只能删除自己的帖子' });
    }

    // 评论、点赞、收藏随外键级联删除
    await pool.execute('DELETE FROM posts WHERE id = ?', [postId]);
    res.json({ deleted: true });
  }),
);

// DELETE /api/replies/:id?userId=1，仅作者可删除自己的评论
app.delete(
  '/api/replies/:id',
  asyncHandler(async (req, res) => {
    const replyId = Number(req.params.id);
    const userId = Number(req.query.userId);

    if (!Number.isInteger(replyId) || replyId <= 0) {
      return res.status(400).json({ error: '评论 id 不合法' });
    }
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }

    const [rows] = await pool.execute(
      'SELECT id, user_id FROM replies WHERE id = ?',
      [replyId],
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: '评论不存在' });
    }
    if (Number(rows[0].user_id) !== userId) {
      return res.status(403).json({ error: '只能删除自己的评论' });
    }

    // 回复该评论的内容随外键级联删除
    await pool.execute('DELETE FROM replies WHERE id = ?', [replyId]);
    res.json({ deleted: true });
  }),
);

// POST /api/reports
// body: { userId, targetType: 'post' | 'reply', targetId, reason }
app.post(
  '/api/reports',
  asyncHandler(async (req, res) => {
    const body = req.body ?? {};
    const userId = Number(body.userId);
    const targetType = body.targetType;
    const targetId = Number(body.targetId);
    const reason = typeof body.reason === 'string' ? body.reason.trim() : '';

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }
    if (targetType !== 'post' && targetType !== 'reply') {
      return res.status(400).json({ error: '投诉类型不合法' });
    }
    if (!Number.isInteger(targetId) || targetId <= 0) {
      return res.status(400).json({ error: '投诉内容 id 不合法' });
    }
    if (!reason || reason.length > 50) {
      return res.status(400).json({ error: '请选择投诉原因' });
    }

    const [users] = await pool.execute(
      'SELECT id FROM users WHERE id = ?',
      [userId],
    );
    if (users.length === 0) {
      return res.status(404).json({ error: '用户不存在' });
    }

    // targetType 已限定为白名单，可安全拼表名
    const table = targetType === 'post' ? 'posts' : 'replies';
    const [targets] = await pool.execute(
      `SELECT id FROM ${table} WHERE id = ?`,
      [targetId],
    );
    if (targets.length === 0) {
      return res.status(404).json({ error: '投诉的内容不存在' });
    }

    // 同一用户对同一内容只保留一条投诉，重复提交时更新原因
    await pool.execute(
      `INSERT INTO reports (target_type, target_id, user_id, reason)
       VALUES (?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE reason = VALUES(reason)`,
      [targetType, targetId, userId, reason],
    );

    res.status(201).json({ reported: true });
  }),
);

// GET /api/messages?userId=1&limit=50
app.get(
  '/api/messages',
  asyncHandler(async (req, res) => {
    const userId = Number(req.query.userId);
    const limit = Math.min(parsePositiveInt(req.query.limit, 50) || 50, 100);

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }

    const [items] = await pool.execute(
      `SELECT id, kind, post_id, title, body,
              DATE_FORMAT(created_at, '%Y-%m-%d %H:%i:%s') AS created_at,
              read_at
       FROM forum_messages
       WHERE user_id = ?
       ORDER BY created_at DESC, id DESC
       LIMIT ?`,
      [userId, limit],
    );

    res.json({
      items: items.map((item) => ({
        ...item,
        unread: item.read_at == null,
      })),
    });
  }),
);

// POST /api/messages/read
// body: { userId, id? }，不带 id 表示全部已读
app.post(
  '/api/messages/read',
  asyncHandler(async (req, res) => {
    const userId = Number(req.body?.userId);
    const rawId = req.body?.id;
    const messageId = rawId == null ? null : Number(rawId);

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }
    if (messageId != null && (!Number.isInteger(messageId) || messageId <= 0)) {
      return res.status(400).json({ error: '消息 id 不合法' });
    }

    if (messageId == null) {
      await pool.execute(
        'UPDATE forum_messages SET read_at = NOW() WHERE user_id = ? AND read_at IS NULL',
        [userId],
      );
    } else {
      await pool.execute(
        'UPDATE forum_messages SET read_at = NOW() WHERE id = ? AND user_id = ? AND read_at IS NULL',
        [messageId, userId],
      );
    }

    res.json({ ok: true });
  }),
);

app.use((req, res) => {
  res.status(404).json({ error: '接口不存在' });
});

// 请求体 JSON 解析失败等错误统一返回 400
app.use((err, req, res, next) => {
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: '请求体不是合法的 JSON' });
  }
  if (err?.type === 'entity.too.large') {
    return res.status(413).json({ error: '图片过大，请重新选择后上传' });
  }
  console.error(err);
  res.status(500).json({ error: '服务器内部错误' });
});

// 启动时自动补齐新增字段，旧库无需手动执行迁移
async function ensureSchema() {
  await pool.query(`
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
    ) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci
      COMMENT = '投诉记录'
  `);

  const [columns] = await pool.query(
    `SELECT TABLE_NAME, COLUMN_NAME
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND ((TABLE_NAME = 'posts' AND COLUMN_NAME = 'featured')
          OR (TABLE_NAME = 'replies' AND COLUMN_NAME = 'parent_id'))`,
  );
  const existing = new Set(
    columns.map((column) => `${column.TABLE_NAME}.${column.COLUMN_NAME}`),
  );

  if (!existing.has('posts.featured')) {
    await pool.query(
      "ALTER TABLE posts ADD COLUMN featured TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否精选（推荐分区优先展示）' AFTER likes",
    );
  }
  if (!existing.has('replies.parent_id')) {
    await pool.query(
      "ALTER TABLE replies ADD COLUMN parent_id BIGINT UNSIGNED DEFAULT NULL COMMENT '回复的评论 id' AFTER user_id",
    );
    await pool.query(
      'ALTER TABLE replies ADD KEY idx_replies_parent (parent_id)',
    );
    await pool.query(
      'ALTER TABLE replies ADD CONSTRAINT fk_replies_parent FOREIGN KEY (parent_id) REFERENCES replies (id) ON DELETE CASCADE',
    );
  }
}

await ensureSchema().catch((error) => {
  console.error('数据库结构检查失败:', error);
});

const port = Number(process.env.PORT) || 3000;
app.listen(port, () => {
  console.log(`论坛后端已启动：http://localhost:${port}`);
});
