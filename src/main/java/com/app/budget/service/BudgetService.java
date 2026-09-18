package com.app.budget.service;

import com.app.budget.domain.Budget;
import com.app.budget.dto.*;
import com.app.budget.repository.BudgetRepository;
import com.app.shared.exception.ResourceNotFoundException;
import com.app.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;
import java.util.*;

@Service @RequiredArgsConstructor
public class BudgetService {
    private final BudgetRepository budgetRepository;
    private final TransactionRepository transactionRepository;

    @Transactional
    @CacheEvict(value = "budgets", key = "#userId + ':' + #req.year() + ':' + #req.month()")
    public BudgetResponse createOrUpdate(UUID userId, BudgetRequest req) {
        Budget budget = budgetRepository.findByUserIdAndCategoryAndMonthAndYear(
                userId, req.category(), req.month(), req.year())
                .orElse(Budget.builder().userId(userId).build());
        budget.setCategory(req.category());
        budget.setLimitAmount(req.limitAmount());
        budget.setMonth(req.month());
        budget.setYear(req.year());
        if (req.alertThresholdPct() != null) budget.setAlertThresholdPct(req.alertThresholdPct());
        Budget saved = budgetRepository.save(budget);
        return BudgetResponse.from(saved, getSpent(userId, saved));
    }

    @Transactional(readOnly = true)
    @Cacheable(value = "budgets", key = "#userId + ':' + #year + ':' + #month")
    public List<BudgetResponse> listWithSpending(UUID userId, int month, int year) {
        return budgetRepository.findByUserIdAndMonthAndYear(userId, month, year)
                .stream().map(b -> BudgetResponse.from(b, getSpent(userId, b))).toList();
    }

    @Transactional
    public void delete(UUID userId, UUID budgetId) {
        Budget b = budgetRepository.findById(budgetId)
                .filter(budget -> budget.getUserId().equals(userId))
                .orElseThrow(() -> new ResourceNotFoundException("Budget not found: " + budgetId));
        budgetRepository.delete(b);
    }

    private BigDecimal getSpent(UUID userId, Budget budget) {
        String cat = budget.getCategory() != null ? budget.getCategory().name() : null;
        BigDecimal spent = transactionRepository.sumExpensesByUserCategoryAndPeriod(
                userId, cat, budget.getMonth(), budget.getYear());
        return spent != null ? spent : BigDecimal.ZERO;
    }
}
