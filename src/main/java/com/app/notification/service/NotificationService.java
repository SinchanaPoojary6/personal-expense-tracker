package com.app.notification.service;

import com.app.notification.domain.*;
import com.app.notification.dto.NotificationResponse;
import com.app.notification.repository.NotificationRepository;
import com.app.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.*;
import org.springframework.data.domain.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.UUID;

@Service @RequiredArgsConstructor @Slf4j
public class NotificationService {
    private final NotificationRepository repo;

    @Transactional
    @CacheEvict(value = "notif_count", key = "#userId")
    public NotificationResponse createAlert(UUID userId, String title, String message, NotificationType type) {
        Notification n = Notification.builder().userId(userId).type(type).title(title).message(message).build();
        return NotificationResponse.from(repo.save(n));
    }

    @Transactional(readOnly = true)
    public Page<NotificationResponse> findAll(UUID userId, int page, int size) {
        return repo.findByUserIdOrderByCreatedAtDesc(userId, PageRequest.of(page, Math.min(size, 50)))
                .map(NotificationResponse::from);
    }

    @Transactional(readOnly = true)
    @Cacheable(value = "notif_count", key = "#userId")
    public long countUnread(UUID userId) { return repo.countByUserIdAndReadFalse(userId); }

    @Transactional
    @CacheEvict(value = "notif_count", key = "#userId")
    public void markRead(UUID userId, UUID id) {
        if (repo.markRead(id, userId) == 0) throw new ResourceNotFoundException("Notification not found: " + id);
    }

    @Transactional
    @CacheEvict(value = "notif_count", key = "#userId")
    public void markAllRead(UUID userId) { repo.markAllRead(userId); }
}
