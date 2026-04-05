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

-- Step 1: Convert existing TEXT values to TIMESTAMPTZ.
-- Empty strings (the old DEFAULT '') are replaced with the epoch to avoid
-- cast errors, then the default is changed to NOW().
UPDATE chunks SET created_at = '1970-01-01T00:00:00Z' WHERE created_at = '';

ALTER TABLE chunks
    ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at::TIMESTAMPTZ;

ALTER TABLE chunks
    ALTER COLUMN created_at SET DEFAULT NOW();
