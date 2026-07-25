package com.app.user.dto;
import jakarta.validation.constraints.*;
public record RegisterRequest(
        @Email @NotBlank String email,
        @NotBlank @Size(min = 8, max = 100) String password,
        @NotBlank @Size(min = 2, max = 100) String fullName) {}
