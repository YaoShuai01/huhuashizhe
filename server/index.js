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
  r.content,
  DATE_FORMAT(r.created_at, '%Y-%m-%d %H:%i:%s') AS created_at,
  u.id       AS author_id,
  u.nickname AS author
`;

const REPLY_FROM = `
  FROM replies r
  JOIN users u ON u.id = r.user_id
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
  return { ...row, images: parseImages(row.images) };
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

// GET /api/posts?section=农友留言区&limit=20&offset=0
app.get(
  '/api/posts',
  asyncHandler(async (req, res) => {
    const section =
      typeof req.query.section === 'string' ? req.query.section.trim() : '';
    const limit = Math.min(parsePositiveInt(req.query.limit, 20) || 20, 100);
    const offset = parsePositiveInt(req.query.offset, 0);

    const where = section ? 'WHERE p.section = ?' : '';
    const params = section ? [section, limit, offset] : [limit, offset];

    // 全部走占位符，杜绝 SQL 注入
    const [items] = await pool.execute(
      `SELECT ${POST_FIELDS} ${POST_FROM} ${where}
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
// body: { userId, content }
app.post(
  '/api/posts/:id/replies',
  asyncHandler(async (req, res) => {
    const postId = Number(req.params.id);
    const body = req.body ?? {};
    const userId = Number(body.userId);
    const content =
      typeof body.content === 'string' ? body.content.trim() : '';

    if (!Number.isInteger(postId) || postId <= 0) {
      return res.status(400).json({ error: '帖子 id 不合法' });
    }
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ error: 'userId 必须是正整数' });
    }
    if (!content || content.length > 450) {
      return res.status(400).json({ error: '评论不能为空且不超过 450 字' });
    }

    const [posts] = await pool.execute(
      'SELECT id FROM posts WHERE id = ?',
      [postId],
    );
    if (posts.length === 0) {
      return res.status(404).json({ error: '帖子不存在' });
    }

    const [users] = await pool.execute(
      'SELECT id FROM users WHERE id = ?',
      [userId],
    );
    if (users.length === 0) {
      return res.status(404).json({ error: '用户不存在' });
    }

    const [result] = await pool.execute(
      'INSERT INTO replies (post_id, user_id, content) VALUES (?, ?, ?)',
      [postId, userId, content],
    );

    const [rows] = await pool.execute(
      `SELECT ${REPLY_FIELDS} ${REPLY_FROM} WHERE r.id = ?`,
      [result.insertId],
    );

    res.status(201).json(rows[0]);
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

const port = Number(process.env.PORT) || 3000;
app.listen(port, () => {
  console.log(`论坛后端已启动：http://localhost:${port}`);
});
