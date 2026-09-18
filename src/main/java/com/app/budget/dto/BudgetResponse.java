package com.app.budget.dto;
import com.app.budget.domain.Budget;
import com.app.transaction.domain.Category;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.UUID;
public record BudgetResponse(UUID id, Category category, BigDecimal limitAmount,
        int month, int year, BigDecimal alertThresholdPct,
        BigDecimal spentAmount, BigDecimal remainingAmount,
        double usagePct, BudgetStatus status) {
    public enum BudgetStatus { SAFE, APPROACHING, EXCEEDED }
    public static BudgetResponse from(Budget b, BigDecimal spent) {
        double pct = spent.divide(b.getLimitAmount(), 4, RoundingMode.HALF_UP).doubleValue() * 100;
        BudgetStatus status = pct >= 100 ? BudgetStatus.EXCEEDED
                : pct >= b.getAlertThresholdPct().doubleValue() ? BudgetStatus.APPROACHING
                : BudgetStatus.SAFE;
        return new BudgetResponse(b.getId(), b.getCategory(), b.getLimitAmount(),
                b.getMonth(), b.getYear(), b.getAlertThresholdPct(),
                spent, b.getLimitAmount().subtract(spent),
                Math.round(pct * 10.0) / 10.0, status);
    }
}
