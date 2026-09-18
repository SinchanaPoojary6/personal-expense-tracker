package com.app.budget.repository;
import com.app.budget.domain.Budget;
import com.app.transaction.domain.Category;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.util.*;
public interface BudgetRepository extends JpaRepository<Budget, UUID> {
    List<Budget> findByUserIdAndMonthAndYear(UUID userId, int month, int year);
    Optional<Budget> findByUserIdAndCategoryAndMonthAndYear(UUID userId, Category category, int month, int year);
    @Query("""
        SELECT b FROM Budget b WHERE b.userId = :userId AND b.month = :month AND b.year = :year
          AND (b.category = :category OR b.category IS NULL)
        """)
    List<Budget> findApplicableBudgets(@Param("userId") UUID userId,
            @Param("category") Category category, @Param("month") int month, @Param("year") int year);
}
