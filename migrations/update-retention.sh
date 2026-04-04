#!/bin/sh
# update-retention.sh — Change the query_log retention window.
#
# Retention is enforced by maintain-partitions.sh (run daily via systemd timer).
# This script validates the new value and runs an immediate maintenance pass
# so expired partitions are dropped without waiting for the next timer tick.
#
# Environment:
#   DATABASE_URL               — Postgres connection string (required)
#   DOCSTORE_URL               — Fallback if DATABASE_URL is unset
#   QUERY_LOG_RETENTION_DAYS   — New retention window in days (required)
set -eu

DAYS="${QUERY_LOG_RETENTION_DAYS:-}"
if [ -z "$DAYS" ]; then
    echo "ERROR: QUERY_LOG_RETENTION_DAYS must be set" >&2
    echo "Usage: QUERY_LOG_RETENTION_DAYS=90 bash update-retention.sh" >&2
    exit 1
fi

case "$DAYS" in
    ''|*[!0-9]*|0) echo "ERROR: QUERY_LOG_RETENTION_DAYS must be a positive integer (>= 1)" >&2; exit 1 ;;
esac

echo "Retention set to ${DAYS} days."
echo "Running immediate maintenance pass to drop newly expired partitions..."

# Delegate to maintain-partitions.sh which reads the same env var
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec sh "$SCRIPT_DIR/maintain-partitions.sh"
