package com.app.shared.event;

import com.app.transaction.domain.Category;
import java.math.BigDecimal;
import java.util.UUID;

public record BudgetThresholdExceededEvent(
        UUID budgetId, UUID userId, Category category,
        BigDecimal limitAmount, BigDecimal spentAmount, double usagePct) {}
