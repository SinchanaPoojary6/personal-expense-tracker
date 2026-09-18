package com.app.budget.dto;
import com.app.transaction.domain.Category;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
public record BudgetRequest(
        Category category,
        @NotNull @Positive @Digits(integer = 13, fraction = 2) BigDecimal limitAmount,
        @NotNull @Min(1) @Max(12) Integer month,
        @NotNull @Min(2000) Integer year,
        @DecimalMin("1.0") @DecimalMax("99.99") BigDecimal alertThresholdPct) {}
