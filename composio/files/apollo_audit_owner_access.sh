#!/bin/sh
set -eu

if [ -n "${APOLLO_SECRET_DIR:-}" ] && [ -f "$APOLLO_SECRET_DIR/DATABASE_URL" ]; then
  DATABASE_URL="$(cat "$APOLLO_SECRET_DIR/DATABASE_URL")"
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo 'Apollo database URL is missing' >&2
  exit 1
fi

psql -X -w -v ON_ERROR_STOP=1 -v migration_role="${MIGRATION_ROLE:-}" \
  --dbname "$DATABASE_URL" <<'SQL'
-- Older pinned DB init images may not contain v175 yet.
SELECT (to_regprocedure('public.audit_log_insert(text)') IS NOT NULL)::int AS migrated \gset
\if :migrated
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL ROLE audit_owner;

-- On fresh installs v175 transfers tables with no explicit application ACL.
-- Ensure Apollo can read and use the guarded writer after that transfer.
SELECT format('GRANT SELECT ON TABLE public.audit_logs TO %I',
              COALESCE(NULLIF(:'migration_role', ''), session_user)) \gexec
SELECT format('GRANT EXECUTE ON FUNCTION public.audit_log_insert(text) TO %I',
              COALESCE(NULLIF(:'migration_role', ''), session_user)) \gexec
SELECT format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE %s FROM %I',
              relid::regclass, COALESCE(NULLIF(:'migration_role', ''), session_user))
FROM pg_partition_tree('public.audit_logs') \gexec
COMMIT;
\endif
SQL
