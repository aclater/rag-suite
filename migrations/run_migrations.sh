#!/bin/sh
# run_migrations.sh — Apply all numbered SQL migrations in order.
# Idempotent: safe to re-run at any time.
#
# Environment:
#   DATABASE_URL           — Postgres connection string (required)
#   DOCSTORE_URL           — Fallback if DATABASE_URL is unset
#   QUERY_LOG_RETENTION_DAYS — Retention window for query_log (default: 30)
#   MIGRATION_USER         — Override the user in DATABASE_URL for psql
#   PG_CONTAINER           — Name of the running postgres container (default: postgres)
#
# Usage:
#   DATABASE_URL=postgresql://postgres:pass@host/db bash run_migrations.sh
#
# If psql is not available on the host, migrations are executed inside
# the running postgres container (identified by PG_CONTAINER).
set -eu

DB_URL="${DATABASE_URL:-${DOCSTORE_URL:-}}"
if [ -z "$DB_URL" ]; then
    echo "ERROR: DATABASE_URL or DOCSTORE_URL must be set" >&2
    exit 1
fi

# Allow overriding the user (e.g. use postgres superuser for extensions)
if [ -n "${MIGRATION_USER:-}" ]; then
    DB_URL=$(echo "$DB_URL" | sed "s|://[^:]*:|://${MIGRATION_USER}:|")
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RETENTION_DAYS="${QUERY_LOG_RETENTION_DAYS:-30}"
PG_CONTAINER="${PG_CONTAINER:-postgres}"

# Build psql command args
PSQL_ARGS="$DB_URL -v ON_ERROR_STOP=1 -v retention_days=$RETENTION_DAYS"

# Use host psql if available, otherwise exec into the postgres container.
# When running inside the container the host file path is not visible,
# so pipe the SQL content via stdin instead of using -f.
run_sql() {
    if command -v psql >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        psql $PSQL_ARGS -f "$1"
    else
        # shellcheck disable=SC2086
        podman exec -i "$PG_CONTAINER" sh -c "psql $PSQL_ARGS" < "$1"
    fi
}

for sql in "$SCRIPT_DIR"/[0-9][0-9][0-9]_*.sql; do
    [ -f "$sql" ] || continue
    echo "Applying $(basename "$sql")..."
    run_sql "$sql"
done

echo "Migrations complete."
