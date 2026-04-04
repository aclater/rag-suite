-- 003_create_partitions.sql
-- Create initial daily partitions for query_log using native PG16 partitioning.
-- No extensions required — partition lifecycle is managed by maintain-partitions.sh
-- run on a systemd timer (daily).
--
-- Safe to re-run: uses CREATE TABLE IF NOT EXISTS throughout.
-- Creates today + 7 days of future partitions.

DO $$
DECLARE
    day_offset INTEGER;
    part_date  DATE;
    part_name  TEXT;
    start_ts   TEXT;
    end_ts     TEXT;
BEGIN
    -- Create today + 7 future daily partitions
    FOR day_offset IN 0..7 LOOP
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
        END IF;
    END LOOP;
END
$$;
