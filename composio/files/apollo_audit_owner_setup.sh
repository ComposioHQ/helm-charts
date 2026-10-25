#!/bin/sh
set -eu

if [ -z "${DATABASE_URL:-}" ]; then
  echo 'Apollo database URL is missing' >&2
  exit 1
fi

# v175 creates the guarded insert function after ownership has been set up.
# Skip fresh installs (no audit_logs yet) and releases that already ran v175.
psql -X -v ON_ERROR_STOP=1 -v migration_role="${MIGRATION_ROLE:-}" \
  --dbname "$DATABASE_URL" <<'SQL'
SELECT (to_regclass('public.audit_logs') IS NOT NULL
    AND to_regprocedure('public.audit_log_insert(text)') IS NULL)::int AS setup_needed \gset
\if :setup_needed
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'audit_owner') THEN
    CREATE ROLE audit_owner NOLOGIN;
  END IF;
END $$;

-- PostgreSQL 16+ requires SET membership before a non-superuser can transfer
-- ownership to a role. The migration uses SET LOCAL ROLE audit_owner as well.
GRANT audit_owner TO CURRENT_USER WITH INHERIT FALSE, SET TRUE;
SELECT format('GRANT audit_owner TO %I WITH INHERIT FALSE, SET TRUE',
              COALESCE(NULLIF(:'migration_role', ''), session_user)) \gexec
GRANT USAGE, CREATE ON SCHEMA public TO audit_owner;

DO $$
DECLARE
  relation regclass;
BEGIN
  FOR relation IN
    SELECT t.relid FROM pg_partition_tree('public.audit_logs') t
    JOIN pg_class c ON c.oid = t.relid
    WHERE c.relowner <> 'audit_owner'::regrole
  LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO audit_owner', relation);
  END LOOP;
  IF (SELECT proowner FROM pg_proc
      WHERE oid = 'public.audit_logs_block_mutation()'::regprocedure)
      <> 'audit_owner'::regrole THEN
    ALTER FUNCTION public.audit_logs_block_mutation() OWNER TO audit_owner;
  END IF;
END $$;

-- Preserve the migration role's ability to read audit rows. Its temporary
-- INSERT grant lets v175 detect the writer and replace direct INSERT with
-- EXECUTE on the guarded audit_log_insert function.
SET LOCAL ROLE audit_owner;
SELECT format('GRANT SELECT, INSERT ON TABLE public.audit_logs TO %I',
              COALESCE(NULLIF(:'migration_role', ''), session_user)) \gexec
COMMIT;
\endif
SQL
