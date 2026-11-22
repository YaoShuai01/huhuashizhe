import mysql from 'mysql2/promise';

/// 数据库连接配置，可用环境变量覆盖
export const dbConfig = {
  host: process.env.DB_HOST ?? '127.0.0.1',
  port: Number(process.env.DB_PORT ?? 3306),
  user: process.env.DB_USER ?? 'hhsz_app',
  password: process.env.DB_PASSWORD ?? '',
  database: process.env.DB_NAME ?? 'huhuashizhe',
  charset: 'utf8mb4',
  connectionLimit: 10,
  dateStrings: true,
  supportBigNumbers: true,
};

/// 全局连接池，接口统一从这里取连接
export const pool = mysql.createPool(dbConfig);
