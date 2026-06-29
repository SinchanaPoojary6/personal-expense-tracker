package com.app.shared.event;

import com.app.transaction.domain.Category;
import com.app.transaction.domain.TransactionType;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

public record TransactionCreatedEvent(
        UUID transactionId, UUID userId, BigDecimal amount,
        TransactionType type, Category category, LocalDate transactionDate) {}
