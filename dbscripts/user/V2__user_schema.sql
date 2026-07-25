-- =============================================================
-- dbscripts/user/V2__user_schema.sql
--
-- MODULE  : User
-- SCHEMA  : usr
--
-- TABLES  : usr.users, usr.refresh_tokens
--
-- DESIGN DECISIONS:
--   - OLTP: all queries are point lookups by PK or email (unique index)
--   - UUID v4 PK: avoids sequential hotspot on inserts (no index page splits)
--   - BCrypt hash stored as VARCHAR(72) — BCrypt output is always 60 chars,
--     72 gives headroom if algorithm changes without a migration
--   - email stored lowercase — enforced by CHECK constraint + app layer
--   - refresh tokens hashed (SHA-256) before storage — raw token never persisted
--   - Soft delete via deleted_at: satisfies GDPR right-to-erasure audit trail
--   - role stored as VARCHAR not FK to a roles table — for this domain,
--     roles are a closed enum (USER, ADMIN); a FK table adds join cost with
--     no normalization benefit
-- =============================================================

SET search_path TO usr, public;


-- ── usr.users ─────────────────────────────────────────────────────────────────

CREATE TABLE usr.users (
    -- ── Identity ────────────────────────────────────────────
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    email           VARCHAR(254)    NOT NULL,   -- RFC 5321 max email length
    password_hash   VARCHAR(72)     NOT NULL,   -- BCrypt output (60 chars + margin)
    full_name       VARCHAR(150)    NOT NULL,

    -- ── Authorization ───────────────────────────────────────
    role            VARCHAR(20)     NOT NULL DEFAULT 'USER',

    -- ── Verification & Status ───────────────────────────────
    email_verified  BOOLEAN         NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    -- ── Audit ───────────────────────────────────────────────
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ     NULL,           -- NULL = active (soft delete)
    last_login_at   TIMESTAMPTZ     NULL,

    -- ── Constraints ─────────────────────────────────────────
    CONSTRAINT pk_users PRIMARY KEY (id),

    -- email must be lowercase — application layer also enforces this
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT chk_users_email_lowercase
        CHECK (email = LOWER(email)),
    CONSTRAINT chk_users_email_format
        CHECK (email ~* '^[A-Za-z0-9._%+][A-Za-z0-9._%+-]*@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_users_role
        CHECK (role IN ('USER', 'ADMIN')),
    CONSTRAINT chk_users_full_name_length
        CHECK (LENGTH(TRIM(full_name)) >= 2)
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
-- Primary lookup path: login by email
CREATE UNIQUE INDEX idx_users_email
    ON usr.users (email)
    WHERE deleted_at IS NULL;

-- Admin query: list active users, paginated by creation date
CREATE INDEX idx_users_created_at
    ON usr.users (created_at DESC)
    WHERE deleted_at IS NULL AND is_active = TRUE;

-- ── Trigger: auto-update updated_at ──────────────────────────────────────────
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON usr.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── Row-Level Security (RLS) ──────────────────────────────────────────────────
-- Enable RLS so that even if a query bug omits a WHERE clause,
-- a user cannot read another user's row at the DB level.
-- Application DB user 'app_user' can only see its own row.
-- Admin operations use a separate 'app_admin' role that bypasses RLS.

ALTER TABLE usr.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_isolation_policy ON usr.users
    USING (id = current_setting('app.current_user_id', TRUE)::UUID
           OR current_user = 'app_admin');

-- ── Comments ──────────────────────────────────────────────────────────────────
COMMENT ON TABLE  usr.users              IS 'Core user accounts. One row per registered user.';
COMMENT ON COLUMN usr.users.password_hash IS 'BCrypt hash (strength=12). Raw password never stored.';
COMMENT ON COLUMN usr.users.deleted_at    IS 'NULL = active. Populated on soft-delete for GDPR audit trail.';
COMMENT ON COLUMN usr.users.role          IS 'Closed enum: USER | ADMIN. Not a FK — closed set, no join needed.';


-- ── usr.refresh_tokens ────────────────────────────────────────────────────────
-- Stores server-side refresh token records.
-- The raw token is NEVER stored — only its SHA-256 hash.
-- This means a compromised DB does not expose valid tokens.

CREATE TABLE usr.refresh_tokens (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL,
    token_hash      VARCHAR(64)     NOT NULL,   -- SHA-256 hex digest (always 64 chars)
    expires_at      TIMESTAMPTZ     NOT NULL,
    revoked         BOOLEAN         NOT NULL DEFAULT FALSE,
    revoked_at      TIMESTAMPTZ     NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    user_agent      VARCHAR(512)    NULL,       -- device/browser for session management UI
    ip_address      INET            NULL,       -- PostgreSQL native IP type

    CONSTRAINT pk_refresh_tokens PRIMARY KEY (id),
    CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash),
    CONSTRAINT fk_refresh_tokens_user
        FOREIGN KEY (user_id) REFERENCES usr.users (id)
        ON DELETE CASCADE   -- hard delete user → tokens gone immediately
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT chk_refresh_token_hash_length
        CHECK (LENGTH(token_hash) = 64),
    CONSTRAINT chk_refresh_token_expiry
        CHECK (expires_at > created_at)
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
-- Token validation: most frequent query — look up by hash
CREATE UNIQUE INDEX idx_refresh_tokens_hash
    ON usr.refresh_tokens (token_hash)
    WHERE revoked = FALSE;

-- Session management: list active sessions for a user
CREATE INDEX idx_refresh_tokens_user_active
    ON usr.refresh_tokens (user_id, created_at DESC)
    WHERE revoked = FALSE;

-- Cleanup job: find expired tokens to purge
CREATE INDEX idx_refresh_tokens_expires
    ON usr.refresh_tokens (expires_at)
    WHERE revoked = FALSE;

-- ── Comments ──────────────────────────────────────────────────────────────────
COMMENT ON TABLE  usr.refresh_tokens             IS 'Server-side refresh token registry. Raw tokens never stored.';
COMMENT ON COLUMN usr.refresh_tokens.token_hash   IS 'SHA-256 hex digest of the raw refresh token.';
COMMENT ON COLUMN usr.refresh_tokens.ip_address   IS 'PostgreSQL INET type — stores IPv4 and IPv6 natively.';
COMMENT ON COLUMN usr.refresh_tokens.user_agent   IS 'Browser/device string for session listing UI.';
