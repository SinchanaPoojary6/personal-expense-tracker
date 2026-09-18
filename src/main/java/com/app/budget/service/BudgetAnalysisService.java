package com.app.budget.service;

import com.app.budget.event.BudgetEventPublisher;
import com.app.budget.repository.BudgetRepository;
import com.app.shared.event.TransactionCreatedEvent;
import com.app.transaction.domain.TransactionType;
import com.app.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import java.math.BigDecimal;
import java.math.RoundingMode;

@Service @RequiredArgsConstructor @Slf4j
public class BudgetAnalysisService {
    private final BudgetRepository budgetRepository;
    private final TransactionRepository transactionRepository;
    private final BudgetEventPublisher budgetEventPublisher;

    public void analyzeAndPublish(TransactionCreatedEvent event) {
        if (event.type() == TransactionType.INCOME) return;
        var budgets = budgetRepository.findApplicableBudgets(event.userId(),
                event.category(), event.transactionDate().getMonthValue(), event.transactionDate().getYear());
        if (budgets.isEmpty()) return;

        for (var budget : budgets) {
            String catStr = budget.getCategory() != null ? budget.getCategory().name() : null;
            BigDecimal spent = transactionRepository.sumExpensesByUserCategoryAndPeriod(
                    event.userId(), catStr, event.transactionDate().getMonthValue(), event.transactionDate().getYear());
            if (spent == null) spent = BigDecimal.ZERO;

            double pct = spent.divide(budget.getLimitAmount(), 4, RoundingMode.HALF_UP).doubleValue() * 100;
            log.debug("Budget check: userId={} category={} pct={}%", event.userId(), budget.getCategory(), pct);

            if (pct >= 100.0)
                budgetEventPublisher.publishBudgetExceeded(budget.getId(), event.userId(),
                        budget.getCategory(), budget.getLimitAmount(), spent);
            else if (pct >= budget.getAlertThresholdPct().doubleValue())
                budgetEventPublisher.publishThresholdExceeded(budget.getId(), event.userId(),
                        budget.getCategory(), budget.getLimitAmount(), spent, Math.round(pct * 10.0) / 10.0);
        }
    }
}
