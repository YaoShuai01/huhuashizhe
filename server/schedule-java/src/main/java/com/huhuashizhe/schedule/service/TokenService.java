package com.huhuashizhe.schedule.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.huhuashizhe.schedule.model.TokenPayload;
import com.huhuashizhe.schedule.web.Json;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;

public class TokenService {
    private static final String HMAC_ALGORITHM = "HmacSHA256";

    private final byte[] secret;
    private final ObjectMapper mapper = Json.mapper();

    public TokenService(String secret) {
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
    }

    public String issue(String role, long ttlSeconds) {
        try {
            long now = Instant.now().getEpochSecond();
            TokenPayload payload = new TokenPayload();
            payload.v = 1;
            payload.role = role;
            payload.iat = now;
            payload.exp = now + ttlSeconds;
            String body = Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(mapper.writeValueAsBytes(payload));
            return body + "." + sign(body);
        } catch (Exception e) {
            throw new IllegalStateException("签发排班 token 失败", e);
        }
    }

    public TokenPayload verify(String token) {
        if (token == null) {
            return null;
        }
        try {
            String[] parts = token.split("\\.");
            if (parts.length != 2) {
                return null;
            }
            String expected = sign(parts[0]);
            if (!MessageDigest.isEqual(
                    expected.getBytes(StandardCharsets.UTF_8),
                    parts[1].getBytes(StandardCharsets.UTF_8))) {
                return null;
            }
            byte[] decoded = Base64.getUrlDecoder().decode(parts[0]);
            TokenPayload payload = mapper.readValue(decoded, TokenPayload.class);
            if (payload.v != 1) {
                return null;
            }
            // 轮协令牌带 role，论坛账号令牌带 uid；两者都不具备则视为伪造
            boolean roleToken = "admin".equals(payload.role) || "member".equals(payload.role);
            boolean accountToken = payload.uid > 0;
            if (!roleToken && !accountToken) {
                return null;
            }
            if (payload.exp <= Instant.now().getEpochSecond()) {
                return null;
            }
            return payload;
        } catch (Exception e) {
            return null;
        }
    }

    private String sign(String body) throws Exception {
        Mac mac = Mac.getInstance(HMAC_ALGORITHM);
        mac.init(new SecretKeySpec(secret, HMAC_ALGORITHM));
        byte[] signature = mac.doFinal(body.getBytes(StandardCharsets.UTF_8));
        return Base64.getUrlEncoder().withoutPadding().encodeToString(signature);
    }
}
