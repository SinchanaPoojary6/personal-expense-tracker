package com.app.user.dto;
import java.util.UUID;
public record AuthResponse(UUID userId, String email, String fullName,
        String role, String accessToken, String tokenType, long expiresIn) {
    public AuthResponse(UUID userId, String email, String fullName,
            String role, String accessToken, long expiresIn) {
        this(userId, email, fullName, role, accessToken, "Bearer", expiresIn);
    }
}
