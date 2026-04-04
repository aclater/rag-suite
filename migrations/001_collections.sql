-- 001_collections.sql
-- Authoritative collection registry for the RAG suite.
-- Both ragstuffer (writes) and ragpipe (reads) use this table.
-- Safe to re-run: uses CREATE ... IF NOT EXISTS throughout.

CREATE TABLE IF NOT EXISTS collections (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_collections_name ON collections (name);

-- Grant access to the litellm application role if it exists.
-- In CI the role may not exist; the DO block silently skips.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'litellm') THEN
        GRANT ALL ON collections TO litellm;
        GRANT USAGE ON SCHEMA public TO litellm;
    END IF;
END
$$;
