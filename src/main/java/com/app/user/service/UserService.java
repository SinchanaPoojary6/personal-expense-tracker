package com.app.user.service;

import com.app.shared.exception.ResourceNotFoundException;
import com.app.user.domain.User;
import com.app.user.dto.*;
import com.app.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.UUID;

@Service @RequiredArgsConstructor
public class UserService {
    private final UserRepository userRepository;

    @Cacheable(value = "user", key = "#userId")
    @Transactional(readOnly = true)
    public UserProfileResponse getProfile(UUID userId) {
        return UserProfileResponse.from(findById(userId));
    }

    @CacheEvict(value = "user", key = "#userId")
    @Transactional
    public UserProfileResponse updateProfile(UUID userId, UpdateProfileRequest req) {
        User user = findById(userId);
        if (req.fullName() != null) user.setFullName(req.fullName());
        return UserProfileResponse.from(userRepository.save(user));
    }

    public User findById(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found: " + userId));
    }
}
