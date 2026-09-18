package com.app.budget.controller;

import com.app.budget.dto.*;
import com.app.budget.service.BudgetService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController @RequestMapping("/api/budgets") @RequiredArgsConstructor
public class BudgetController {
    private final BudgetService budgetService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public BudgetResponse create(@AuthenticationPrincipal UUID userId,
            @RequestBody @Valid BudgetRequest req) {
        return budgetService.createOrUpdate(userId, req);
    }

    @GetMapping
    public List<BudgetResponse> list(@AuthenticationPrincipal UUID userId,
            @RequestParam int month, @RequestParam int year) {
        return budgetService.listWithSpending(userId, month, year);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@AuthenticationPrincipal UUID userId, @PathVariable UUID id) {
        budgetService.delete(userId, id);
    }
}
