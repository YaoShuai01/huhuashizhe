import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import mysql from 'mysql2/promise';

import { dbConfig, pool } from './db.js';

const root = dirname(fileURLToPath(import.meta.url));

// 建库阶段还没有 huhuashizhe，先不指定 database 连接
const connection = await mysql.createConnection({
  host: dbConfig.host,
  port: dbConfig.port,
  user: dbConfig.user,
  password: dbConfig.password,
  charset: 'utf8mb4',
  multipleStatements: true,
});

try {
  await connection.query(readFileSync(join(root, 'mysql', 'schema.sql'), 'utf8'));
  await connection.query(readFileSync(join(root, 'mysql', 'seed.sql'), 'utf8'));
  console.log('已执行 mysql/schema.sql 与 mysql/seed.sql');
} finally {
  await connection.end();
}

const [[counts]] = await pool.query(
  `SELECT
     (SELECT COUNT(*) FROM users)   AS users,
     (SELECT COUNT(*) FROM posts)   AS posts,
     (SELECT COUNT(*) FROM replies) AS replies`,
);
console.log(`MySQL 初始化完成：users=${counts.users} posts=${counts.posts} replies=${counts.replies}`);
await pool.end();
