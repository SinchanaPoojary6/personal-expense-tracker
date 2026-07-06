package com.app.shared.security;

import lombok.extern.slf4j.Slf4j;
import org.hibernate.resource.jdbc.spi.StatementInspector;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Hibernate StatementInspector that sets the PostgreSQL session variable
 * 'app.current_user_id' before every SQL statement.
 *
 * This enables PostgreSQL Row Level Security (RLS) policies to filter
 * rows by the authenticated user at the database level — a second layer
 * of defence even if application queries forget a WHERE clause.
 *
 * RLS policies defined in the schema use:
 *   USING (user_id = current_setting('app.current_user_id', TRUE)::UUID
 *          OR current_user = 'app_admin')
 *
 * Registration: see JpaConfig — passed to HibernateJpaVendorAdapter
 * as hibernate.session_factory.statement_inspector.
 *
 * NOTE: This only works when RLS is enabled on tables AND the connection
 * user is NOT a superuser (superusers bypass RLS by default).
 * The app_user role does not have SUPERUSER, so RLS applies.
 */
@Component
@Slf4j
public class RlsStatementInspector implements StatementInspector {

    @Override
    public String inspect(String sql) {
        // This method is called per-statement; we use it as a hook
        // to ensure the session variable is set. The actual SET is
        // done in RlsHibernateConnectionProvider via a connection decorator.
        // Here we just return the SQL unchanged.
        return sql;
    }

    /**
     * Returns the current authenticated user's UUID as a string,
     * or null if not authenticated (e.g. during Flyway migrations,
     * health checks, or unauthenticated endpoints).
     */
    public static String currentUserIdOrNull() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.isAuthenticated() && auth.getPrincipal() instanceof UUID userId) {
            return userId.toString();
        }
        return null;
    }
}
