package com.app.budget.event;

import com.app.shared.event.*;
import com.app.transaction.domain.Category;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;
import java.math.BigDecimal;
import java.util.UUID;

@Component @RequiredArgsConstructor @Slf4j
public class BudgetEventPublisher {
    private final ApplicationEventPublisher eventPublisher;

    public void publishThresholdExceeded(UUID budgetId, UUID userId, Category category,
            BigDecimal limitAmount, BigDecimal spentAmount, double usagePct) {
        log.info("Publishing BudgetThresholdExceededEvent: userId={} category={} usage={}%", userId, category, usagePct);
        eventPublisher.publishEvent(new BudgetThresholdExceededEvent(budgetId, userId, category, limitAmount, spentAmount, usagePct));
    }

    public void publishBudgetExceeded(UUID budgetId, UUID userId, Category category,
            BigDecimal limitAmount, BigDecimal spentAmount) {
        log.warn("Publishing BudgetExceededEvent: userId={} category={} spent={}", userId, category, spentAmount);
        eventPublisher.publishEvent(new BudgetExceededEvent(budgetId, userId, category, limitAmount, spentAmount));
    }
}
