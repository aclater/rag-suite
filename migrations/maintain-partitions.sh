#!/bin/sh
# maintain-partitions.sh — Create upcoming partitions and drop expired ones.
# Designed to run daily via a systemd timer.
# Idempotent: safe to re-run at any time.
#
# Environment:
#   DATABASE_URL               — Postgres connection string (required)
#   DOCSTORE_URL               — Fallback if DATABASE_URL is unset
#   QUERY_LOG_RETENTION_DAYS   — Drop partitions older than this (default: 30)
#   QUERY_LOG_PREMAKE_DAYS     — Create partitions this many days ahead (default: 7)
#   PG_CONTAINER               — Postgres container name for podman exec fallback (default: postgres)
set -eu

DB_URL="${DATABASE_URL:-${DOCSTORE_URL:-}}"
if [ -z "$DB_URL" ]; then
    echo "ERROR: DATABASE_URL or DOCSTORE_URL must be set" >&2
    exit 1
fi

RETENTION_DAYS="${QUERY_LOG_RETENTION_DAYS:-30}"
PREMAKE_DAYS="${QUERY_LOG_PREMAKE_DAYS:-7}"
PG_CONTAINER="${PG_CONTAINER:-postgres}"

# Validate numeric inputs
case "$RETENTION_DAYS" in
    ''|*[!0-9]*|0) echo "ERROR: QUERY_LOG_RETENTION_DAYS must be a positive integer (>= 1)" >&2; exit 1 ;;
esac
case "$PREMAKE_DAYS" in
    ''|*[!0-9]*|0) echo "ERROR: QUERY_LOG_PREMAKE_DAYS must be a positive integer (>= 1)" >&2; exit 1 ;;
esac

SQL=$(cat <<EOSQL
DO \$\$
DECLARE
    day_offset  INTEGER;
    part_date   DATE;
    part_name   TEXT;
    start_ts    TEXT;
    end_ts      TEXT;
    drop_before DATE;
    rec         RECORD;
BEGIN
    -- Create upcoming partitions (today + premake days)
    FOR day_offset IN 0..${PREMAKE_DAYS} LOOP
        part_date := CURRENT_DATE + day_offset;
        part_name := 'query_log_' || to_char(part_date, 'YYYYMMDD');
        start_ts  := to_char(part_date, 'YYYY-MM-DD');
        end_ts    := to_char(part_date + 1, 'YYYY-MM-DD');

        IF NOT EXISTS (
            SELECT 1 FROM pg_class WHERE relname = part_name
        ) THEN
            EXECUTE format(
                'CREATE TABLE %I PARTITION OF query_log FOR VALUES FROM (%L) TO (%L)',
                part_name, start_ts, end_ts
            );
            RAISE NOTICE 'Created partition %', part_name;
        END IF;
    END LOOP;

    -- Drop expired partitions
    drop_before := CURRENT_DATE - ${RETENTION_DAYS};
    FOR rec IN
        SELECT c.relname
        FROM pg_inherits i
        JOIN pg_class c ON c.oid = i.inhrelid
        JOIN pg_class p ON p.oid = i.inhparent
        WHERE p.relname = 'query_log'
        ORDER BY c.relname
    LOOP
        -- Extract the date from partition name (query_log_YYYYMMDD)
        BEGIN
            part_date := to_date(substring(rec.relname from '\d{8}$'), 'YYYYMMDD');
            IF part_date < drop_before THEN
                EXECUTE format('DROP TABLE %I', rec.relname);
                RAISE NOTICE 'Dropped expired partition % (older than % days)', rec.relname, ${RETENTION_DAYS};
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Skip partitions that don't match the naming convention
            NULL;
        END;
    END LOOP;
END
\$\$;
EOSQL
)

# Use host psql if available, otherwise exec into the postgres container
if command -v psql >/dev/null 2>&1; then
    echo "$SQL" | psql "$DB_URL" -v ON_ERROR_STOP=1
else
    echo "$SQL" | podman exec -i "$PG_CONTAINER" psql "$DB_URL" -v ON_ERROR_STOP=1
fi

echo "Partition maintenance complete (premake=${PREMAKE_DAYS}d, retention=${RETENTION_DAYS}d)."
