#!/bin/sh
# init-pg-cron.sh — docker-entrypoint-initdb.d hook for pg_cron configuration.
# Runs once during initdb (fresh database only). Sets cron.database_name so
# pg_cron schedules and executes jobs in the application database instead of
# the default 'postgres' database.
set -eu

echo "cron.database_name = '${POSTGRES_DB:-postgres}'" >> "$PGDATA/postgresql.conf"
