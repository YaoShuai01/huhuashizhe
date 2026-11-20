package com.huhuashizhe.schedule.config;

/**
 * 运行期 AI 配置。
 *
 * Key、服务地址与模型只保存在服务器配置文件中；管理页修改后立即更新这里，
 * AI 代理无需重启 Tomcat 即可生效。
 */
public final class AiRuntimeConfig {
    private static final String DEFAULT_BASE_URL = "https://maas.qianwenaiapi.com/compatible-mode/v1";
    private static final String DEFAULT_MODEL = "qwen3.8-flash";

    private static volatile String apiKey = "";
    private static volatile String baseUrl = DEFAULT_BASE_URL;
    private static volatile String model = DEFAULT_MODEL;

    private AiRuntimeConfig() {
    }

    public static synchronized void init(AppConfig config) {
        if (config == null) {
            return;
        }
        apiKey = trim(config.aiApiKey);
        baseUrl = normalizeBase(trim(config.aiBaseUrl));
        String configuredModel = trim(config.aiModel);
        model = configuredModel.isEmpty() ? DEFAULT_MODEL : configuredModel;
    }

    public static String apiKey() {
        return apiKey;
    }

    public static String baseUrl() {
        return baseUrl;
    }

    public static String model() {
        return model;
    }

    public static synchronized void update(String newKey, String newBaseUrl, String newModel) {
        if (newKey != null) {
            apiKey = trim(newKey);
        }
        String base = trim(newBaseUrl);
        if (!base.isEmpty()) {
            baseUrl = normalizeBase(base);
        }
        String modelValue = trim(newModel);
        if (!modelValue.isEmpty()) {
            model = modelValue;
        }
    }

    /** 只返回掩码，绝不把完整 Key 发送到浏览器。 */
    public static String maskedKey() {
        String key = apiKey;
        if (key.isEmpty()) {
            return "";
        }
        if (key.length() <= 8) {
            return "****";
        }
        return key.substring(0, 3) + "****" + key.substring(key.length() - 4);
    }

    private static String normalizeBase(String value) {
        String result = value == null ? "" : value.trim();
        while (result.endsWith("/")) {
            result = result.substring(0, result.length() - 1);
        }
        return result.isEmpty() ? DEFAULT_BASE_URL : result;
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }
}
