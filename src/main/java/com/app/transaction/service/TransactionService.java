package com.app.transaction.service;

import com.app.shared.event.TransactionCreatedEvent;
import com.app.shared.exception.*;
import com.app.transaction.domain.*;
import com.app.transaction.dto.*;
import com.app.transaction.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import java.time.LocalDate;
import java.util.UUID;

@Service @RequiredArgsConstructor @Slf4j
public class TransactionService {
    private final TransactionRepository repo;
    private final ApplicationEventPublisher eventPublisher;

    @Transactional
    public TransactionResponse create(UUID userId, TransactionRequest req) {
        if (StringUtils.hasText(req.idempotencyKey()))
            repo.findByIdempotencyKeyAndDeletedAtIsNull(req.idempotencyKey())
                .ifPresent(t -> { throw new DuplicateResourceException("Duplicate transaction"); });

        Transaction tx = Transaction.builder().userId(userId).amount(req.amount())
                .type(req.type()).category(req.category()).description(req.description())
                .transactionDate(req.transactionDate()).idempotencyKey(req.idempotencyKey()).build();
        Transaction saved = repo.save(tx);
        log.info("Transaction created: id={} userId={}", saved.getId(), userId);

        eventPublisher.publishEvent(new TransactionCreatedEvent(
                saved.getId(), userId, saved.getAmount(), saved.getType(),
                saved.getCategory(), saved.getTransactionDate()));
        return TransactionResponse.from(saved);
    }

    @Transactional(readOnly = true)
    public Page<TransactionResponse> findAll(UUID userId, Pageable pageable,
            Category category, TransactionType type, LocalDate from, LocalDate to) {
        return repo.findByUserFiltered(userId, category, type, from, to, pageable)
                .map(TransactionResponse::from);
    }

    @Transactional(readOnly = true)
    public TransactionResponse findById(UUID userId, UUID id) {
        return repo.findById(id).filter(t -> t.getUserId().equals(userId) && t.getDeletedAt() == null)
                .map(TransactionResponse::from)
                .orElseThrow(() -> new ResourceNotFoundException("Transaction not found: " + id));
    }

    @Transactional
    public void delete(UUID userId, UUID id) {
        if (repo.softDelete(id, userId) == 0)
            throw new ResourceNotFoundException("Transaction not found: " + id);
        log.info("Transaction deleted: id={} userId={}", id, userId);
    }
}
