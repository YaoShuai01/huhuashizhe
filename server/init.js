import { db, initSchema } from './db.js';

// 建表（幂等）
initSchema();

// 首次初始化时创建一个演示用户，方便直接调用发帖接口
const { total } = db.prepare('SELECT COUNT(*) AS total FROM users').get();
if (total === 0) {
  const info = db
    .prepare('INSERT INTO users (nickname) VALUES (?)')
    .run('农友小助手');
  console.log(`已创建演示用户，id = ${info.lastInsertRowid}`);
}

const counts = db
  .prepare(
    `SELECT
       (SELECT COUNT(*) FROM users)   AS users,
       (SELECT COUNT(*) FROM posts)   AS posts,
       (SELECT COUNT(*) FROM replies) AS replies`,
  )
  .get();

console.log(`数据库初始化完成：users=${counts.users} posts=${counts.posts} replies=${counts.replies}`);
