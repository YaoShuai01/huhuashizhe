package com.huhuashizhe.schedule.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.huhuashizhe.schedule.config.AiRuntimeConfig;
import com.huhuashizhe.schedule.config.AppConfig;
import com.huhuashizhe.schedule.model.TokenPayload;
import com.huhuashizhe.schedule.service.AiQuota;
import com.huhuashizhe.schedule.service.TokenService;

import javax.servlet.ServletConfig;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * AI 代理：/ai/chat
 *
 * App 不再内置任何大模型 API Key，统一由本服务转发到千问AI平台。
 * Key 只保存在服务器配置 ai.api.key 中，并配套单 IP / 全局每日限频。
 *
 * 请求体（OpenAI 兼容子集）：
 * {"messages":[{role,content}...],"max_tokens":1024,"temperature":0.7,"top_p":0.95,"stream":true}
 */
@WebServlet(name = "aiProxyServlet", urlPatterns = {"/ai/*"}, loadOnStartup = 1)
public class AiProxyServlet extends HttpServlet {
    private static final Logger LOG = Logger.getLogger(AiProxyServlet.class.getName());
    private static final ObjectMapper MAPPER = Json.mapper();

    private static final int MAX_BODY_BYTES = 64 * 1024;
    private static final int MAX_MESSAGES = 41;
    private static final int MAX_MESSAGE_CHARS = 4000;
    private static final int MAX_TOTAL_CHARS = 20000;
    private static final int MAX_OUTPUT_TOKENS = 1024;
    private static final int MAX_NON_STREAM_BYTES = 1_000_000;
    private static final int UPSTREAM_TIMEOUT_MS = 90_000;

    private transient AppConfig config;
    private transient AiQuota quota;
    private transient TokenService tokenService;

    @Override
    public void init(ServletConfig servletConfig) throws ServletException {
        super.init(servletConfig);
        try {
            config = AppConfig.load();
            AiRuntimeConfig.init(config);
            quota = new AiQuota();
            tokenService = new TokenService(config.tokenSecret);
            LOG.info("AI 代理已启动；base=" + AiRuntimeConfig.baseUrl()
                    + "；model=" + AiRuntimeConfig.model()
                    + "；keyConfigured=" + !AiRuntimeConfig.apiKey().isEmpty());
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "AI 代理启动失败", e);
            throw new ServletException("AI 代理启动失败: " + e.getMessage(), e);
        }
    }

    @Override
    protected void service(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        setCommonHeaders(response);
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            response.setStatus(HttpServletResponse.SC_NO_CONTENT);
            return;
        }

        String path = request.getRequestURI().substring(request.getContextPath().length());
        if (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        if (!"/ai/chat".equals(path)) {
            writeError(response, 404, "not_found", "接口不存在");
            return;
        }
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            writeError(response, 405, "method_not_allowed", "不支持的请求方法");
            return;
        }
        if (AiRuntimeConfig.apiKey().isEmpty()) {
            writeError(response, 503, "ai_not_configured", "AI 服务尚未配置");
            return;
        }

        // 必须登录（论坛账号令牌或轮协令牌均可），否则任何人都能白嫖 AI 额度
        if (!isAuthorized(request)) {
            writeError(response, 401, "unauthorized", "请先登录后再使用 AI 助手");
            return;
        }

        String ip = clientIp(request);
        if (!quota.allow(ip)) {
            LOG.warning("[AI] 触发限流 ip=" + ip);
            writeError(response, 429, "too_many_requests", "AI 调用过于频繁，请稍后再试");
            return;
        }

        try {
            Map<String, Object> payload = readPayload(request);
            List<Map<String, Object>> messages = parseMessages(payload);
            int totalChars = 0;
            for (Map<String, Object> message : messages) {
                totalChars += ((String) message.get("content")).length();
            }
            boolean stream = !(payload.get("stream") instanceof Boolean)
                    || (Boolean) payload.get("stream");
            int maxTokens = intValue(payload.get("max_tokens"), MAX_OUTPUT_TOKENS, 1, MAX_OUTPUT_TOKENS);
            double temperature = doubleValue(payload.get("temperature"), 0.7, 0.0, 2.0);
            double topP = doubleValue(payload.get("top_p"), 0.95, 0.01, 1.0);

            Map<String, Object> upstream = new LinkedHashMap<>();
            upstream.put("model", AiRuntimeConfig.model());
            upstream.put("messages", messages);
            upstream.put("max_tokens", maxTokens);
            upstream.put("temperature", temperature);
            upstream.put("top_p", topP);
            // 千问支持关闭思考模式；小米 MiMo 接口不保证接受该参数，切到小米时不传
            if (!AiRuntimeConfig.baseUrl().contains("xiaomimimo")) {
                upstream.put("enable_thinking", false);
            }
            upstream.put("stream", stream);

            forward(upstream, stream, ip, messages.size(), totalChars, response);
        } catch (BadRequestException e) {
            writeError(response, 400, "invalid_request", e.getMessage());
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "[AI] 请求处理失败 ip=" + ip, e);
            writeError(response, 500, "internal_error", "服务暂时不可用，请稍后再试");
        }
    }

    /** 校验 Bearer 令牌：论坛账号令牌（uid）或轮协令牌（role）都放行。 */
    private boolean isAuthorized(HttpServletRequest request) {
        String header = request.getHeader("Authorization");
        if (header == null || !header.regionMatches(true, 0, "Bearer ", 0, 7)) {
            return false;
        }
        TokenPayload payload = tokenService.verify(header.substring(7).trim());
        if (payload == null) {
            return false;
        }
        return payload.uid > 0
                || "admin".equals(payload.role)
                || "member".equals(payload.role);
    }

    private void forward(Map<String, Object> upstream, boolean stream, String ip,
            int messageCount, int totalChars, HttpServletResponse response) throws IOException {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(AiRuntimeConfig.baseUrl() + "/chat/completions");
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("POST");
            connection.setDoOutput(true);
            connection.setConnectTimeout(10_000);
            connection.setReadTimeout(UPSTREAM_TIMEOUT_MS);
            connection.setRequestProperty("Authorization", "Bearer " + AiRuntimeConfig.apiKey());
            connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            connection.setRequestProperty("Accept", stream ? "text/event-stream" : "application/json");
            connection.setRequestProperty("Accept-Encoding", "identity");

            byte[] body = MAPPER.writeValueAsBytes(upstream);
            connection.setFixedLengthStreamingMode(body.length);
            try (OutputStream out = connection.getOutputStream()) {
                out.write(body);
            }

            int status = connection.getResponseCode();
            LOG.info("[AI] ip=" + ip + " msgs=" + messageCount + " chars=" + totalChars
                    + " stream=" + stream + " upstream=" + status);

            if (status != HttpURLConnection.HTTP_OK) {
                drain(connection.getErrorStream(), 2048);
                writeError(response, 502, "ai_upstream_error", "AI 服务暂时不可用，请稍后再试");
                return;
            }

            if (stream) {
                response.setStatus(200);
                response.setContentType("text/event-stream;charset=UTF-8");
                response.setHeader("Cache-Control", "no-cache");
                response.setHeader("X-Accel-Buffering", "no");
                try (InputStream in = connection.getInputStream();
                        OutputStream out = response.getOutputStream()) {
                    byte[] buffer = new byte[4096];
                    int read;
                    while ((read = in.read(buffer)) >= 0) {
                        if (read == 0) {
                            continue;
                        }
                        out.write(buffer, 0, read);
                        out.flush();
                    }
                }
            } else {
                byte[] data;
                try (InputStream in = connection.getInputStream()) {
                    data = readLimited(in, MAX_NON_STREAM_BYTES);
                }
                response.setStatus(200);
                response.setContentType("application/json;charset=UTF-8");
                response.setContentLength(data.length);
                response.getOutputStream().write(data);
            }
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    private Map<String, Object> readPayload(HttpServletRequest request) throws IOException {
        long declared = request.getContentLengthLong();
        if (declared > MAX_BODY_BYTES) {
            throw new BadRequestException("请求内容过大");
        }
        byte[] raw;
        try (InputStream in = request.getInputStream()) {
            raw = readLimited(in, MAX_BODY_BYTES);
        }
        if (raw.length == 0) {
            throw new BadRequestException("请求内容为空");
        }
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> payload = MAPPER.readValue(raw, Map.class);
            return payload;
        } catch (Exception e) {
            throw new BadRequestException("请求格式不正确");
        }
    }

    private List<Map<String, Object>> parseMessages(Map<String, Object> payload) {
        Object raw = payload.get("messages");
        if (!(raw instanceof List)) {
            throw new BadRequestException("缺少 messages");
        }
        List<?> list = (List<?>) raw;
        if (list.isEmpty() || list.size() > MAX_MESSAGES) {
            throw new BadRequestException("对话消息数量不合法");
        }
        List<Map<String, Object>> result = new ArrayList<>();
        int totalChars = 0;
        for (Object item : list) {
            if (!(item instanceof Map)) {
                throw new BadRequestException("消息格式不正确");
            }
            Map<?, ?> source = (Map<?, ?>) item;
            Object roleValue = source.get("role");
            Object contentValue = source.get("content");
            if (!(roleValue instanceof String) || !(contentValue instanceof String)) {
                throw new BadRequestException("消息格式不正确");
            }
            String role = (String) roleValue;
            String content = (String) contentValue;
            if (!"system".equals(role) && !"user".equals(role) && !"assistant".equals(role)) {
                throw new BadRequestException("不支持的消息角色");
            }
            if (content.length() > MAX_MESSAGE_CHARS) {
                throw new BadRequestException("单条消息过长");
            }
            totalChars += content.length();
            if (totalChars > MAX_TOTAL_CHARS) {
                throw new BadRequestException("对话内容过长");
            }
            Map<String, Object> message = new LinkedHashMap<>();
            message.put("role", role);
            message.put("content", content);
            result.add(message);
        }
        return result;
    }

    private static int intValue(Object value, int fallback, int min, int max) {
        int parsed = fallback;
        if (value instanceof Number) {
            parsed = ((Number) value).intValue();
        }
        return Math.max(min, Math.min(max, parsed));
    }

    private static double doubleValue(Object value, double fallback, double min, double max) {
        double parsed = fallback;
        if (value instanceof Number) {
            parsed = ((Number) value).doubleValue();
        }
        return Math.max(min, Math.min(max, parsed));
    }

    private static byte[] readLimited(InputStream in, int limit) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        byte[] chunk = new byte[4096];
        int read;
        while ((read = in.read(chunk)) >= 0) {
            if (read == 0) {
                continue;
            }
            if (buffer.size() + read > limit) {
                throw new IOException("内容超过限制");
            }
            buffer.write(chunk, 0, read);
        }
        return buffer.toByteArray();
    }

    private static void drain(InputStream in, int limit) {
        if (in == null) {
            return;
        }
        try (InputStream stream = in) {
            readLimited(stream, limit);
        } catch (IOException ignored) {
            // 忽略上游错误流读取失败
        }
    }

    private void writeError(HttpServletResponse response, int status, String code, String message)
            throws IOException {
        response.setStatus(status);
        response.setContentType("application/json;charset=UTF-8");
        response.setCharacterEncoding("UTF-8");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("code", code);
        body.put("message", message);
        MAPPER.writeValue(response.getWriter(), body);
    }

    private void setCommonHeaders(HttpServletResponse response) {
        response.setHeader("Access-Control-Allow-Origin", "*");
        response.setHeader("Access-Control-Allow-Methods", "POST,OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type");
        response.setHeader("Access-Control-Max-Age", "86400");
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Content-Type-Options", "nosniff");
    }

    /** 直连用户取 remoteAddr；经本机反向代理时取 X-Forwarded-For，避免所有请求共用 127.0.0.1 配额。 */
    private String clientIp(HttpServletRequest request) {
        String remote = request.getRemoteAddr();
        boolean local = "127.0.0.1".equals(remote) || "0:0:0:0:0:0:0:1".equals(remote);
        if (local) {
            String forwarded = request.getHeader("X-Forwarded-For");
            if (forwarded != null && !forwarded.trim().isEmpty()) {
                return forwarded.split(",")[0].trim();
            }
        }
        return remote;
    }

    private static final class BadRequestException extends RuntimeException {
        private BadRequestException(String message) {
            super(message);
        }
    }
}
