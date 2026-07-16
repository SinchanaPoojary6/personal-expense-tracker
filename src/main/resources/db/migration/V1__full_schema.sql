-- =============================================================
-- src/main/resources/db/migration/V1__full_schema.sql
--
-- This is the single Flyway-managed migration file.
-- It is the authoritative, ordered combination of all module
-- scripts from dbscripts/.
--
-- EXECUTION ORDER (dependency order):
--   V1  shared/foundation    — extensions, schemas, audit trigger
--   V2  user                 — usr.users, usr.refresh_tokens
--   V3  transaction          — txn.categories, txn.transactions
--   V4  budget               — bgt.budgets, bgt.budget_audit_log
--   V5  notification         — ntf.notifications
--   V6  report               — rpt.monthly_report_cache, rpt.spending_trends
--   V7  shared/permissions   — roles and grants (run last, after all tables exist)
--
-- WORKFLOW:
--   - Edit the source files in dbscripts/<module>/
--   - Copy changes here before committing
--   - For schema changes AFTER v1, create V2__<description>.sql etc.
--   - Never edit a Flyway migration that has already been applied to prod.
--
-- LOCAL SETUP:
--   psql -U postgres -d expense_tracker -f this_file.sql
--   OR let Spring Boot + Flyway apply it automatically on startup.
-- =============================================================


-- ═══════════════════════════════════════════════════════════════
-- PART 1: SHARED FOUNDATION
-- Source: dbscripts/shared/V1__shared_foundation.sql
-- ═══════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

CREATE SCHEMA IF NOT EXISTS usr;
CREATE SCHEMA IF NOT EXISTS txn;
CREATE SCHEMA IF NOT EXISTS bgt;
CREATE SCHEMA IF NOT EXISTS ntf;
CREATE SCHEMA IF NOT EXISTS rpt;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- ═══════════════════════════════════════════════════════════════
-- PART 2: USER MODULE
-- Source: dbscripts/user/V2__user_schema.sql
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE usr.users (
    id              UUID         NOT NULL DEFAULT gen_random_uuid(),
    email           VARCHAR(254) NOT NULL,
    password_hash   VARCHAR(72)  NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    role            VARCHAR(20)  NOT NULL DEFAULT 'USER',
    email_verified  BOOLEAN      NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ  NULL,
    last_login_at   TIMESTAMPTZ  NULL,

    CONSTRAINT pk_users                PRIMARY KEY (id),
    CONSTRAINT uq_users_email          UNIQUE (email),
    CONSTRAINT chk_users_email_lower   CHECK (email = LOWER(email)),
    CONSTRAINT chk_users_email_format  CHECK (email ~* '^[A-Za-z0-9._%+][A-Za-z0-9._%+-]*@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_users_role          CHECK (role IN ('USER','ADMIN')),
    CONSTRAINT chk_users_name_length   CHECK (LENGTH(TRIM(full_name)) >= 2)
);

CREATE UNIQUE INDEX idx_users_email
    ON usr.users (email) WHERE deleted_at IS NULL;

CREATE INDEX idx_users_created_at
    ON usr.users (created_at DESC) WHERE deleted_at IS NULL AND is_active = TRUE;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON usr.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


CREATE TABLE usr.refresh_tokens (
    id          UUID         NOT NULL DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL,
    token_hash  VARCHAR(64)  NOT NULL,
    expires_at  TIMESTAMPTZ  NOT NULL,
    revoked     BOOLEAN      NOT NULL DEFAULT FALSE,
    revoked_at  TIMESTAMPTZ  NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    user_agent  VARCHAR(512) NULL,
    ip_address  INET         NULL,

    CONSTRAINT pk_refresh_tokens      PRIMARY KEY (id),
    CONSTRAINT uq_refresh_token_hash  UNIQUE (token_hash),
    CONSTRAINT fk_refresh_tokens_user
        FOREIGN KEY (user_id) REFERENCES usr.users (id) ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT chk_token_hash_length  CHECK (LENGTH(token_hash) = 64),
    CONSTRAINT chk_token_expiry       CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX idx_refresh_tokens_hash
    ON usr.refresh_tokens (token_hash) WHERE revoked = FALSE;

CREATE INDEX idx_refresh_tokens_user_active
    ON usr.refresh_tokens (user_id, created_at DESC) WHERE revoked = FALSE;

CREATE INDEX idx_refresh_tokens_expires
    ON usr.refresh_tokens (expires_at) WHERE revoked = FALSE;


-- ═══════════════════════════════════════════════════════════════
-- PART 3: TRANSACTION MODULE
-- Source: dbscripts/transaction/V3__transaction_schema.sql
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE txn.categories (
    code         VARCHAR(50)  NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    type_hint    VARCHAR(10)  NOT NULL DEFAULT 'BOTH',
    icon_key     VARCHAR(50)  NULL,
    sort_order   SMALLINT     NOT NULL DEFAULT 0,
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_categories         PRIMARY KEY (code),
    CONSTRAINT chk_categories_hint   CHECK (type_hint IN ('INCOME','EXPENSE','BOTH')),
    CONSTRAINT chk_categories_code   CHECK (code = UPPER(code))
);

INSERT INTO txn.categories (code, display_name, type_hint, sort_order) VALUES
    ('FOOD',          'Food & Dining',      'EXPENSE', 1),
    ('RENT',          'Rent & Housing',     'EXPENSE', 2),
    ('TRAVEL',        'Travel',             'EXPENSE', 3),
    ('UTILITIES',     'Utilities',          'EXPENSE', 4),
    ('HEALTHCARE',    'Healthcare',         'EXPENSE', 5),
    ('ENTERTAINMENT', 'Entertainment',      'EXPENSE', 6),
    ('EDUCATION',     'Education',          'EXPENSE', 7),
    ('SHOPPING',      'Shopping',           'EXPENSE', 8),
    ('SALARY',        'Salary',             'INCOME',  9),
    ('FREELANCE',     'Freelance Income',   'INCOME',  10),
    ('INVESTMENT',    'Investment Returns', 'INCOME',  11),
    ('OTHER',         'Other',              'BOTH',    99);


CREATE TABLE txn.transactions (
    id               UUID          NOT NULL DEFAULT gen_random_uuid(),
    user_id          UUID          NOT NULL,
    amount           NUMERIC(15,2) NOT NULL,
    type             VARCHAR(10)   NOT NULL,
    category_code    VARCHAR(50)   NOT NULL,
    description      TEXT          NULL,
    notes            TEXT          NULL,
    reference_number VARCHAR(100)  NULL,
    transaction_date DATE          NOT NULL,
    idempotency_key  VARCHAR(255)  NULL,
    deleted_at       TIMESTAMPTZ   NULL,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_transactions              PRIMARY KEY (id),
    CONSTRAINT uq_transactions_idempotency  UNIQUE (idempotency_key),
    CONSTRAINT fk_transactions_category
        FOREIGN KEY (category_code) REFERENCES txn.categories (code),
    CONSTRAINT chk_txn_amount_positive      CHECK (amount > 0),
    CONSTRAINT chk_txn_type                 CHECK (type IN ('INCOME','EXPENSE')),
    CONSTRAINT chk_txn_date_range
        CHECK (transaction_date >= '2000-01-01'
           AND transaction_date <= CURRENT_DATE + INTERVAL '1 day')
);

CREATE INDEX idx_txn_user_date
    ON txn.transactions (user_id, transaction_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_txn_user_category_month
    ON txn.transactions (user_id, category_code, DATE_TRUNC('month', transaction_date))
    WHERE deleted_at IS NULL AND type = 'EXPENSE';

CREATE INDEX idx_txn_user_month
    ON txn.transactions (user_id, DATE_TRUNC('month', transaction_date))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX idx_txn_idempotency
    ON txn.transactions (idempotency_key)
    WHERE idempotency_key IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_txn_description_trgm
    ON txn.transactions USING GIN (description gin_trgm_ops)
    WHERE deleted_at IS NULL AND description IS NOT NULL;

CREATE TRIGGER trg_transactions_updated_at
    BEFORE UPDATE ON txn.transactions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ═══════════════════════════════════════════════════════════════
-- PART 4: BUDGET MODULE
-- Source: dbscripts/budget/V4__budget_schema.sql
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE bgt.budgets (
    id                  UUID          NOT NULL DEFAULT gen_random_uuid(),
    user_id             UUID          NOT NULL,
    category_code       VARCHAR(50)   NULL,
    limit_amount        NUMERIC(15,2) NOT NULL,
    month               SMALLINT      NOT NULL,
    year                SMALLINT      NOT NULL,
    alert_threshold_pct NUMERIC(5,2)  NOT NULL DEFAULT 80.00,
    version             BIGINT        NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_budgets PRIMARY KEY (id),
    -- Uniqueness enforced via two partial indexes below (NULL-safe, PG12+ compatible).
    -- See idx_budget_uq_category_period and idx_budget_uq_overall_period.
    CONSTRAINT chk_budget_limit_positive    CHECK (limit_amount > 0),
    CONSTRAINT chk_budget_month_range       CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT chk_budget_year_range        CHECK (year >= 2000 AND year <= 2100),
    CONSTRAINT chk_budget_threshold_range   CHECK (alert_threshold_pct BETWEEN 1.00 AND 99.99)
);

CREATE INDEX idx_budget_user_period
    ON bgt.budgets (user_id, year, month);

CREATE INDEX idx_budget_user_category_period
    ON bgt.budgets (user_id, category_code, year, month);

-- NULL-safe uniqueness: two partial indexes replace UNIQUE NULLS NOT DISTINCT (PG15+)
-- Ensures one category budget and one overall budget per user per period.
CREATE UNIQUE INDEX idx_budget_uq_category_period
    ON bgt.budgets (user_id, category_code, month, year)
    WHERE category_code IS NOT NULL;

CREATE UNIQUE INDEX idx_budget_uq_overall_period
    ON bgt.budgets (user_id, month, year)
    WHERE category_code IS NULL;

CREATE TRIGGER trg_budgets_updated_at
    BEFORE UPDATE ON bgt.budgets
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


CREATE TABLE bgt.budget_audit_log (
    id            UUID          NOT NULL DEFAULT gen_random_uuid(),
    budget_id     UUID          NOT NULL,
    user_id       UUID          NOT NULL,
    action        VARCHAR(10)   NOT NULL,
    old_limit     NUMERIC(15,2) NULL,
    new_limit     NUMERIC(15,2) NULL,
    old_threshold NUMERIC(5,2)  NULL,
    new_threshold NUMERIC(5,2)  NULL,
    category_code VARCHAR(50)   NULL,
    month         SMALLINT      NOT NULL,
    year          SMALLINT      NOT NULL,
    changed_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    changed_by    UUID          NULL,

    CONSTRAINT pk_budget_audit_log PRIMARY KEY (id),
    CONSTRAINT chk_audit_action    CHECK (action IN ('CREATED','UPDATED','DELETED'))
);

CREATE INDEX idx_budget_audit_budget_id ON bgt.budget_audit_log (budget_id, changed_at DESC);
CREATE INDEX idx_budget_audit_user_id   ON bgt.budget_audit_log (user_id,   changed_at DESC);


-- ═══════════════════════════════════════════════════════════════
-- PART 5: NOTIFICATION MODULE
-- Source: dbscripts/notification/V5__notification_schema.sql
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE ntf.notifications (
    id            UUID         NOT NULL DEFAULT gen_random_uuid(),
    user_id       UUID         NOT NULL,
    type          VARCHAR(50)  NOT NULL,
    title         VARCHAR(255) NOT NULL,
    message       TEXT         NOT NULL,
    metadata      JSONB        NULL DEFAULT '{}',
    is_read       BOOLEAN      NOT NULL DEFAULT FALSE,
    read_at       TIMESTAMPTZ  NULL,
    email_sent    BOOLEAN      NOT NULL DEFAULT FALSE,
    email_sent_at TIMESTAMPTZ  NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_notifications       PRIMARY KEY (id),
    CONSTRAINT chk_notification_type  CHECK (type IN ('BUDGET_ALERT','EXCEEDED','SYSTEM')),
    CONSTRAINT chk_notification_read
        CHECK ((is_read = FALSE AND read_at IS NULL) OR
               (is_read = TRUE  AND read_at IS NOT NULL))
);

CREATE INDEX idx_ntf_user_unread
    ON ntf.notifications (user_id) WHERE is_read = FALSE;

CREATE INDEX idx_ntf_user_created
    ON ntf.notifications (user_id, created_at DESC);

CREATE INDEX idx_ntf_metadata_gin
    ON ntf.notifications USING GIN (metadata);

CREATE INDEX idx_ntf_created_at_retention
    ON ntf.notifications (created_at) WHERE is_read = TRUE;

CREATE OR REPLACE FUNCTION ntf.stamp_read_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.is_read = TRUE AND OLD.is_read = FALSE THEN NEW.read_at = NOW(); END IF;
    IF NEW.is_read = FALSE THEN NEW.read_at = NULL; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notifications_read_at
    BEFORE UPDATE OF is_read ON ntf.notifications
    FOR EACH ROW EXECUTE FUNCTION ntf.stamp_read_at();


-- ═══════════════════════════════════════════════════════════════
-- PART 6: REPORT MODULE
-- Source: dbscripts/report/V6__report_schema.sql
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE rpt.monthly_report_cache (
    id                  UUID          NOT NULL DEFAULT gen_random_uuid(),
    user_id             UUID          NOT NULL,
    month               SMALLINT      NOT NULL,
    year                SMALLINT      NOT NULL,
    total_income        NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_expense       NUMERIC(15,2) NOT NULL DEFAULT 0,
    net_savings         NUMERIC(15,2) GENERATED ALWAYS AS (total_income - total_expense) STORED,
    transaction_count   INTEGER       NOT NULL DEFAULT 0,
    category_breakdown  JSONB         NOT NULL DEFAULT '[]',
    top_category_code   VARCHAR(50)   NULL,
    top_category_amount NUMERIC(15,2) NULL,
    generated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_monthly_report_cache       PRIMARY KEY (id),
    CONSTRAINT uq_report_cache_user_period   UNIQUE (user_id, month, year),
    CONSTRAINT chk_report_month_range        CHECK (month BETWEEN 1 AND 12),
    CONSTRAINT chk_report_year_range         CHECK (year >= 2000),
    CONSTRAINT chk_report_totals_non_negative
        CHECK (total_income >= 0 AND total_expense >= 0)
);

CREATE UNIQUE INDEX idx_rpt_cache_user_period
    ON rpt.monthly_report_cache (user_id, year, month);

CREATE INDEX idx_rpt_cache_generated_at
    ON rpt.monthly_report_cache (generated_at);


CREATE TABLE rpt.spending_trends (
    id                  UUID          NOT NULL DEFAULT gen_random_uuid(),
    user_id             UUID          NOT NULL,
    category_code       VARCHAR(50)   NOT NULL,
    avg_monthly_expense NUMERIC(15,2) NOT NULL DEFAULT 0,
    max_monthly_expense NUMERIC(15,2) NOT NULL DEFAULT 0,
    min_monthly_expense NUMERIC(15,2) NOT NULL DEFAULT 0,
    trend_from_month    SMALLINT      NOT NULL,
    trend_from_year     SMALLINT      NOT NULL,
    trend_to_month      SMALLINT      NOT NULL,
    trend_to_year       SMALLINT      NOT NULL,
    calculated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_spending_trends              PRIMARY KEY (id),
    CONSTRAINT uq_spending_trends_user_category UNIQUE (user_id, category_code)
);

CREATE INDEX idx_spending_trends_user
    ON rpt.spending_trends (user_id, category_code);
