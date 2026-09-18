package com.app.budget.listener;

import com.app.budget.service.BudgetAnalysisService;
import com.app.shared.event.TransactionCreatedEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.retry.annotation.*;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.*;

@Component @RequiredArgsConstructor @Slf4j
public class TransactionEventListener {
    private final BudgetAnalysisService budgetAnalysisService;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Async
    @Retryable(maxAttempts = 3, backoff = @Backoff(delay = 1000, multiplier = 2))
    public void onTransactionCreated(TransactionCreatedEvent event) {
        log.info("Budget analysis triggered: txId={}", event.transactionId());
        try { budgetAnalysisService.analyzeAndPublish(event); }
        catch (Exception e) { log.error("Budget analysis failed", e); throw e; }
    }
}
