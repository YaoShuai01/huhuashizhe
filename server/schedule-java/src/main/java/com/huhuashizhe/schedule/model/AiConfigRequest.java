package com.huhuashizhe.schedule.model;

/** 管理页提交的 AI 配置；apiKey 留空表示保持原 Key 不变。 */
public class AiConfigRequest {
    public String apiKey;
    public String baseUrl;
    public String model;
}
