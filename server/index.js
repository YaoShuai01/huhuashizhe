import express from 'express';

import authRouter from './auth.js';
import { db } from './db.js';

const app = express();
app.use(express.json({ limit: '100kb' }));

app.use('/api/auth', authRouter);

const POST_FIELDS = `
  p.id,
  p.section,
  p.title,
  p.content,
  p.likes,
  p.created_at,
  u.id       AS author_id,
  u.nickname AS author,
  (SELECT COUNT(*) FROM replies r WHERE r.post_id = p.id) AS reply_count
`;

const POST_FROM = `
  FROM posts p
  JOIN users u ON u.id = p.user_id
`;

function parsePositiveInt(value, fallback) {
  const n = Number.parseInt(value, 10);
  return Number.isInteger(n) && n >= 0 ? n : fallback;
}

// GET /api/posts?section=农友留言区&limit=20&offset=0
app.get('/api/posts', (req, res) => {
  const section = typeof req.query.section === 'string' ? req.query.section.trim() : '';
  const limit = Math.min(parsePositiveInt(req.query.limit, 20) || 20, 100);
  const offset = parsePositiveInt(req.query.offset, 0);

  const where = section ? 'WHERE p.section = ?' : '';
  const params = section ? [section, limit, offset] : [limit, offset];

  // 参数全部走占位符，杜绝字符串拼接注入
  const items = db
    .prepare(
      `SELECT ${POST_FIELDS} ${POST_FROM} ${where}
       ORDER BY p.created_at DESC, p.id DESC
       LIMIT ? OFFSET ?`,
    )
    .all(...params);

  const { total } = db
    .prepare(`SELECT COUNT(*) AS total FROM posts p ${where}`)
    .get(...(section ? [section] : []));

  res.json({ total, limit, offset, items });
});

// POST /api/posts
// body: { userId, section, title, content }
app.post('/api/posts', (req, res) => {
  const body = req.body ?? {};
  const userId = Number(body.userId);
  const section = typeof body.section === 'string' ? body.section.trim() : '';
  const title = typeof body.title === 'string' ? body.title.trim() : '';
  const content = typeof body.content === 'string' ? body.content.trim() : '';

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

  const user = db.prepare('SELECT id FROM users WHERE id = ?').get(userId);
  if (!user) {
    return res.status(404).json({ error: '用户不存在' });
  }

  const info = db
    .prepare('INSERT INTO posts (user_id, section, title, content) VALUES (?, ?, ?, ?)')
    .run(userId, section, title, content);

  const post = db
    .prepare(`SELECT ${POST_FIELDS} ${POST_FROM} WHERE p.id = ?`)
    .get(Number(info.lastInsertRowid));

  res.status(201).json(post);
});

app.use((req, res) => {
  res.status(404).json({ error: '接口不存在' });
});

// 请求体 JSON 解析失败等错误统一返回 400
app.use((err, req, res, next) => {
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: '请求体不是合法的 JSON' });
  }
  console.error(err);
  res.status(500).json({ error: '服务器内部错误' });
});

const port = Number(process.env.PORT) || 3000;
app.listen(port, () => {
  console.log(`论坛后端已启动：http://localhost:${port}`);
});
