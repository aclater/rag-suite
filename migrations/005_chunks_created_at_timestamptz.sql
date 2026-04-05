-- 005_chunks_created_at_timestamptz.sql
-- Migrate chunks.created_at from TEXT (ISO8601 strings) to TIMESTAMPTZ.
-- Technical debt from Unit 1: chunks table was created with TEXT created_at
-- while all other tables (collections, query_log) use TIMESTAMPTZ.
--
-- Prerequisites: ragpipe and ragstuffer must be updated to stop writing
-- ISO8601 strings before running this migration. Both should use
-- DEFAULT NOW() or pass TIMESTAMPTZ values.
--
-- Safe to run on empty tables. For tables with data, the USING clause
-- casts existing ISO8601 strings to TIMESTAMPTZ.
--
-- The chunks table is created by ragpipe/ragstuffer docstore, not by
-- rag-suite migrations. Skip gracefully if the table doesn't exist yet.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = 'chunks') THEN

        -- Only migrate if column is still TEXT
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'chunks' AND column_name = 'created_at'
                   AND data_type = 'text') THEN

            -- Replace empty string defaults with epoch to avoid cast errors
            UPDATE chunks SET created_at = '1970-01-01T00:00:00Z' WHERE created_at = '';

            ALTER TABLE chunks
                ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at::TIMESTAMPTZ;

            ALTER TABLE chunks
                ALTER COLUMN created_at SET DEFAULT NOW();

            RAISE NOTICE 'chunks.created_at migrated from TEXT to TIMESTAMPTZ';
        ELSE
            RAISE NOTICE 'chunks.created_at is already TIMESTAMPTZ — skipping';
        END IF;
    ELSE
        RAISE NOTICE 'chunks table does not exist yet — skipping migration';
    END IF;
END
$$;
