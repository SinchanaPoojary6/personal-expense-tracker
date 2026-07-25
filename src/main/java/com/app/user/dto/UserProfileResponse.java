package com.app.user.dto;
import com.app.user.domain.User;
import java.time.Instant;
import java.util.UUID;
public record UserProfileResponse(UUID id, String email, String fullName,
        String role, boolean emailVerified, Instant createdAt) {
    public static UserProfileResponse from(User u) {
        return new UserProfileResponse(u.getId(), u.getEmail(), u.getFullName(),
                u.getRole().name(), u.isEmailVerified(), u.getCreatedAt());
    }
}
