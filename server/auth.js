import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

import { Router } from 'express';

import { db } from './db.js';

const router = Router();

const NICKNAME_MIN = 2;
const NICKNAME_MAX = 20;
const PASSWORD_MIN = 6;
const PASSWORD_MAX = 32;

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

function readCredentials(body) {
  const nickname = typeof body?.nickname === 'string' ? body.nickname.trim() : '';
  const password = typeof body?.password === 'string' ? body.password : '';
  return { nickname, password };
}

function validNickname(nickname) {
  return nickname.length >= NICKNAME_MIN && nickname.length <= NICKNAME_MAX;
}

function validPassword(password) {
  return password.length >= PASSWORD_MIN && password.length <= PASSWORD_MAX;
}

// POST /api/auth/register  { nickname, password }
// 昵称即账号：昵称未被占用则新建；已存在但还没设置密码的，补设密码
router.post('/register', (req, res) => {
  const { nickname, password } = readCredentials(req.body);

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

  const existing = db
    .prepare('SELECT id, password_hash FROM users WHERE nickname = ?')
    .get(nickname);

  if (existing?.password_hash) {
    return res.status(409).json({ error: '该昵称已设置过密码，请直接登录' });
  }

  const passwordHash = hashPassword(password);

  if (existing) {
    db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(
      passwordHash,
      existing.id,
    );
    return res.status(200).json({ id: existing.id, nickname });
  }

  // 昵称与密码都走参数化查询
  const info = db
    .prepare('INSERT INTO users (nickname, password_hash) VALUES (?, ?)')
    .run(nickname, passwordHash);

  res.status(201).json({ id: Number(info.lastInsertRowid), nickname });
});

// POST /api/auth/login  { nickname, password }
router.post('/login', (req, res) => {
  const { nickname, password } = readCredentials(req.body);

  if (!validNickname(nickname) || !validPassword(password)) {
    return res.status(400).json({ error: '昵称或密码格式不正确' });
  }

  const user = db
    .prepare('SELECT id, nickname, password_hash FROM users WHERE nickname = ?')
    .get(nickname);

  // 统一提示，避免暴露昵称是否存在
  if (!user || !verifyPassword(password, user.password_hash)) {
    return res.status(401).json({ error: '昵称或密码错误' });
  }

  res.json({ id: user.id, nickname: user.nickname });
});

export default router;
