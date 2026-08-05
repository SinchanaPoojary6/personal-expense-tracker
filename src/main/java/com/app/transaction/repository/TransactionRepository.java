package com.app.transaction.repository;

import com.app.transaction.domain.*;
import org.springframework.data.domain.*;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;

public interface TransactionRepository extends JpaRepository<Transaction, UUID> {

    Optional<Transaction> findByIdempotencyKeyAndDeletedAtIsNull(String key);

    @Query("""
        SELECT t FROM Transaction t
        WHERE t.userId = :userId AND t.deletedAt IS NULL
          AND (:category IS NULL OR t.category = :category)
          AND (:type IS NULL OR t.type = :type)
          AND (:from IS NULL OR t.transactionDate >= :from)
          AND (:to IS NULL OR t.transactionDate <= :to)
        """)
    Page<Transaction> findByUserFiltered(
            @Param("userId") UUID userId, @Param("category") Category category,
            @Param("type") TransactionType type, @Param("from") LocalDate from,
            @Param("to") LocalDate to, Pageable pageable);

    @Query(value = """
        SELECT COALESCE(SUM(amount), 0) FROM txn.transactions
        WHERE user_id = :userId AND type = 'EXPENSE' AND deleted_at IS NULL
          AND (:category IS NULL OR category_code = CAST(:category AS VARCHAR))
          AND EXTRACT(MONTH FROM transaction_date) = :month
          AND EXTRACT(YEAR  FROM transaction_date) = :year
        """, nativeQuery = true)
    BigDecimal sumExpensesByUserCategoryAndPeriod(
            @Param("userId") UUID userId, @Param("category") String category,
            @Param("month") int month, @Param("year") int year);

    @Modifying
    @Query("UPDATE Transaction t SET t.deletedAt = CURRENT_TIMESTAMP WHERE t.id = :id AND t.userId = :userId")
    int softDelete(@Param("id") UUID id, @Param("userId") UUID userId);
}
