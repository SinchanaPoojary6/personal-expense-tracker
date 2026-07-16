-- =============================================================
-- dbscripts/shared/V1__shared_foundation.sql
--
-- PURPOSE : One-time foundation setup shared across all modules.
--           Run this FIRST before any module-specific scripts.
--
-- SCOPE   : Extensions, logical schemas, audit infrastructure,
--           shared lookup types, and reusable trigger functions.
-- =============================================================


-- ── EXTENSIONS ────────────────────────────────────────────────────────────────
-- pgcrypto  : gen_random_uuid() for UUID primary keys
-- pg_trgm   : trigram indexes for ILIKE / full-text search on descriptions
-- btree_gin : GIN indexes on scalar columns (used for JSONB + composite search)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";


-- ── LOGICAL SCHEMAS (module isolation) ────────────────────────────────────────
-- Each module lives in its own schema.
-- This enforces boundary visibility at the database level —
-- identical to how packages enforce it in Java.
-- In a future microservice split, each schema maps to its own database.

CREATE SCHEMA IF NOT EXISTS usr;           -- User module
CREATE SCHEMA IF NOT EXISTS txn;           -- Transaction module
CREATE SCHEMA IF NOT EXISTS bgt;           -- Budget module
CREATE SCHEMA IF NOT EXISTS ntf;           -- Notification module
CREATE SCHEMA IF NOT EXISTS rpt;           -- Report module


-- ── SEARCH PATH ───────────────────────────────────────────────────────────────
-- OPTIONAL: Sets the default schema resolution order at the database level.
-- REQUIRES: SUPERUSER or pg_database_owner role.
-- If you do not have superuser access, skip this line and configure
-- the search_path in the application JDBC URL instead:
--   jdbc:postgresql://localhost:5432/expense_tracker?currentSchema=usr,txn,bgt,ntf,rpt,public
--
-- Uncomment only if running as postgres superuser:
-- ALTER DATABASE expense_tracker SET search_path TO usr, txn, bgt, ntf, rpt, public;


-- ── AUDIT TRIGGER FUNCTION ────────────────────────────────────────────────────
-- Reusable function that auto-updates the updated_at column on every UPDATE.
-- Attach it to any table via CREATE TRIGGER (see each module script).
-- Defined in public schema so all module schemas can reference it.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- ── SOFT DELETE HELPER ────────────────────────────────────────────────────────
-- Convention: tables with soft-delete have a deleted_at TIMESTAMPTZ column.
-- NULL  = active row
-- value = deletion timestamp
-- All application queries must filter WHERE deleted_at IS NULL.
-- Hard deletes are performed by a scheduled GDPR purge job.

COMMENT ON FUNCTION public.set_updated_at() IS
    'Trigger function: automatically stamps updated_at on every UPDATE.
     Attach with: CREATE TRIGGER trg_<table>_updated_at
                  BEFORE UPDATE ON <schema>.<table>
                  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();';
