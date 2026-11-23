import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * 论坛账号令牌：HMAC-SHA256 签名，格式 `<base64url(payload)>.<base64url(sig)>`
 *
 * 与 Java 轮协服务共用服务器 config.properties 里的 token.secret，
 * 这样同一个令牌既能在 Node 论坛后端校验，也能在 Java AI 代理校验。
 *
 * payload: { v: 1, uid: <users.id>, iat, exp }
 */

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const TOKEN_VERSION = 1;
/** 默认 30 天，可用 app.token.ttl.seconds 覆盖 */
const DEFAULT_TTL_SECONDS = 30 * 24 * 60 * 60;

let cachedSecret = '';
let cachedTtl = DEFAULT_TTL_SECONDS;

/** 读取 config.properties（不缓存文件内容，定时器之外只读一次） */
function readProperties() {
  const candidates = [
    process.env.FORUM_CONFIG,
    path.join(__dirname, '..', 'config', 'config.properties'),
    'C:\\huhuashizhe\\config\\config.properties',
  ].filter(Boolean);
  for (const file of candidates) {
    try {
      if (!fs.existsSync(file)) continue;
      const map = {};
      for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
        const text = line.trim();
        if (!text || text.startsWith('#')) continue;
        const index = text.indexOf('=');
        if (index < 0) continue;
        map[text.slice(0, index).trim()] = text.slice(index + 1).trim();
      }
      return map;
    } catch {
      // 读不到就尝试下一个候选
    }
  }
  return {};
}

function resolveSecret() {
  if (cachedSecret) return cachedSecret;
  const props = readProperties();
  const secret =
    process.env.TOKEN_SECRET || props['token.secret'] || props['app.token.secret'] || '';
  if (secret.length < 32) {
    // 没有共享密钥时退化为进程内随机密钥：能启动、能签发，但重启后旧令牌全部失效。
    // 服务器上 token.secret 由 Java 服务强制配置，正常不会走到这里。
    cachedSecret = crypto.randomBytes(32).toString('hex');
    console.warn(
      '[token] 未读取到 token.secret（至少 32 位），已临时生成随机密钥；重启后旧令牌会失效',
    );
  } else {
    cachedSecret = secret;
  }
  const ttl = Number(props['app.token.ttl.seconds']);
  if (Number.isInteger(ttl) && ttl > 0) cachedTtl = ttl;
  return cachedSecret;
}

function sign(body) {
  return crypto
    .createHmac('sha256', resolveSecret())
    .update(body)
    .digest('base64url');
}

/** 为账号签发令牌，返回 { token, expiresAt } */
export function issueToken(userId) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    v: TOKEN_VERSION,
    uid: Number(userId),
    iat: now,
    exp: now + cachedTtl,
  };
  const body = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  return {
    token: `${body}.${sign(body)}`,
    expiresAt: new Date(payload.exp * 1000).toISOString(),
  };
}

/** 校验令牌，成功返回 payload，失败返回 null */
export function verifyToken(token) {
  if (typeof token !== 'string' || !token) return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [body, signature] = parts;
  const expected = sign(body);
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (payload.v !== TOKEN_VERSION) return null;
    // 两种令牌：论坛账号令牌带 uid，轮协令牌带 role；都不具备则视为伪造
    const accountToken = Number.isInteger(payload.uid) && payload.uid > 0;
    const roleToken = payload.role === 'admin' || payload.role === 'member';
    if (!accountToken && !roleToken) return null;
    if (Number(payload.exp) <= Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

/** 从请求头取 token（支持 Authorization: Bearer <token>） */
export function tokenFromRequest(req) {
  const header = req.get?.('authorization') ?? req.headers?.authorization ?? '';
  if (typeof header !== 'string') return '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match ? match[1].trim() : '';
}

/**
 * 解析当前请求的登录用户 id。
 * 返回 0 表示未登录 / 令牌无效。
 */
export function currentUserId(req) {
  const payload = verifyToken(tokenFromRequest(req));
  return payload ? payload.uid : 0;
}
