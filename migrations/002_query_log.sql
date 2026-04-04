-- 002_query_log.sql
-- Query log for observability, analytics, and retention.
-- Range-partitioned on created_at; partitions managed by pg_partman.
-- Safe to re-run: uses CREATE ... IF NOT EXISTS throughout.

CREATE TABLE IF NOT EXISTS query_log (
    id            BIGINT GENERATED ALWAYS AS IDENTITY,
    collection_id UUID REFERENCES collections(id) ON DELETE SET NULL,
    query_text    TEXT NOT NULL,
    query_hash    TEXT NOT NULL,
    grounding     TEXT NOT NULL CHECK (grounding IN ('corpus', 'general', 'mixed')),
    cited_chunks  TEXT[],
    cited_count   INTEGER GENERATED ALWAYS AS (
        CASE WHEN cited_chunks IS NOT NULL THEN cardinality(cited_chunks) ELSE 0 END
    ) STORED,
    total_chunks  INTEGER NOT NULL DEFAULT 0,
    latency_ms    INTEGER,
    model         TEXT,
    route         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX IF NOT EXISTS idx_query_log_created_at ON query_log (created_at);
CREATE INDEX IF NOT EXISTS idx_query_log_collection ON query_log (collection_id);
CREATE INDEX IF NOT EXISTS idx_query_log_grounding ON query_log (grounding);
CREATE INDEX IF NOT EXISTS idx_query_log_hash ON query_log (query_hash);
CREATE INDEX IF NOT EXISTS idx_query_log_cited_chunks ON query_log USING GIN (cited_chunks);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'litellm') THEN
        GRANT ALL ON query_log TO litellm;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO litellm;
    END IF;
END
$$;
