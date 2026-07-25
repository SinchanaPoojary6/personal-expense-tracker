package com.app.user.repository;
import com.app.user.domain.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import java.util.*;
public interface UserRepository extends JpaRepository<User, UUID> {
    Optional<User> findByEmailAndDeletedAtIsNull(String email);
    boolean existsByEmail(String email);
    @Query("SELECT u.id FROM User u WHERE u.deletedAt IS NULL AND u.isActive = true")
    List<UUID> findAllActiveIds();
}
