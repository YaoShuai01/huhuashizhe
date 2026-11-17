package com.huhuashizhe.schedule.service;

import com.huhuashizhe.schedule.model.TokenPayload;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

class TokenServiceTest {
    private final TokenService service =
            new TokenService("0123456789abcdef0123456789abcdef");

    @Test
    void issuesAndVerifiesMemberToken() {
        String token = service.issue("member", 3600);
        TokenPayload payload = service.verify(token);
        assertNotNull(payload);
        assertEquals("member", payload.role);
    }

    @Test
    void rejectsTamperedAndExpiredTokens() {
        String token = service.issue("admin", 3600);
        assertNull(service.verify(token + "x"));
        assertNull(service.verify(token.replace('.', '-')));
        assertNull(service.verify(null));
        assertNull(service.verify(service.issue("admin", -1)));
    }
}
