package com.huhuashizhe.schedule.model;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.ArrayList;
import java.util.List;

public class Message {
    public String id;
    public String content;
    public String createdAt;

    @JsonProperty("isMine")
    public boolean isMine;

    public List<Reply> replies = new ArrayList<>();
}
