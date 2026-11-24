import { randomBytes, randomInt, scryptSync, timingSafeEqual } from 'node:crypto';

import { Router } from 'express';

import { pool } from './db.js';
import { isAdminUserId } from './admin.js';
import { issueToken, currentUserId } from './token.js';

const router = Router();

const NICKNAME_MIN = 5;
const NICKNAME_MAX = 6;
const PASSWORD_MIN = 6;
const PASSWORD_MAX = 32;
const LOGIN_ID_PATTERN = /^\d{8}$/;

/** 登录 / 注册限流：同一 IP 每分钟最多 8 次，防止 8 位登录号被在线撞库 */
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 8;
const rateBuckets = new Map();

function allowAttempt(ip) {
  const now = Date.now();
  const key = ip || 'unknown';
  const hits = (rateBuckets.get(key) ?? []).filter(
    (at) => now - at < RATE_WINDOW_MS,
  );
  if (hits.length >= RATE_MAX) {
    rateBuckets.set(key, hits);
    return false;
  }
  hits.push(now);
  rateBuckets.set(key, hits);
  if (rateBuckets.size > 5000) {
    for (const [bucketKey, list] of rateBuckets) {
      if (list.every((at) => now - at >= RATE_WINDOW_MS)) {
        rateBuckets.delete(bucketKey);
      }
    }
  }
  return true;
}

/** 经本机反向代理（Tomcat /forum）时取 X-Forwarded-For，否则直连地址 */
function clientIp(req) {
  const remote = req.socket?.remoteAddress ?? '';
  const local = remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
  if (local) {
    const forwarded = req.headers['x-forwarded-for'];
    if (typeof forwarded === 'string' && forwarded.trim()) {
      return forwarded.split(',')[0].trim();
    }
  }
  return remote;
}

const asyncHandler = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch(next);

function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const key = scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${key}`;
}

function verifyPassword(password, stored) {
  if (!stored) return false;
  const [salt, key] = stored.split(':');
  if (!salt || !key) return false;
  const expected = Buffer.from(key, 'hex');
  const actual = scryptSync(password, salt, expected.length);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

/** 系统生成 8 位数字登录号，如 30219845 */
function generateLoginId() {
  return String(randomInt(10000000, 100000000));
}

function validNickname(nickname) {
  return nickname.length >= NICKNAME_MIN && nickname.length <= NICKNAME_MAX;
}

function validPassword(password) {
  return password.length >= PASSWORD_MIN && password.length <= PASSWORD_MAX;
}

// POST /api/auth/register  { nickname, password }
// 设置密码的同时，系统自动分配一个唯一登录号
router.post(
  '/register',
  asyncHandler(async (req, res) => {
    const nickname =
      typeof req.body?.nickname === 'string' ? req.body.nickname.trim() : '';
    const password =
      typeof req.body?.password === 'string' ? req.body.password : '';

    if (!validNickname(nickname)) {
      return res
        .status(400)
        .json({ error: `昵称需为 ${NICKNAME_MIN}-${NICKNAME_MAX} 个字符` });
    }
    if (!validPassword(password)) {
      return res
        .status(400)
        .json({ error: `密码需为 ${PASSWORD_MIN}-${PASSWORD_MAX} 位` });
    }
    if (!allowAttempt(clientIp(req))) {
      return res.status(429).json({ error: '操作太频繁，请稍后再试' });
    }

    const passwordHash = hashPassword(password);

    // 登录号随机生成，极小概率撞号时重试
    for (let attempt = 0; attempt < 5; attempt++) {
      const loginId = generateLoginId();
      try {
        const [result] = await pool.execute(
          'INSERT INTO users (login_id, nickname, password_hash) VALUES (?, ?, ?)',
          [loginId, nickname, passwordHash],
        );
        return res.status(201).json({
          id: result.insertId,
          loginId,
          nickname,
          isAdmin: isAdminUserId(result.insertId),
          ...issueToken(result.insertId),
        });
      } catch (error) {
        if (error?.code !== 'ER_DUP_ENTRY') throw error;
        if (String(error.message).includes('uk_users_nickname')) {
          return res.status(409).json({ error: '该昵称已被使用，请换一个' });
        }
        // 登录号冲突，换一个重试
      }
    }

    res.status(500).json({ error: '登录号生成失败，请重试' });
  }),
);

// POST /api/auth/login  { loginId, password }
router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const loginId =
      typeof req.body?.loginId === 'string' ? req.body.loginId.trim() : '';
    const password =
      typeof req.body?.password === 'string' ? req.body.password : '';

    if (!LOGIN_ID_PATTERN.test(loginId) || !validPassword(password)) {
      return res.status(400).json({ error: '登录号或密码格式不正确' });
    }
    if (!allowAttempt(clientIp(req))) {
      return res.status(429).json({ error: '操作太频繁，请稍后再试' });
    }

    const [rows] = await pool.execute(
      'SELECT id, login_id, nickname, password_hash FROM users WHERE login_id = ?',
      [loginId],
    );
    const user = rows[0];

    // 统一提示，避免暴露登录号是否存在
    if (!user || !verifyPassword(password, user.password_hash)) {
      return res.status(401).json({ error: '登录号或密码错误' });
    }

    res.json({
      id: user.id,
      loginId: user.login_id,
      nickname: user.nickname,
      isAdmin: isAdminUserId(user.id),
      ...issueToken(user.id),
    });
  }),
);

// POST /api/auth/profile  { nickname }，昵称以令牌里的账号为准，禁止代改他人昵称
// 修改昵称：论坛帖子/评论查询时 JOIN users，历史内容会同步展示新昵称
router.post(
  '/profile',
  asyncHandler(async (req, res) => {
    const userId = currentUserId(req);
    const nickname =
      typeof req.body?.nickname === 'string' ? req.body.nickname.trim() : '';

    if (userId <= 0) {
      return res.status(401).json({ error: '请先登录后再修改资料' });
    }
    if (!validNickname(nickname)) {
      return res
        .status(400)
        .json({ error: `昵称需为 ${NICKNAME_MIN}-${NICKNAME_MAX} 个字符` });
    }

    try {
      const [result] = await pool.execute(
        'UPDATE users SET nickname = ? WHERE id = ?',
        [nickname, userId],
      );
      // 昵称未变化时 affectedRows 也是 0，需再确认账号是否存在
      if (result.affectedRows === 0) {
        const [exists] = await pool.execute(
          'SELECT id FROM users WHERE id = ?',
          [userId],
        );
        if (exists.length === 0) {
          return res.status(404).json({ error: '账号不存在，请重新登录' });
        }
      }
      return res.json({ id: userId, nickname });
    } catch (error) {
      if (error?.code === 'ER_DUP_ENTRY') {
        return res.status(409).json({ error: '该昵称已被使用，请换一个' });
      }
      throw error;
    }
  }),
);

export default router;
