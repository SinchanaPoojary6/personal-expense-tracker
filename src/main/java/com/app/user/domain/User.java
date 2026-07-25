package com.app.user.domain;

import com.app.shared.util.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name = "users", schema = "usr")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class User extends BaseEntity {
    @Id @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;
    @Column(unique = true, nullable = false) private String email;
    @Column(name = "password_hash", nullable = false) private String passwordHash;
    @Column(name = "full_name", nullable = false) private String fullName;
    @Enumerated(EnumType.STRING) @Column(nullable = false) @Builder.Default
    private Role role = Role.USER;
    @Column(name = "email_verified") @Builder.Default private boolean emailVerified = false;
    @Column(name = "is_active") @Builder.Default private boolean isActive = true;
    @Column(name = "last_login_at") private Instant lastLoginAt;
    @Column(name = "deleted_at") private Instant deletedAt;
}
