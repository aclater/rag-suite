-- 004_collections_source_types.sql
-- Add source_types column to collections table for tracking document origins.
-- Both ragstuffer and ingest-remote populate this on first ingest.
-- Safe to re-run: uses ALTER TABLE ... ADD COLUMN IF NOT EXISTS.

ALTER TABLE collections ADD COLUMN IF NOT EXISTS source_types TEXT NOT NULL DEFAULT '[]';

-- Grant access to the litellm application role if it exists.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'litellm') THEN
        GRANT ALL ON collections TO litellm;
        GRANT USAGE ON SCHEMA public TO litellm;
    END IF;
END
$$;
