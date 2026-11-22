import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const dataDir = join(root, 'data');
mkdirSync(dataDir, { recursive: true });

/** 共用数据库连接：data/forum.db */
export const db = new DatabaseSync(join(dataDir, 'forum.db'));

db.exec('PRAGMA journal_mode = WAL;');
db.exec('PRAGMA foreign_keys = ON;');

/** 建表（幂等，可重复执行） */
export function initSchema() {
  db.exec(readFileSync(join(root, 'schema.sql'), 'utf8'));
}

initSchema();

// 兼容旧库：users 表补充密码字段
const userColumns = db
  .prepare('PRAGMA table_info(users)')
  .all()
  .map((column) => column.name);
if (!userColumns.includes('password_hash')) {
  db.exec('ALTER TABLE users ADD COLUMN password_hash TEXT');
}
