package com.app.user.service;

import com.app.shared.exception.DuplicateResourceException;
import com.app.shared.security.JwtUtil;
import com.app.user.domain.User;
import com.app.user.dto.*;
import com.app.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service @RequiredArgsConstructor @Slf4j
public class AuthService {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;

    @Transactional
    public AuthResponse register(RegisterRequest req) {
        if (userRepository.existsByEmail(req.email().toLowerCase()))
            throw new DuplicateResourceException("Email already registered: " + req.email());
        User user = User.builder().email(req.email().toLowerCase())
                .passwordHash(passwordEncoder.encode(req.password()))
                .fullName(req.fullName()).build();
        User saved = userRepository.save(user);
        log.info("New user registered: userId={}", saved.getId());
        return new AuthResponse(saved.getId(), saved.getEmail(), saved.getFullName(),
                saved.getRole().name(), jwtUtil.generate(saved.getId(), saved.getRole().name()),
                jwtUtil.getExpiryMs() / 1000);
    }

    @Transactional(readOnly = true)
    public AuthResponse login(LoginRequest req) {
        User user = userRepository.findByEmailAndDeletedAtIsNull(req.email().toLowerCase())
                .orElseThrow(() -> new BadCredentialsException("Invalid credentials"));
        if (!passwordEncoder.matches(req.password(), user.getPasswordHash()))
            throw new BadCredentialsException("Invalid credentials");
        log.info("User logged in: userId={}", user.getId());
        return new AuthResponse(user.getId(), user.getEmail(), user.getFullName(),
                user.getRole().name(), jwtUtil.generate(user.getId(), user.getRole().name()),
                jwtUtil.getExpiryMs() / 1000);
    }
}
