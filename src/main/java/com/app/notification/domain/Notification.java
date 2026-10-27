package com.app.notification.domain;

import jakarta.persistence.*;
import lombok.*;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name = "notifications", schema = "ntf")
@EntityListeners(AuditingEntityListener.class)
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Notification {
    @Id @GeneratedValue(strategy = GenerationType.UUID) private UUID id;
    @Column(name = "user_id", nullable = false) private UUID userId;
    @Enumerated(EnumType.STRING) @Column(nullable = false) private NotificationType type;
    @Column(nullable = false) private String title;
    @Column(nullable = false) private String message;
    @Column(name = "is_read") @Builder.Default private boolean read = false;
    @Column(name = "read_at") private Instant readAt;
    @CreatedDate @Column(name = "created_at", nullable = false, updatable = false) private Instant createdAt;
}
