package com.app.transaction.controller;

import com.app.transaction.domain.*;
import com.app.transaction.dto.*;
import com.app.transaction.service.TransactionService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.*;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDate;
import java.util.UUID;

@RestController @RequestMapping("/api/transactions") @RequiredArgsConstructor
public class TransactionController {
    private final TransactionService service;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public TransactionResponse create(@AuthenticationPrincipal UUID userId,
            @RequestBody @Valid TransactionRequest req) {
        return service.create(userId, req);
    }

    @GetMapping
    public Page<TransactionResponse> list(@AuthenticationPrincipal UUID userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) Category category,
            @RequestParam(required = false) TransactionType type,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        Pageable pg = PageRequest.of(page, Math.min(size, 100), Sort.by("transactionDate").descending());
        return service.findAll(userId, pg, category, type, from, to);
    }

    @GetMapping("/{id}")
    public TransactionResponse get(@AuthenticationPrincipal UUID userId, @PathVariable UUID id) {
        return service.findById(userId, id);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@AuthenticationPrincipal UUID userId, @PathVariable UUID id) {
        service.delete(userId, id);
    }
}
