-- 007_query_log_agentic_columns.sql
-- Add CRAG and agentic RAG tracking columns to query_log.
-- Safe to re-run: uses ADD COLUMN IF NOT EXISTS throughout.
--
-- New columns:
--   query_rewritten    — whether CRAG triggered a query rewrite (default false)
--   retrieval_attempts — number of retrieval passes, 1=normal, 2=CRAG retry (default 1)
--   original_query     — the user's original query when rewrite occurred
--   rewritten_query    — the LLM-rewritten query when rewrite occurred

ALTER TABLE query_log ADD COLUMN IF NOT EXISTS query_rewritten BOOLEAN DEFAULT FALSE;
ALTER TABLE query_log ADD COLUMN IF NOT EXISTS retrieval_attempts INTEGER DEFAULT 1;
ALTER TABLE query_log ADD COLUMN IF NOT EXISTS original_query TEXT;
ALTER TABLE query_log ADD COLUMN IF NOT EXISTS rewritten_query TEXT;
