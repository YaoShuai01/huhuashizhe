// 论坛管理员账号 ID：可删除任意帖子与评论
// 12554357 / 小苗 对应的 users.id 为 8
export const ADMIN_USER_IDS = new Set([8]);

export function isAdminUserId(userId) {
  return ADMIN_USER_IDS.has(Number(userId));
}
