-- =============================================================
-- dbscripts/budget/V4__budget_schema.sql
--
-- MODULE  : Budget
-- SCHEMA  : bgt
--
-- TABLES  : bgt.budgets, bgt.budget_audit_log
--
-- DESIGN DECISIONS:
--   - category_code is nullable: NULL = overall monthly budget (all categories).
--     This allows two types of budgets per period:
--       1. Per-category: category_code = 'FOOD', month=7, year=2025
--       2. Overall monthly: category_code = NULL, month=7, year=2025
--   - UNIQUE constraint on (user_id, category_code, month, year) with
--     NULLS NOT DISTINCT (PG 15+) — ensures only one overall budget per period.
--   - Optimistic locking via version column: prevents lost-update anomaly
--     when two requests update the same budget concurrently.
--     Application checks version on UPDATE; throws OptimisticLockException if stale.
--   - alert_threshold_pct stored per-budget: different budgets can have
--     different sensitivity (e.g. alert at 70% for rent, 90% for entertainment).
--   - audit_log table: tracks every change to a budget — who changed what,
--     when, and what the old values were. Essential for financial systems.
--   - No cross-schema FK to txn.transactions — module boundary.
--     Spending is calculated at query time, not stored here.
-- =============================================================

SET search_path TO bgt, public;


-- ── bgt.budgets ───────────────────────────────────────────────────────────────

CREATE TABLE bgt.budgets (
    -- ── Identity ────────────────────────────────────────────
    id                      UUID            NOT NULL DEFAULT gen_random_uuid(),

    -- ── Ownership ───────────────────────────────────────────
    user_id                 UUID            NOT NULL,   -- no FK, cross-module boundary

    -- ── Budget definition ───────────────────────────────────
    -- NULL category = overall monthly budget across all categories
    category_code           VARCHAR(50)     NULL,

    -- Budget ceiling for the period
    limit_amount            NUMERIC(15,2)   NOT NULL,

    -- Calendar period — stored as separate int columns (not DATE range) because:
    --   1. A budget is always exactly one calendar month
    --   2. Queries always filter by EXTRACT(MONTH) and EXTRACT(YEAR)
    --   3. Avoids ambiguity of "which day of month starts/ends the budget"
    month                   SMALLINT        NOT NULL,
    year                    SMALLINT        NOT NULL,

    -- Alert fires when spending reaches this % of limit_amount
    alert_threshold_pct     NUMERIC(5,2)    NOT NULL DEFAULT 80.00,

    -- ── Concurrency control ─────────────────────────────────
    -- Optimistic locking: JPA @Version increments on every UPDATE.
    -- If two threads read version=3 and both try to UPDATE,
    -- the second one finds version≠3 and throws OptimisticLockException.
    version                 BIGINT          NOT NULL DEFAULT 0,

    -- ── Audit ───────────────────────────────────────────────
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- ── Constraints ─────────────────────────────────────────
    CONSTRAINT pk_budgets PRIMARY KEY (id),

    -- One budget per user+category+period.
    -- NOTE: We cannot use a standard UNIQUE constraint here because
    -- SQL treats NULL != NULL, so (user_id, NULL, month, year) would
    -- never conflict with itself — allowing multiple "overall" budgets.
    --
    -- PostgreSQL 15+ solution: UNIQUE NULLS NOT DISTINCT
    -- PostgreSQL 12-14 solution: partial unique index (used below).
    -- We use the partial index approach for maximum compatibility.
    -- See index: idx_budget_overall_period and idx_budget_category_period below.

    CONSTRAINT chk_budget_limit_positive
        CHECK (limit_amount > 0),

    CONSTRAINT chk_budget_month_range
        CHECK (month BETWEEN 1 AND 12),

    CONSTRAINT chk_budget_year_range
        CHECK (year >= 2000 AND year <= 2100),

    CONSTRAINT chk_budget_threshold_range
        CHECK (alert_threshold_pct BETWEEN 1.00 AND 99.99)
        -- Never set threshold at 100% — that's the exceeded event, not the warning
);

-- ── Indexes ───────────────────────────────────────────────────────────────────

-- 1. List all budgets for a user in a given month — primary read path
CREATE INDEX idx_budget_user_period
    ON bgt.budgets (user_id, year, month);

-- 2. Look up a specific budget for analysis (Budget module listener)
CREATE INDEX idx_budget_user_category_period
    ON bgt.budgets (user_id, category_code, year, month);

-- 3+4. Enforce one budget per user+category+period (NULL-safe uniqueness).
--      Two partial indexes instead of UNIQUE NULLS NOT DISTINCT (PG15+):
--
--      a) Category-specific budgets: (user_id, category_code, month, year)
--         WHERE category_code IS NOT NULL
CREATE UNIQUE INDEX idx_budget_uq_category_period
    ON bgt.budgets (user_id, category_code, month, year)
    WHERE category_code IS NOT NULL;

--      b) Overall monthly budget: only one allowed per user+period
--         WHERE category_code IS NULL
CREATE UNIQUE INDEX idx_budget_uq_overall_period
    ON bgt.budgets (user_id, month, year)
    WHERE category_code IS NULL;

-- ── Trigger: auto-update updated_at ──────────────────────────────────────────
CREATE TRIGGER trg_budgets_updated_at
    BEFORE UPDATE ON bgt.budgets
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── Comments ──────────────────────────────────────────────────────────────────
COMMENT ON TABLE  bgt.budgets                       IS 'Monthly budgets per user. NULL category = overall monthly budget.';
COMMENT ON COLUMN bgt.budgets.category_code          IS 'NULL = overall monthly budget. Non-null = category-specific budget.';
COMMENT ON COLUMN bgt.budgets.version                IS 'Optimistic lock counter. JPA @Version — prevents concurrent lost-update anomaly.';
COMMENT ON COLUMN bgt.budgets.alert_threshold_pct    IS 'Alert fires at this % of limit. Range 1-99.99. 100% triggers exceeded event, not alert.';


-- ── bgt.budget_audit_log ──────────────────────────────────────────────────────
-- Immutable log of every budget change. Append-only (no UPDATEs, no DELETEs).
-- Required for financial systems: "what was my budget last month and when did I change it?"

CREATE TABLE bgt.budget_audit_log (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    budget_id       UUID            NOT NULL,   -- references budgets.id (no FK — audit log is immutable)
    user_id         UUID            NOT NULL,
    action          VARCHAR(10)     NOT NULL,   -- CREATED | UPDATED | DELETED

    -- Snapshot of values at time of change
    old_limit       NUMERIC(15,2)   NULL,
    new_limit       NUMERIC(15,2)   NULL,
    old_threshold   NUMERIC(5,2)    NULL,
    new_threshold   NUMERIC(5,2)    NULL,
    category_code   VARCHAR(50)     NULL,
    month           SMALLINT        NOT NULL,
    year            SMALLINT        NOT NULL,

    changed_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    changed_by      UUID            NULL,       -- user who made the change (for admin audit)

    CONSTRAINT pk_budget_audit_log PRIMARY KEY (id),
    CONSTRAINT chk_audit_action CHECK (action IN ('CREATED', 'UPDATED', 'DELETED'))
);

-- Append-only table: never UPDATE or DELETE rows here
-- Revoke UPDATE/DELETE privileges on this table from app_user
-- (enforced in V7__db_roles_and_permissions.sql)

CREATE INDEX idx_budget_audit_budget_id ON bgt.budget_audit_log (budget_id, changed_at DESC);
CREATE INDEX idx_budget_audit_user_id   ON bgt.budget_audit_log (user_id, changed_at DESC);

COMMENT ON TABLE bgt.budget_audit_log IS 'Immutable audit trail of all budget changes. Append-only — no UPDATEs or DELETEs permitted.';
