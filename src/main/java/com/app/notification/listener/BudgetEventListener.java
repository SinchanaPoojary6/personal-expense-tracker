package com.app.notification.listener;

import com.app.notification.domain.NotificationType;
import com.app.notification.service.NotificationService;
import com.app.shared.event.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.retry.annotation.*;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.*;

@Component @RequiredArgsConstructor @Slf4j
public class BudgetEventListener {
    private final NotificationService notificationService;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Async @Retryable(maxAttempts = 3, backoff = @Backoff(delay = 500, multiplier = 2))
    public void onThresholdExceeded(BudgetThresholdExceededEvent event) {
        String cat = event.category() != null ? event.category().name() : "Overall";
        String title = "Budget Alert: " + cat;
        String msg = String.format("Warning: You've used %.1f%% of your %s budget (%.2f / %.2f)",
                event.usagePct(), cat, event.spentAmount(), event.limitAmount());
        notificationService.createAlert(event.userId(), title, msg, NotificationType.BUDGET_ALERT);
        log.info("[EMAIL-SIM] Threshold alert sent userId={} category={}", event.userId(), event.category());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Async @Retryable(maxAttempts = 3, backoff = @Backoff(delay = 500, multiplier = 2))
    public void onBudgetExceeded(BudgetExceededEvent event) {
        String cat = event.category() != null ? event.category().name() : "Overall";
        String title = "Budget Exceeded: " + cat;
        String msg = String.format("Budget EXCEEDED for %s! Spent %.2f of %.2f limit.",
                cat, event.spentAmount(), event.limitAmount());
        notificationService.createAlert(event.userId(), title, msg, NotificationType.EXCEEDED);
        log.warn("[EMAIL-SIM] Exceeded alert sent userId={} category={}", event.userId(), event.category());
    }
}
