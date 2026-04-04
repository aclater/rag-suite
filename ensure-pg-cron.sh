#!/bin/sh
# ensure-pg-cron.sh — prepare an sclorg-initialized Postgres cluster for
# use with the stock postgres:16 image, then start the server.
#
# - Ensures shared_preload_libraries includes pg_cron
# - Configures cron.database_name so pg_cron reads jobs from the
#   application database (litellm) instead of the default postgres db
# - Removes the sclorg-specific include directive that references a
#   non-existent openshift-custom-postgresql.conf
# - Starts postgres directly (skips the stock entrypoint's initdb logic)
PG_DATA="${PGDATA:-/var/lib/postgresql/data}"
PG_CONF="$PG_DATA/postgresql.conf"
APP_DB="${POSTGRES_DATABASE:-${POSTGRESQL_DATABASE:-postgres}}"

if [ -f "$PG_CONF" ]; then
    # Remove the sclorg openshift include if present
    sed -i "/include.*openshift-custom-postgresql.conf/d" "$PG_CONF"

    # Ensure pg_cron is preloaded
    if ! grep -q "shared_preload_libraries.*pg_cron" "$PG_CONF"; then
        echo "shared_preload_libraries = 'pg_cron'" >> "$PG_CONF"
    fi

    # Tell pg_cron to read job definitions from the application database
    if ! grep -q "cron.database_name" "$PG_CONF"; then
        echo "cron.database_name = '${APP_DB}'" >> "$PG_CONF"
    fi
fi

exec gosu postgres postgres -D "$PG_DATA"
