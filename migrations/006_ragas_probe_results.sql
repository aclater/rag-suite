-- 006_ragas_probe_results.sql
-- ragprobe Ragas evaluation results table
--
-- Stores quantitative RAG quality metrics from ragprobe's Ragas integration.
-- Complementary to promptfoo's adversarial/structural tests — this table
-- captures quality metrics (faithfulness, answer_relevance, etc.)
--
-- Created by: Unit 4 (ragprobe Ragas integration)
-- See: ragprobe/ragas_eval.py, ragprobe/ragas_metrics.py

CREATE TABLE IF NOT EXISTS probe_results (
    id              SERIAL PRIMARY KEY,
    eval_run_id     TEXT NOT NULL,           -- UUID for this eval run
    eval_run_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    target          TEXT NOT NULL,            -- e.g. "primary-35b"
    ragpipe_version TEXT,                    -- git SHA of ragpipe under test
    model           TEXT,                    -- model that produced the answer
    question        TEXT NOT NULL,
    ground_truth    TEXT,                    -- for context recall
    answer          TEXT NOT NULL,
    context_chunks  JSONB NOT NULL,         -- retrieved chunks
    faithfulness    REAL,                    -- 0-1: is answer supported by context?
    answer_relevance REAL,                  -- 0-1: does answer address question?
    context_precision REAL,                  -- 0-1: were retrieved chunks relevant?
    context_recall   REAL,                  -- 0-1: does answer contain ground truth?
    routing         TEXT                    -- which semantic route was used
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_probe_results_target
    ON probe_results(target);

CREATE INDEX IF NOT EXISTS idx_probe_results_eval_run
    ON probe_results(eval_run_id);

CREATE INDEX IF NOT EXISTS idx_probe_results_eval_at
    ON probe_results(eval_run_at);

CREATE INDEX IF NOT EXISTS idx_probe_results_routing
    ON probe_results(routing);

COMMENT ON TABLE probe_results IS
    'Ragas evaluation results from ragprobe. Stores per-question quality metrics '
    'for RAG pipelines — faithfulness, answer relevance, context precision, and recall. '
    'Complementary to promptfoo adversarial tests which check structural correctness.';
