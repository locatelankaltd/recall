#!/usr/bin/env bash
# Runs an isolated ephemeral PostgreSQL cluster; never connects to a cloud project.
set -euo pipefail
recall_root="$(cd "$(dirname "$0")/../.." && pwd)"
recall_pg_bin="${RECALL_PG_BIN:-/opt/homebrew/opt/postgresql@14/bin}"
recall_tmp="$(mktemp -d "${TMPDIR:-/tmp}/recall-sql-test.XXXXXX")"
recall_port="${RECALL_TEST_PORT:-55439}"
cleanup() {
  "$recall_pg_bin/pg_ctl" -D "$recall_tmp/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$recall_tmp"
}
trap cleanup EXIT
"$recall_pg_bin/initdb" -D "$recall_tmp/data" -A trust --no-locale -E UTF8 >/dev/null
"$recall_pg_bin/pg_ctl" -D "$recall_tmp/data" -l "$recall_tmp/postgres.log" -o "-F -k $recall_tmp -p $recall_port -h 127.0.0.1" start >/dev/null
recall_psql=("$recall_pg_bin/psql" -X -v ON_ERROR_STOP=1 -h "$recall_tmp" -p "$recall_port" -d postgres)
"${recall_psql[@]}" -q -f "$recall_root/supabase/tests/bootstrap.sql"
for recall_migration in "$recall_root"/supabase/migrations/*.sql; do
  "${recall_psql[@]}" -q -f "$recall_migration"
done
"${recall_psql[@]}" -q -f "$recall_root/supabase/tests/security_and_workflow.sql"
"${recall_psql[@]}" -q -f "$recall_root/supabase/tests/analysis_quota.sql"
"${recall_psql[@]}" -q -f "$recall_root/supabase/tests/billing_security.sql"
"${recall_psql[@]}" -q -f "$recall_root/supabase/tests/plan_limits.sql"
"${recall_psql[@]}" -q -f "$recall_root/supabase/tests/review_receipt_replay.sql"

python3 "$recall_root/supabase/tests/concurrency.py" "$recall_pg_bin/psql" "$recall_tmp" "$recall_port"
