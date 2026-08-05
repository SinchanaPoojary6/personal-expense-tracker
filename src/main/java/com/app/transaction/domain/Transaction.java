package com.app.transaction.domain;

import com.app.shared.util.BaseEntity;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.Instant;
import java.util.UUID;

@Entity @Table(name = "transactions", schema = "txn")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Transaction extends BaseEntity {
    @Id @GeneratedValue(strategy = GenerationType.UUID) private UUID id;
    @Column(name = "user_id", nullable = false) private UUID userId;
    @Column(nullable = false, precision = 15, scale = 2) private BigDecimal amount;
    @Enumerated(EnumType.STRING) @Column(nullable = false) private TransactionType type;
    @Enumerated(EnumType.STRING) @Column(name = "category_code", nullable = false) private Category category;
    private String description;
    @Column(name = "transaction_date", nullable = false) private LocalDate transactionDate;
    @Column(name = "idempotency_key", unique = true) private String idempotencyKey;
    @Column(name = "deleted_at") private Instant deletedAt;
}
