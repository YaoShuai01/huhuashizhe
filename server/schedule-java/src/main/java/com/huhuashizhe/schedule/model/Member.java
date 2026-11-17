package com.huhuashizhe.schedule.model;

public class Member {
    public String id;
    public String name;
    public Boolean active = Boolean.TRUE;
    /** 成员编号，按加入顺序分配，用于“X号成员” */
    public Integer seq;
    /** 是否已通过身份验证（成员首次用专属密钥登录时由服务端写入） */
    public Boolean verified = Boolean.FALSE;
    /** 首次验证时间 */
    public String verifiedAt;

    public Member() {
    }

    public Member(String id, String name, Boolean active) {
        this(id, name, active, null);
    }

    public Member(String id, String name, Boolean active, Integer seq) {
        this.id = id;
        this.name = name;
        this.active = active == null ? Boolean.TRUE : active;
        this.seq = seq;
    }
}
