-- 003_partman_config.sql
-- Install pg_partman and pg_cron, configure daily partitioning and retention.
-- Requires: shared_preload_libraries = 'pg_cron' (set in postgresql.conf).
-- Safe to re-run: uses CREATE EXTENSION IF NOT EXISTS and guards create_parent.
-- The retention window is controlled by the :retention_days psql variable,
-- passed by run_migrations.sh (default: 30).

CREATE SCHEMA IF NOT EXISTS partman;

CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Only call create_parent if this table is not already registered.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM partman.part_config WHERE parent_table = 'public.query_log'
    ) THEN
        PERFORM partman.create_parent(
            p_parent_table   := 'public.query_log',
            p_control        := 'created_at',
            p_type           := 'range',
            p_interval       := '1 day',
            p_premake        := 7
        );
    END IF;
END
$$;

-- Default retention_days if not passed by run_migrations.sh
\if :{?retention_days}
\else
  \set retention_days 30
\endif

UPDATE partman.part_config
SET
    retention = :'retention_days' || ' days',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table = 'public.query_log';

-- Only schedule the cron job if it does not already exist.
DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'query_log_retention'
    ) THEN
        PERFORM cron.schedule(
            'query_log_retention',
            '0 2 * * *',
            $cmd$SELECT partman.run_maintenance(p_jobmon := false)$cmd$
        );
    END IF;
END
$migration$;
