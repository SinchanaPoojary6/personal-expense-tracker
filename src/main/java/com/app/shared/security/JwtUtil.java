package com.app.shared.security;

import io.jsonwebtoken.*;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import javax.crypto.SecretKey;
import java.util.Date;
import java.util.UUID;

@Component @Slf4j
public class JwtUtil {
    @Value("${jwt.secret}") private String secret;
    @Value("${jwt.expiry-ms}") private long expiryMs;

    public String generate(UUID userId, String role) {
        return Jwts.builder().subject(userId.toString()).claim("role", role)
                .issuedAt(new Date()).expiration(new Date(System.currentTimeMillis() + expiryMs))
                .signWith(getKey(), Jwts.SIG.HS256).compact();
    }

    public Claims validate(String token) {
        return Jwts.parser().verifyWith(getKey()).build().parseSignedClaims(token).getPayload();
    }

    public boolean isValid(String token) {
        try { validate(token); return true; }
        catch (Exception e) { log.debug("JWT invalid: {}", e.getMessage()); return false; }
    }

    public long getExpiryMs() { return expiryMs; }
    private SecretKey getKey() { return Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret)); }
}
