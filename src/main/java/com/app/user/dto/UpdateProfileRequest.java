package com.app.user.dto;
import jakarta.validation.constraints.Size;
public record UpdateProfileRequest(@Size(min = 2, max = 100) String fullName) {}
