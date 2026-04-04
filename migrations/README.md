# Migrations

Postgres schema migrations for the RAG suite. Applied once per Postgres
instance and consumed by all services (ragpipe, ragstuffer).

## Quick Start

```bash
# Local deployment (runs inside the postgres container via podman exec)
DATABASE_URL=postgresql://postgres:litellm@127.0.0.1:5432/litellm \
  bash migrations/run_migrations.sh

# CI / remote deployment
DATABASE_URL=postgresql://superuser:pass@host/db \
  bash migrations/run_migrations.sh
```

## Files

| File | Purpose |
|---|---|
| `001_collections.sql` | Collection registry (`collections` table) |
| `002_query_log.sql` | Query log with partitioning (`query_log` table) |
| `003_partman_config.sql` | pg_partman + pg_cron setup, retention config |
| `run_migrations.sh` | Applies all `NNN_*.sql` files in order (three-digit prefix) |
| `update-retention.sh` | Change `QUERY_LOG_RETENTION_DAYS` post-deployment |
| `test_migrations.py` | pytest suite — runs against a live Postgres instance |

## Adding a New Migration

1. Create `NNN_description.sql` where `NNN` is the next three-digit sequential
   number (e.g., `004_`, `005_`).
2. Use `CREATE ... IF NOT EXISTS` for all objects.
3. If the migration depends on an earlier one, document it in a comment.
4. Run `run_migrations.sh` locally to verify idempotency.
5. Add tests to `test_migrations.py`.

## Retention Configuration

The query log retention window is set during initial migration via
`QUERY_LOG_RETENTION_DAYS` (default: 30). To change it after deployment:

```bash
QUERY_LOG_RETENTION_DAYS=90 bash migrations/update-retention.sh
```

Or update `partman.part_config` directly:

```sql
UPDATE partman.part_config
SET retention = '90 days'
WHERE parent_table = 'public.query_log';
```

## Rollback

Migrations are additive only. To roll back, drop the affected objects and
re-run migrations:

```sql
DROP TABLE IF EXISTS query_log CASCADE;
DROP TABLE IF EXISTS collections CASCADE;
DROP EXTENSION IF EXISTS pg_cron;
DROP EXTENSION IF EXISTS pg_partman;
DROP SCHEMA IF EXISTS partman CASCADE;
```

Then re-run `run_migrations.sh`.

## Prerequisites

- Postgres 16
- `pg_partman` extension (installed in the container image)
- `pg_cron` extension (installed in the container image)
- `shared_preload_libraries = 'pg_cron'` in postgresql.conf
- `cron.database_name` set to the application database name

## Known Technical Debt

### `chunks.created_at` is TEXT, not TIMESTAMPTZ

The existing `chunks` table (created by ragpipe and ragstuffer at startup via
`CREATE TABLE IF NOT EXISTS`) stores `created_at` as `TEXT NOT NULL DEFAULT ''`
with ISO8601 strings. All new tables (`collections`, `query_log`) use
`TIMESTAMPTZ`.

This inconsistency is intentional for now — changing the column type requires
coordinating schema changes across ragpipe and ragstuffer simultaneously.
A future migration will address this once both services are updated to emit
and consume `TIMESTAMPTZ` values.
