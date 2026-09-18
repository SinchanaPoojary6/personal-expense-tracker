-- =============================================================
-- dbscripts/transaction/V3__transaction_schema.sql
--
-- MODULE  : Transaction
-- SCHEMA  : txn
--
-- TABLES  : txn.categories, txn.transactions
--
-- DESIGN DECISIONS:
--   - OLTP: workload is INSERT-heavy (new transactions) + range scans
--     (history by date, by category). Indexes designed for both.
--   - categories is a reference table (small, stable) — avoids ENUM type
--     which requires ALTER TYPE migration to add new values.
--   - amount is NUMERIC(15,2): exact decimal arithmetic — never FLOAT/DOUBLE
--     for monetary values (floating point rounding errors are unacceptable).
--   - idempotency_key: client-generated UUID prevents duplicate submissions
--     from retries. UNIQUE constraint is the source of truth.
--   - user_id is NOT a FK to usr.users — module boundary. Cross-schema FKs
--     couple modules at the DB level, preventing future schema split.
--     Referential integrity enforced at the application layer.
--   - Soft delete via deleted_at: preserves audit trail, enables undo.
--   - Partial indexes (WHERE deleted_at IS NULL) keep index size small —
--     only active rows in the index.
--   - transaction_date is DATE not TIMESTAMPTZ: a transaction on July 10
--     is July 10 regardless of timezone. Budget month calculation is
--     date-based, not timestamp-based.
-- =============================================================

SET search_path TO txn, public;


-- ── txn.categories ────────────────────────────────────────────────────────────
-- Reference / lookup table.
-- Using a table instead of a PostgreSQL ENUM:
--   + New categories can be added with a simple INSERT (no DDL migration)
--   + Display names and metadata can be stored alongside
--   + Can be user-extensible in future (custom categories)

CREATE TABLE txn.categories (
    code            VARCHAR(50)     NOT NULL,
    display_name    VARCHAR(100)    NOT NULL,
    type_hint       VARCHAR(10)     NOT NULL DEFAULT 'BOTH',   -- INCOME | EXPENSE | BOTH
    icon_key        VARCHAR(50)     NULL,                      -- UI icon identifier
    sort_order      SMALLINT        NOT NULL DEFAULT 0,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_categories PRIMARY KEY (code),
    CONSTRAINT chk_categories_type_hint
        CHECK (type_hint IN ('INCOME', 'EXPENSE', 'BOTH')),
    CONSTRAINT chk_categories_code_format
        CHECK (code = UPPER(code))  -- always uppercase e.g. 'FOOD', 'RENT'
);

-- Seed data — standard categories
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

COMMENT ON TABLE  txn.categories          IS 'Reference table for transaction categories. Prefer INSERT over ENUM ALTER.';
COMMENT ON COLUMN txn.categories.type_hint IS 'Hint for UI: which transaction types this category applies to.';


-- ── txn.transactions ──────────────────────────────────────────────────────────

CREATE TABLE txn.transactions (
    -- ── Identity ────────────────────────────────────────────
    id                  UUID            NOT NULL DEFAULT gen_random_uuid(),

    -- ── Ownership (no FK — cross-module boundary) ───────────
    user_id             UUID            NOT NULL,

    -- ── Core financial fields ───────────────────────────────
    -- NUMERIC(15,2): supports up to 9,999,999,999,999.99
    -- Never use FLOAT or DOUBLE for money — binary floating point
    -- cannot represent all decimal fractions exactly.
    amount              NUMERIC(15,2)   NOT NULL,
    type                VARCHAR(10)     NOT NULL,   -- INCOME | EXPENSE
    category_code       VARCHAR(50)     NOT NULL,

    -- ── Descriptive fields ──────────────────────────────────
    description         TEXT            NULL,       -- free text, no length limit
    notes               TEXT            NULL,       -- internal notes, not shown in summaries
    reference_number    VARCHAR(100)    NULL,       -- bank/payment reference (optional)

    -- ── Date ────────────────────────────────────────────────
    -- DATE (not TIMESTAMPTZ): budget calculations are date-based.
    -- "July 10 transaction" means July 10 in the user's local date,
    -- not a UTC instant. Storing as DATE avoids timezone confusion.
    transaction_date    DATE            NOT NULL,

    -- ── Idempotency ─────────────────────────────────────────
    -- Client sends a UUID with each POST. If the same UUID is sent
    -- twice (retry), the second request gets 409 Conflict.
    -- UNIQUE constraint is the authority — not application-level locking.
    idempotency_key     VARCHAR(255)    NULL,

    -- ── Soft Delete ─────────────────────────────────────────
    deleted_at          TIMESTAMPTZ     NULL,       -- NULL = active

    -- ── Audit ───────────────────────────────────────────────
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- ── Constraints ─────────────────────────────────────────
    CONSTRAINT pk_transactions PRIMARY KEY (id),

    CONSTRAINT uq_transactions_idempotency
        UNIQUE (idempotency_key),               -- enforces exactly-once on client retries

    CONSTRAINT fk_transactions_category
        FOREIGN KEY (category_code) REFERENCES txn.categories (code),
        -- Within same schema, FK is fine and enforces referential integrity

    CONSTRAINT chk_transactions_amount_positive
        CHECK (amount > 0),                     -- amounts are always positive; type indicates direction

    CONSTRAINT chk_transactions_type
        CHECK (type IN ('INCOME', 'EXPENSE')),

    CONSTRAINT chk_transactions_date_range
        CHECK (transaction_date >= '2000-01-01'
           AND transaction_date <= CURRENT_DATE + INTERVAL '1 day')
        -- Prevents far-future or nonsensical dates; 1-day buffer for timezone edge cases
);

-- ── Indexes ───────────────────────────────────────────────────────────────────

-- 1. Paginated transaction history — most frequent query
--    "Give me user X's transactions ordered by date"
CREATE INDEX idx_txn_user_date
    ON txn.transactions (user_id, transaction_date DESC)
    WHERE deleted_at IS NULL;

-- 2. Budget analysis aggregation — SUM(amount) for a user+category+month
--    Using DATE_TRUNC in the index expression matches the query pattern exactly
CREATE INDEX idx_txn_user_category_month
    ON txn.transactions (user_id, category_code, DATE_TRUNC('month', transaction_date))
    WHERE deleted_at IS NULL AND type = 'EXPENSE';

-- 3. Monthly report aggregation — SUM income + expense for a user+month
CREATE INDEX idx_txn_user_month
    ON txn.transactions (user_id, DATE_TRUNC('month', transaction_date))
    WHERE deleted_at IS NULL;

-- 4. Idempotency check — exact lookup on submission
--    Partial: only non-null keys need to be in the index
CREATE UNIQUE INDEX idx_txn_idempotency
    ON txn.transactions (idempotency_key)
    WHERE idempotency_key IS NOT NULL AND deleted_at IS NULL;

-- 5. Trigram index for description search (optional feature: search by keyword)
CREATE INDEX idx_txn_description_trgm
    ON txn.transactions USING GIN (description gin_trgm_ops)
    WHERE deleted_at IS NULL AND description IS NOT NULL;

-- ── Trigger: auto-update updated_at ──────────────────────────────────────────
CREATE TRIGGER trg_transactions_updated_at
    BEFORE UPDATE ON txn.transactions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── Row-Level Security ────────────────────────────────────────────────────────
ALTER TABLE txn.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY txn_user_isolation ON txn.transactions
    USING (user_id = current_setting('app.current_user_id', TRUE)::UUID
           OR current_user = 'app_admin');

-- ── Comments ──────────────────────────────────────────────────────────────────
COMMENT ON TABLE  txn.transactions                  IS 'Core financial transaction ledger. OLTP — optimised for inserts and range scans.';
COMMENT ON COLUMN txn.transactions.amount            IS 'Always positive NUMERIC(15,2). Direction determined by type column. Never use FLOAT for money.';
COMMENT ON COLUMN txn.transactions.transaction_date  IS 'DATE (not TIMESTAMPTZ) — budget months are calendar-date based, not UTC-instant based.';
COMMENT ON COLUMN txn.transactions.idempotency_key   IS 'Client-generated UUID. UNIQUE constraint prevents duplicate submissions from retries.';
COMMENT ON COLUMN txn.transactions.user_id           IS 'No FK to usr.users — cross-module boundary. Integrity enforced at application layer.';
COMMENT ON COLUMN txn.transactions.deleted_at        IS 'Soft delete. NULL = active. Hard purge run by scheduled GDPR job.';
