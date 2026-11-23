package com.huhuashizhe.schedule.model;

public class TokenPayload {
    public int v;
    /** 轮协令牌用：admin / member */
    public String role;
    /** 论坛账号令牌用：users.id，0 表示不是账号令牌 */
    public long uid;
    public long iat;
    public long exp;
}
