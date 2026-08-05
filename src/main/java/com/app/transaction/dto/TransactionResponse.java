package com.app.transaction.dto;
import com.app.transaction.domain.*;
import java.math.BigDecimal;
import java.time.*;
import java.util.UUID;
public record TransactionResponse(UUID id, BigDecimal amount, TransactionType type,
        Category category, String description, LocalDate transactionDate, Instant createdAt) {
    public static TransactionResponse from(Transaction t) {
        return new TransactionResponse(t.getId(), t.getAmount(), t.getType(),
                t.getCategory(), t.getDescription(), t.getTransactionDate(), t.getCreatedAt());
    }
}
