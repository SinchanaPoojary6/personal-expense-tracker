package com.app.user.controller;

import com.app.user.dto.*;
import com.app.user.service.*;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.UUID;

@RestController @RequiredArgsConstructor
public class UserController {
    private final AuthService authService;
    private final UserService userService;

    @PostMapping("/api/auth/register")
    @ResponseStatus(HttpStatus.CREATED)
    public AuthResponse register(@RequestBody @Valid RegisterRequest req) {
        return authService.register(req);
    }

    @PostMapping("/api/auth/login")
    public AuthResponse login(@RequestBody @Valid LoginRequest req) {
        return authService.login(req);
    }

    @GetMapping("/api/users/me")
    public UserProfileResponse getProfile(@AuthenticationPrincipal UUID userId) {
        return userService.getProfile(userId);
    }

    @PutMapping("/api/users/me")
    public UserProfileResponse updateProfile(@AuthenticationPrincipal UUID userId,
            @RequestBody @Valid UpdateProfileRequest req) {
        return userService.updateProfile(userId, req);
    }
}
