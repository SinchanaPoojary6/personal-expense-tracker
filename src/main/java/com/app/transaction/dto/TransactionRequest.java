package com.app.transaction.dto;
import com.app.transaction.domain.*;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.LocalDate;
public record TransactionRequest(
        @NotNull @Positive @Digits(integer = 13, fraction = 2) BigDecimal amount,
        @NotNull TransactionType type,
        @NotNull Category category,
        @Size(max = 500) String description,
        @NotNull @PastOrPresent LocalDate transactionDate,
        @Size(max = 255) String idempotencyKey) {}
