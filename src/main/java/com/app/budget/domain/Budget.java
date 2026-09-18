package com.app.budget.domain;

import com.app.shared.util.BaseEntity;
import com.app.transaction.domain.Category;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.util.UUID;

@Entity @Table(name = "budgets", schema = "bgt")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Budget extends BaseEntity {
    @Id @GeneratedValue(strategy = GenerationType.UUID) private UUID id;
    @Column(name = "user_id", nullable = false) private UUID userId;
    @Enumerated(EnumType.STRING) @Column(name = "category_code") private Category category;
    @Column(name = "limit_amount", nullable = false, precision = 15, scale = 2) private BigDecimal limitAmount;
    @Column(nullable = false) private int month;
    @Column(nullable = false) private int year;
    @Column(name = "alert_threshold_pct", nullable = false, precision = 5, scale = 2)
    @Builder.Default private BigDecimal alertThresholdPct = new BigDecimal("80.0");
    @Version private long version;
}
