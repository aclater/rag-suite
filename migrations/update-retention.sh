#!/bin/sh
# update-retention.sh — Change the query_log retention window post-deployment.
# Reads DATABASE_URL (or falls back to DOCSTORE_URL).
# Reads QUERY_LOG_RETENTION_DAYS (default: 30).
# Idempotent: safe to re-run at any time.
set -eu

DB_URL="${DATABASE_URL:-${DOCSTORE_URL:-}}"
if [ -z "$DB_URL" ]; then
    echo "ERROR: DATABASE_URL or DOCSTORE_URL must be set" >&2
    exit 1
fi

DAYS="${QUERY_LOG_RETENTION_DAYS:-30}"

# Validate DAYS is a positive integer (>= 1)
case "$DAYS" in
    ''|*[!0-9]*|0) echo "ERROR: QUERY_LOG_RETENTION_DAYS must be a positive integer (>= 1)" >&2; exit 1 ;;
esac

psql "$DB_URL" -v ON_ERROR_STOP=1 -v days="$DAYS" <<'SQL'
UPDATE partman.part_config
SET
    retention = :'days' || ' days',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table = 'public.query_log';
SQL

echo "Retention updated to ${DAYS} days."
