package com.huhuashizhe.schedule.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public class Reply {
    public String id;
    public String content;
    public String createdAt;

    @JsonProperty("isMine")
    public boolean isMine;
}
