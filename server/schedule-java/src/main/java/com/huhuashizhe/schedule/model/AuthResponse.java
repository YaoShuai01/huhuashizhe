package com.huhuashizhe.schedule.model;

public class AuthResponse {
    public String token;
    public String role;
    public String expiresAt;
    /** 使用成员专属密钥登录时返回对应成员 ID */
    public String memberId;
}
