package com.huhuashizhe.schedule.web;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.huhuashizhe.schedule.config.AppConfig;
import com.huhuashizhe.schedule.db.MessageRepository;
import com.huhuashizhe.schedule.db.ScheduleRepository;
import com.huhuashizhe.schedule.model.AuthRequest;
import com.huhuashizhe.schedule.model.AuthResponse;
import com.huhuashizhe.schedule.model.ConflictResponse;
import com.huhuashizhe.schedule.model.ErrorResponse;
import com.huhuashizhe.schedule.model.MemberRequest;
import com.huhuashizhe.schedule.model.Message;
import com.huhuashizhe.schedule.model.MessageRequest;
import com.huhuashizhe.schedule.model.Member;
import com.huhuashizhe.schedule.model.MessagesResponse;
import com.huhuashizhe.schedule.model.SubmitRequest;
import com.huhuashizhe.schedule.model.SubmitResponse;
import com.huhuashizhe.schedule.model.TokenPayload;
import com.huhuashizhe.schedule.service.BuildResult;
import com.huhuashizhe.schedule.service.RateLimiter;
import com.huhuashizhe.schedule.service.ScheduleValidator;
import com.huhuashizhe.schedule.service.TokenService;
import com.huhuashizhe.schedule.service.ValidatedPayload;
import com.huhuashizhe.schedule.service.ValidationException;

import javax.servlet.ServletConfig;
import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Driver;
import java.sql.DriverManager;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * 轮协 API：
 * POST /auth         {key} -> {token, role, expiresAt}
 * GET  /schedule     Bearer token -> {schedule, serverTime}
 * PUT  /schedule     admin Bearer token -> {schedule, changes, changedMemberIds, committedAt}
 * POST /verify       member Bearer token {memberId} -> 记录成员已验证
 * POST /presence     member Bearer token {memberId} -> 刷新在线心跳
 * GET  /health       健康检查
 */
@WebServlet(name = "scheduleApiServlet", urlPatterns = {"/*"}, loadOnStartup = 1)
public class ApiServlet extends HttpServlet {
    private static final Logger LOG = Logger.getLogger(ApiServlet.class.getName());
    private static final long MAX_BODY_BYTES = 1_000_000L;
    /** 最近 5 分钟内上报过心跳视为在线 */
    private static final long ONLINE_WINDOW_SECONDS = 300L;

    private final ObjectMapper mapper = Json.mapper();
    private transient AppConfig config;
    private transient ScheduleRepository repository;
    private transient MessageRepository messageRepository;
    private transient TokenService tokenService;
    private transient RateLimiter rateLimiter;

    @Override
    public void init(ServletConfig servletConfig) throws ServletException {
        super.init(servletConfig);
        try {
            config = AppConfig.load();
            repository = new ScheduleRepository(config.dbPath, config.backupDir);
            repository.initialize();
            messageRepository = new MessageRepository(config.dbPath);
            messageRepository.initialize();
            tokenService = new TokenService(config.tokenSecret);
            rateLimiter = new RateLimiter();
            LOG.info("轮协服务已启动；db=" + config.dbPath
                    + "；backup=" + config.backupDir
                    + "；config=" + (config.configPath == null ? "classpath" : config.configPath));
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "轮协服务启动失败", e);
            throw new ServletException("轮协服务启动失败: " + e.getMessage(), e);
        }
    }

    @Override
    public void destroy() {
        // Tomcat 热部署时注销 WebApp 类加载器注册的 JDBC 驱动，避免内存泄漏警告
        try {
            Enumeration<Driver> drivers = DriverManager.getDrivers();
            while (drivers.hasMoreElements()) {
                Driver driver = drivers.nextElement();
                if (driver.getClass().getClassLoader() == getClass().getClassLoader()) {
                    DriverManager.deregisterDriver(driver);
                }
            }
        } catch (Exception e) {
            LOG.log(Level.WARNING, "注销 JDBC 驱动失败", e);
        }
        super.destroy();
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
        if (path.isEmpty()) {
            path = "/";
        }
        if (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }

        try {
            if (("/".equals(path) || "/health".equals(path))
                    && "GET".equalsIgnoreCase(request.getMethod())) {
                health(response);
                return;
            }
            if ("/auth".equals(path) && "POST".equalsIgnoreCase(request.getMethod())) {
                auth(request, response);
                return;
            }
            if ("/verify".equals(path) && "POST".equalsIgnoreCase(request.getMethod())) {
                requireAuth(request);
                verifyMember(request, response);
                return;
            }
            if ("/presence".equals(path) && "POST".equalsIgnoreCase(request.getMethod())) {
                requireAuth(request);
                presence(request, response);
                return;
            }
            if ("/schedule".equals(path)) {
                TokenPayload token = requireAuth(request);
                if ("GET".equalsIgnoreCase(request.getMethod())) {
                    getSchedule(response);
                    return;
                }
                if ("PUT".equalsIgnoreCase(request.getMethod())) {
                    if (!"admin".equals(token.role)) {
                        throw new ApiException(403, "forbidden", "只有管理员可以修改轮协表");
                    }
                    submit(request, response);
                    return;
                }
                throw new ApiException(405, "method_not_allowed", "不支持的请求方法");
            }
            if ("/messages".equals(path)) {
                requireAuth(request);
                if ("GET".equalsIgnoreCase(request.getMethod())) {
                    listMessages(request, response);
                    return;
                }
                if ("POST".equalsIgnoreCase(request.getMethod())) {
                    createMessage(request, response);
                    return;
                }
                throw new ApiException(405, "method_not_allowed", "不支持的请求方法");
            }
            String[] segments = path.split("/");
            if (segments.length == 4 && "messages".equals(segments[1]) && "replies".equals(segments[3])) {
                requireAuth(request);
                if (!"POST".equalsIgnoreCase(request.getMethod())) {
                    throw new ApiException(405, "method_not_allowed", "不支持的请求方法");
                }
                createReply(segments[2], request, response);
                return;
            }
            if (segments.length == 3 && "messages".equals(segments[1])) {
                TokenPayload token = requireAuth(request);
                if (!"DELETE".equalsIgnoreCase(request.getMethod())) {
                    throw new ApiException(405, "method_not_allowed", "不支持的请求方法");
                }
                deleteMessage(segments[2], token, request, response);
                return;
            }
            if (segments.length == 3 && "replies".equals(segments[1])) {
                TokenPayload token = requireAuth(request);
                if (!"DELETE".equalsIgnoreCase(request.getMethod())) {
                    throw new ApiException(405, "method_not_allowed", "不支持的请求方法");
                }
                deleteReply(segments[2], token, request, response);
                return;
            }
            throw new ApiException(404, "not_found", "接口不存在");
        } catch (ConflictException e) {
            ConflictResponse body = new ConflictResponse();
            body.message = e.getMessage();
            body.currentRevision = e.current.revision;
            body.schedule = e.current.schedule;
            write(response, 409, body);
        } catch (ValidationException e) {
            write(response, 400, new ErrorResponse("invalid_request", e.getMessage()));
        } catch (ApiException e) {
            write(response, e.status, new ErrorResponse(e.code, e.getMessage()));
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "请求处理失败: " + request.getMethod() + " " + path, e);
            write(response, 500, new ErrorResponse("internal_error", "服务暂时不可用，请稍后再试"));
        }
    }

    private void health(HttpServletResponse response) throws IOException {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("ok", true);
        body.put("service", "huhuashizhe-schedule");
        body.put("schemaVersion", 1);
        body.put("time", Instant.now().toString());
        write(response, 200, body);
    }

    private void auth(HttpServletRequest request, HttpServletResponse response) throws IOException {
        AuthRequest body = readBody(request, AuthRequest.class);
        String key = body == null ? "" : trim(body.key);
        if (key.isEmpty()) {
            throw new ApiException(400, "bad_request", "请输入轮协密钥");
        }

        rateLimiter.cleanup();
        String ip = clientIp(request);
        if (!rateLimiter.allow(ip)) {
            throw new ApiException(429, "rate_limited", "尝试次数过多，请稍后再试");
        }

        String role;
        if (constantTimeEquals(key, config.adminKey)) {
            role = "admin";
        } else if (constantTimeEquals(key, config.scheduleKey)) {
            role = "member";
        } else {
            throw new ApiException(401, "invalid_key", "轮协密钥错误");
        }

        long ttl = "admin".equals(role)
                ? config.adminTokenTtlSeconds
                : config.memberTokenTtlSeconds;
        AuthResponse result = new AuthResponse();
        result.token = tokenService.issue(role, ttl);
        result.role = role;
        result.expiresAt = Instant.now().plusSeconds(ttl).toString();
        write(response, 200, result);
    }

    /** 姓名验证成功后记录成员已验证：之后该成员不再显示“未验证”。 */
    private void verifyMember(HttpServletRequest request, HttpServletResponse response) throws IOException {
        String memberId = readMemberId(request);
        try {
            String verifiedAt = repository.markVerified(memberId);
            if (verifiedAt == null) {
                throw new ApiException(404, "not_found", "成员不存在，请刷新轮协表");
            }
            repository.touchPresence(memberId, Instant.now());
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("memberId", memberId);
            body.put("verified", true);
            body.put("verifiedAt", verifiedAt);
            write(response, 200, body);
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            LOG.log(Level.WARNING, "记录成员验证状态失败: " + memberId, e);
            throw new ApiException(500, "verify_failed", "验证状态保存失败");
        }
    }

    /** App 前台定时上报在线心跳。 */
    private void presence(HttpServletRequest request, HttpServletResponse response) throws IOException {
        String memberId = readMemberId(request);
        try {
            if (repository.markVerified(memberId) == null) {
                throw new ApiException(404, "not_found", "成员不存在，请刷新轮协表");
            }
            Instant now = Instant.now();
            repository.touchPresence(memberId, now);
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("memberId", memberId);
            body.put("lastSeenAt", now.toString());
            body.put("online", true);
            write(response, 200, body);
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            LOG.log(Level.WARNING, "更新成员在线状态失败: " + memberId, e);
            throw new ApiException(500, "presence_failed", "在线状态更新失败");
        }
    }

    private String readMemberId(HttpServletRequest request) {
        MemberRequest body = readBody(request, MemberRequest.class);
        String memberId = body == null ? "" : trim(body.memberId);
        if (memberId.isEmpty()) {
            throw new ApiException(400, "bad_request", "缺少成员信息");
        }
        return memberId;
    }

    private void getSchedule(HttpServletResponse response) throws IOException {
        try {
            ScheduleRepository.Record record = repository.read();
            Map<String, String> presence = repository.readPresence();
            Instant now = Instant.now();
            List<Map<String, Object>> members = new ArrayList<>();
            for (Member member : record.schedule.members) {
                Map<String, Object> item = mapper.convertValue(
                        member, new TypeReference<Map<String, Object>>() {});
                String lastSeenAt = presence.get(member.id);
                item.put("lastSeenAt", lastSeenAt);
                item.put("online", isOnline(member, lastSeenAt, now));
                members.add(item);
            }
            Map<String, Object> schedule = mapper.convertValue(
                    record.schedule, new TypeReference<Map<String, Object>>() {});
            schedule.put("members", members);

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("schedule", schedule);
            body.put("serverTime", now.toString());
            write(response, 200, body);
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new ApiException(500, "read_failed", "轮协数据读取失败");
        }
    }

    private static boolean isOnline(Member member, String lastSeenAt, Instant now) {
        if (!Boolean.TRUE.equals(member.verified) || lastSeenAt == null || lastSeenAt.isEmpty()) {
            return false;
        }
        try {
            long seconds = Duration.between(Instant.parse(lastSeenAt), now).getSeconds();
            return seconds >= 0 && seconds <= ONLINE_WINDOW_SECONDS;
        } catch (Exception e) {
            return false;
        }
    }

    private void submit(HttpServletRequest request, HttpServletResponse response) throws IOException {
        SubmitRequest body = readBody(request, SubmitRequest.class);
        if (body == null) {
            throw new ApiException(400, "bad_request", "请求格式错误");
        }
        if (body.baseRevision == null) {
            throw new ApiException(400, "bad_request", "缺少 baseRevision，无法校验版本");
        }

        ValidatedPayload payload = ScheduleValidator.validate(body);
        try {
            ScheduleRepository.Record current = repository.read();
            if (current.revision != body.baseRevision) {
                throw new ConflictException(current, "轮协表已被其他设备更新，请刷新后再提交");
            }

            // 验证状态只由服务端产生，管理员提交时保留服务端现有状态
            Map<String, Member> verifiedLookup = new HashMap<>();
            for (Member member : current.schedule.members) {
                verifiedLookup.put(member.id.toLowerCase(Locale.ROOT), member);
            }
            for (Member member : payload.members) {
                Member existing = verifiedLookup.get(member.id.toLowerCase(Locale.ROOT));
                boolean verified = existing != null && Boolean.TRUE.equals(existing.verified);
                member.verified = verified;
                member.verifiedAt = verified ? existing.verifiedAt : null;
            }

            BuildResult built = ScheduleValidator.buildNext(current.schedule, payload, Instant.now());
            boolean written = repository.writeIfRevision(body.baseRevision, built.schedule);
            if (!written) {
                throw new ConflictException(repository.read(), "轮协表刚被其他人更新，请刷新后重试");
            }

            SubmitResponse result = new SubmitResponse();
            result.schedule = built.schedule;
            result.changes = built.diff.changes;
            result.changedMemberIds = built.diff.changedMemberIds;
            result.committedAt = built.schedule.updatedAt;
            write(response, 200, result);
        } catch (ConflictException e) {
            throw e;
        } catch (ValidationException e) {
            throw e;
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "轮协提交失败", e);
            throw new ApiException(500, "write_failed", "轮协提交失败，请稍后重试");
        }
    }

    private TokenPayload requireAuth(HttpServletRequest request) {
        String header = request.getHeader("Authorization");
        if (header == null || !header.regionMatches(true, 0, "Bearer ", 0, 7)) {
            throw new ApiException(401, "unauthorized", "登录已失效，请重新输入轮协密钥");
        }
        TokenPayload payload = tokenService.verify(header.substring(7).trim());
        if (payload == null) {
            throw new ApiException(401, "unauthorized", "登录已失效，请重新输入轮协密钥");
        }
        return payload;
    }

    private <T> T readBody(HttpServletRequest request, Class<T> type) {
        try {
            if (request.getContentLengthLong() > MAX_BODY_BYTES) {
                throw new ApiException(413, "payload_too_large", "请求内容过大");
            }
            return mapper.readValue(request.getInputStream(), type);
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            throw new ApiException(400, "bad_request", "请求格式错误");
        }
    }

    private void listMessages(HttpServletRequest request, HttpServletResponse response) throws IOException {
        try {
            writeMessages(response, messageRepository.list(request.getParameter("anonId")));
        } catch (ValidationException e) {
            throw e;
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "读取留言失败", e);
            throw new ApiException(500, "message_read_failed", "留言读取失败");
        }
    }

    private void createMessage(HttpServletRequest request, HttpServletResponse response) throws IOException {
        MessageRequest body = readBody(request, MessageRequest.class);
        if (body == null) {
            throw new ApiException(400, "bad_request", "请求格式错误");
        }
        try {
            messageRepository.createMessage(body.anonId, body.content);
            writeMessages(response, messageRepository.list(body.anonId));
        } catch (ValidationException e) {
            throw e;
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "发布留言失败", e);
            throw new ApiException(500, "message_write_failed", "留言发布失败");
        }
    }

    private void createReply(String messageId, HttpServletRequest request, HttpServletResponse response)
            throws IOException {
        MessageRequest body = readBody(request, MessageRequest.class);
        if (body == null) {
            throw new ApiException(400, "bad_request", "请求格式错误");
        }
        try {
            messageRepository.createReply(messageId, body.anonId, body.content);
            writeMessages(response, messageRepository.list(body.anonId));
        } catch (ValidationException e) {
            throw e;
        } catch (NoSuchElementException e) {
            throw new ApiException(404, "not_found", e.getMessage());
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "回复留言失败", e);
            throw new ApiException(500, "message_write_failed", "回复发布失败");
        }
    }

    private void deleteMessage(String messageId, TokenPayload token, HttpServletRequest request,
            HttpServletResponse response) throws IOException {
        String anonId = request.getParameter("anonId");
        try {
            messageRepository.deleteMessage(messageId, anonId, "admin".equals(token.role));
            writeMessages(response, messageRepository.list(anonId));
        } catch (NoSuchElementException e) {
            throw new ApiException(404, "not_found", e.getMessage());
        } catch (SecurityException e) {
            throw new ApiException(403, "forbidden", e.getMessage());
        } catch (ValidationException e) {
            throw e;
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "删除留言失败", e);
            throw new ApiException(500, "message_delete_failed", "留言删除失败");
        }
    }

    private void deleteReply(String replyId, TokenPayload token, HttpServletRequest request,
            HttpServletResponse response) throws IOException {
        String anonId = request.getParameter("anonId");
        try {
            messageRepository.deleteReply(replyId, anonId, "admin".equals(token.role));
            writeMessages(response, messageRepository.list(anonId));
        } catch (NoSuchElementException e) {
            throw new ApiException(404, "not_found", e.getMessage());
        } catch (SecurityException e) {
            throw new ApiException(403, "forbidden", e.getMessage());
        } catch (ValidationException e) {
            throw e;
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "删除回复失败", e);
            throw new ApiException(500, "message_delete_failed", "回复删除失败");
        }
    }

    private void writeMessages(HttpServletResponse response, List<Message> messages) throws IOException {
        MessagesResponse body = new MessagesResponse();
        body.messages = messages;
        write(response, 200, body);
    }

    private void write(HttpServletResponse response, int status, Object body) throws IOException {
        response.setStatus(status);
        response.setContentType("application/json;charset=UTF-8");
        response.setCharacterEncoding("UTF-8");
        mapper.writeValue(response.getWriter(), body);
    }

    private void setCommonHeaders(HttpServletResponse response) {
        response.setHeader("Access-Control-Allow-Origin", "*");
        response.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
        response.setHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
        response.setHeader("Access-Control-Max-Age", "86400");
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Content-Type-Options", "nosniff");
    }

    private String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.trim().isEmpty()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }

    private static boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) {
            return false;
        }
        return MessageDigest.isEqual(
                a.getBytes(StandardCharsets.UTF_8),
                b.getBytes(StandardCharsets.UTF_8));
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }

    private static class ApiException extends RuntimeException {
        private final int status;
        private final String code;

        private ApiException(int status, String code, String message) {
            super(message);
            this.status = status;
            this.code = code;
        }
    }

    private static class ConflictException extends RuntimeException {
        private final ScheduleRepository.Record current;

        private ConflictException(ScheduleRepository.Record current, String message) {
            super(message);
            this.current = current;
        }
    }
}
