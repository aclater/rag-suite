# Migrations

Postgres schema migrations for the RAG suite. Applied once per Postgres
instance and consumed by all services (ragpipe, ragstuffer).

Runs on `quay.io/sclorg/postgresql-16-c9s` — no additional extensions required.

## Quick Start

```bash
# Local deployment (runs inside the postgres container via podman exec)
DATABASE_URL=postgresql://litellm:litellm@127.0.0.1:5432/litellm \
  bash migrations/run_migrations.sh

# CI / remote deployment
DATABASE_URL=postgresql://user:pass@host/db \
  bash migrations/run_migrations.sh
```

## Files

| File | Purpose |
|---|---|
| `001_collections.sql` | Collection registry (`collections` table) |
| `002_query_log.sql` | Query log with partitioning (`query_log` table) |
| `003_create_partitions.sql` | Creates initial daily partitions (today + 7 days) |
| `run_migrations.sh` | Applies all `NNN_*.sql` files in order |
| `maintain-partitions.sh` | Creates upcoming partitions, drops expired ones |
| `update-retention.sh` | Change retention and run immediate maintenance |
| `test_migrations.py` | pytest suite — runs against a live Postgres instance |

## Partitioning

`query_log` is range-partitioned by `created_at` with daily granularity.
Partitions follow the naming convention `query_log_YYYYMMDD`.

Partition lifecycle is managed by `maintain-partitions.sh`, run daily
via a systemd timer:

- **Creates** partitions for the next 7 days (configurable via `QUERY_LOG_PREMAKE_DAYS`)
- **Drops** partitions older than 30 days (configurable via `QUERY_LOG_RETENTION_DAYS`)

The initial migration (`003_create_partitions.sql`) creates today + 7 days
of partitions so the table is usable immediately after `run_migrations.sh`.

### Installing the systemd timer

Copy the service and timer units from `quadlets/`:

```bash
cp quadlets/query-log-maintenance.service ~/.config/systemd/user/
cp quadlets/query-log-maintenance.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now query-log-maintenance.timer
```

Or add them to your `llm-stack.sh install` workflow.

## Retention Configuration

The retention window defaults to 30 days. To change it:

```bash
QUERY_LOG_RETENTION_DAYS=90 \
DATABASE_URL=postgresql://litellm:litellm@127.0.0.1:5432/litellm \
  bash migrations/update-retention.sh
```

This runs an immediate maintenance pass so expired partitions are dropped
without waiting for the next timer tick.

To change the default permanently, set `QUERY_LOG_RETENTION_DAYS` in
`~/.config/llm-stack/env`.

## Adding a New Migration

1. Create `NNN_description.sql` where `NNN` is the next three-digit sequential
   number (e.g., `004_`, `005_`).
2. Use `CREATE ... IF NOT EXISTS` for all objects.
3. If the migration depends on an earlier one, document it in a comment.
4. Run `run_migrations.sh` locally to verify idempotency.
5. Add tests to `test_migrations.py`.

## Rollback

Migrations are additive only. To roll back, drop the affected objects and
re-run migrations:

```sql
DROP TABLE IF EXISTS query_log CASCADE;
DROP TABLE IF EXISTS collections CASCADE;
```

Then re-run `run_migrations.sh`.

## Prerequisites

- Postgres 16 (`quay.io/sclorg/postgresql-16-c9s`)
- No additional extensions required

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
