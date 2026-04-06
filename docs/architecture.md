# rag-suite Architecture

**Last updated:** April 2026
**Stack phase:** Agentic RAG (Phase 2 — CRAG + Self-RAG)

---

## Service Map

| Service | Port | Responsibility | Docs |
|---------|------|---------------|------|
| ragpipe | 8090 | RAG proxy — semantic routing, retrieval, reranking, citation validation, grounding classification | [ragpipe/README](https://github.com/aclater/ragpipe) |
| ragstuffer | 8091 | Document ingestion — Drive, git, web → Qdrant + Postgres | [ragstuffer/README](https://github.com/aclater/ragstuffer) |
| ragstuffer-mpep | 8093 | USPTO/MPEP-specific ingestion pipeline | same |
| ragorchestrator | 8095 | LangGraph agentic orchestration — adaptive classifier, CRAG, Self-RAG | [ragorchestrator/README](https://github.com/aclater/ragorchestrator) |
| ragwatch | 9090 | Prometheus metrics aggregation — scrapes all services, exposes /metrics/summary | [ragwatch/README](https://github.com/aclater/ragwatch) |
| ragdeck | 8092 | Admin UI — collections, ingest, query log, metrics, agentic observability | [ragdeck/README](https://github.com/aclater/ragdeck) |
| ragprobe | — | Ragas evaluation + adversarial testing — runs independently, writes to Postgres | [ragprobe/README](https://github.com/aclater/ragprobe) |
| Qdrant | 6333 | Vector store — separate collections per domain | — |
| Postgres | 5432 | Document store — chunks, collections, query_log, probe_results | — |
| LiteLLM | 4000 | Model proxy — OpenAI-compatible API for all LLM calls | — |
| llama-vulkan | 8080 | LLM inference — Qwen3-32B Q4_K_M, gfx1151 | — |
| Open WebUI | 3000 | Chat interface | — |

---

## Query Flow (Agentic RAG with CRAG)

```
Client → Open WebUI (:3000)
            ↓
      LiteLLM (:4000)
            ↓
   ragorchestrator (:8095) ←── Self-RAG reflection loop
            ↓
      classify complexity
      (simple | complex | external)
      /                \
   simple          complex/external
      ↓                   ↓
  ragpipe          ragpipe + CRAG
  (direct)         (corpus-aware retrieval)
      ↓                   ↓
    Qdrant              Qdrant
  (per-route)        (per-route, re-ranked)
      ↓                   ↓
  Postgres            Postgres
(chunks+title)      (chunks+title)
      ↓                   ↓
  ragpipe             ragpipe
  (synthesis)         (reflection: grounded?|ungrounded?)
      ↓                   ↓
    LLM                re-generate? ──→ loop
  (response)                ↓
      ↓                grounded
  response +              ↓
  rag_metadata      LLM (response)
```

### Step-by-step (complex query with CRAG)

1. **Classify** — ragorchestrator's adaptive classifier determines query complexity
2. **Retrieve** — ragpipe retrieves from the appropriate Qdrant collection
3. **Generate** — LLM generates answer from retrieved context
4. **Reflect** — Self-RAG reflection: is the answer grounded in the context?
   - `grounded` → return response
   - `ungrounded` → re-generate with CRAG (corpus-aware retrieval, broader search)
   - `useful` → return response (no further retrieval needed)

### Step-by-step (simple query)

1. **Classify** — simple query (factual lookup)
2. **Route** — ragorchestrator routes directly to ragpipe without agentic loop
3. **Retrieve** — ragpipe retrieves from appropriate Qdrant collection
4. **Generate** — LLM generates answer
5. **Return** — response + rag_metadata

---

## Self-RAG Reflection Loop

```
generate → reflect
    ↓
┌───────────────────────────────┼───────────────────────────────┐
↓                               ↓                               ↓
grounded                     useful                        ungrounded
↓                               ↓                               ↓
END                           END                          re-generate
                                                                ↓
                                                      ┌────────┴────────┐
                                                      ↓                  ↓
                                                 max retries?          corpus
                                                 exceeded?          retrieval
                                                      ↓                  ↓
                                                    END          (CRAG, broader search)
                                                      ↓
                                                  re-generate
```

Max retries: 3 (configurable via `MAX_RETRIEVAL_ATTEMPTS`)

---

## CRAG (Corpus-Aware Retrieval) Flow

When Self-RAG marks a response as `ungrounded`:

1. **Corpus classifier** — determines which Qdrant collection(s) to search
2. **Broader retrieval** — expands search beyond initial top-k results
3. **Re-ranking** — applies cross-encoder reranker to expanded result set
4. **Re-generate** — LLM generates new answer from re-ranked context
5. **Final reflect** — Self-RAG re-evaluates the new answer

---

## Adaptive Complexity Classifier

ragorchestrator uses a two-tier classifier:

| Complexity | Criteria | Behavior |
|------------|----------|----------|
| **simple** | Factual lookup, single document | Direct ragpipe retrieval, no agentic loop |
| **complex** | Multi-document synthesis, analysis | CRAG + Self-RAG |
| **external** | Real-time information, beyond corpus | Web search (DISABLED — `DISABLE_WEB_SEARCH=true`) |

Routing is stored in `probe_results.routing` for per-route quality analysis.

---

## Qdrant Collections

Each collection is a separate retrieval domain with isolated vector indices:

| Collection | Description | Typical Queries |
|-----------|-------------|----------------|
| `personnel` | Org chart, professional backgrounds | "Who does X report to?", "Tell me about Y's experience" |
| `nato` | NATO documents, defense strategy | "NATO AI adoption strategy", "Defense authorization act" |
| `mpep` | USPTO patent manual (MPEP) | "What does the patent manual say about prior art?" |
| `documents` | General documents | Catch-all for uncategorized content |
| `general` | No-RAG mode | Factual questions ("What is the capital of France?") |

Vector similarity threshold for routing: **0.75** (configurable)

---

## Postgres Schema

### `collections` (migration 001)

```sql
collections (
    id          UUID PRIMARY KEY,
    name        TEXT UNIQUE NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    source_types TEXT[],          -- e.g. ["drive", "git", "web"]
    created_at  TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ
)
```

### `chunks` (created by ragstuffer)

```sql
chunks (
    id              UUID PRIMARY KEY,
    collection_id    UUID REFERENCES collections(id),
    chunk_hash       TEXT,
    content         TEXT,
    title           TEXT,          -- extracted per source type
    source_uri      TEXT,
    created_at       TIMESTAMPTZ
)
```

### `query_log` (migration 002, partitioned by day)

```sql
query_log (
    id              BIGINT IDENTITY,
    collection_id   UUID REFERENCES collections(id),
    query_text      TEXT,
    query_hash      TEXT,
    grounding       TEXT CHECK (grounding IN ('corpus', 'general', 'mixed')),
    cited_chunks    TEXT[],        -- [doc_id:chunk_id, ...]
    cited_count     INTEGER GENERATED ALWAYS AS (cardinality(cited_chunks)),
    total_chunks    INTEGER,
    latency_ms      INTEGER,
    model           TEXT,
    route           TEXT,          -- personnel|nato|mpep|documents|general
    -- Agentic columns (added by ragorchestrator)
    query_rewritten TEXT,          -- TRUE if CRAG triggered rewrite
    retrieval_attempts INTEGER,     -- how many retrieval passes
    created_at      TIMESTAMPTZ
) PARTITION BY RANGE (created_at)
```

### `probe_results` (migration 006)

```sql
probe_results (
    id              SERIAL PRIMARY KEY,
    eval_run_id     TEXT NOT NULL,      -- UUID per eval run
    eval_run_at     TIMESTAMPTZ,
    target          TEXT NOT NULL,       -- e.g. "ragpipe-v1", "crag-v1"
    ragpipe_version TEXT,
    model           TEXT,
    question        TEXT,
    ground_truth    TEXT,
    answer          TEXT,
    context_chunks  JSONB,              -- retrieved chunk objects
    faithfulness    REAL,                -- 0-1: answer supported by context?
    answer_relevance REAL,               -- 0-1: answer addresses question?
    context_precision REAL,              -- 0-1: retrieved chunks relevant?
    context_recall   REAL,              -- 0-1: answer covers ground truth?
    routing         TEXT                 -- which semantic route was used
)
```

---

## Ragas Quality Baselines

Ragas metrics are stored in `probe_results` and compared using `ragprobe/scripts/compare_targets.py`.

### Phase 0 — Non-Agentic Baseline

| Route | Faithfulness | Answer Relevance | Context Precision | Context Recall |
|-------|-------------|-----------------|------------------|---------------|
| **Personnel** | 0.967 | — | — | — |
| **MPEP/lookup** | 0.333 | — | — | — |
| **General** | varies | — | — | — |
| **Aggregate** | 0.700 | 0.843 | 0.714 | — |

### Phase 1 — CRAG (Corpus-Aware Retrieval)

| Route | Faithfulness | Answer Relevance | Context Precision | Context Recall |
|-------|-------------|-----------------|------------------|---------------|
| **Personnel** | 0.950 | — | — | — |
| **MPEP/lookup** | 0.933 (+0.600) | — | — | — |
| **Aggregate** | **0.971** (+0.271) | — | — | — |

### Key Observations

- CRAG dramatically improved the weak MPEP route (0.333 → 0.933)
- Personnel route showed slight expected regression (0.967 → 0.950) — acceptable given overall improvement
- General route unchanged (no retrieval involved)

---

## ragorchestrator Metrics

ragorchestrator exposes Prometheus metrics at `:8095/metrics`:

| Metric | Type | Description |
|--------|------|-------------|
| `ragorchestrator_queries_total` | Counter | Total queries processed |
| `ragorchestrator_query_latency_seconds` | Histogram | End-to-end query latency |
| `ragorchestrator_tool_calls_total` | Counter | Tool invocations by tool name |
| `ragorchestrator_complexity_classified_total` | Counter | Queries by complexity class |

ragwatch scrapes ragorchestrator every 30s and includes it in `/metrics/summary`:

```json
{
  "sources": {
    "ragorchestrator": {"up": true, "metric_count": 34}
  },
  "ragorchestrator": {
    "queries_total": 0.0,
    "query_latency_seconds": 0.0,
    "tool_calls_total": 0.0,
    "complexity_classified_total": 0.0
  }
}
```

---

## Title Extraction Pipeline

1. ragstuffer extracts titles per source type:
   - **PDF**: Metadata title field
   - **Markdown**: First `# heading`
   - **Google Drive**: Document title API field
2. Titles stored in Postgres `chunks.title`
3. ragpipe hydrates retrieved chunks with titles at query time
4. Titles surfaced in `rag_metadata.cited_chunks[].title`

Example `cited_chunks` entry:
```json
{
  "id": "abc-123:0",
  "title": "Q3 Strategy 2026",
  "source": "gdrive://file.pdf"
}
```

Citation format: `[doc_id:chunk_id]` — NOT `[doc_id:...:chunk_id:...]`

---

## Hot-Reload Endpoints

No restart needed for configuration changes:

| Endpoint | Service | Purpose |
|----------|---------|---------|
| `POST /admin/reload-routes` | ragpipe :8090 | Reload semantic routing config |
| `POST /admin/reload-prompt` | ragpipe :8090 | Reload system prompt |

Routes and system prompt are mounted from host at `~/.config/ragpipe/routes.yaml` and `~/.config/ragpipe/system-prompt.txt`.

---

## GPU and Memory Architecture

- **APU**: AMD Ryzen AI Max+ 395 (gfx1151)
- **VRAM**: 512MB (GPU housekeeping only)
- **GTT**: ~113GB (model weights, KV cache, inference)
- **GPU executes compute against GTT** — full GPU inference, not CPU fallback

```bash
HSA_OVERRIDE_GFX_VERSION=11.5.1  # required for all ROCm workloads
```

### LLM Inference
- Container: `llama-vulkan` on port 8080
- Model: Qwen3-32B dense Q4_K_M (~19GB GTT)
- Backend: Vulkan RADV (gfx1151 optimized)
- Cold start: ~3:53 | Warm start (MXR cached): ~6s (39x improvement)
- `ORT_MIGRAPHX_MODEL_CACHE_PATH` enables MXR caching

### Embedder/Reranker
- CPU-based on gfx1151
- MIGraphX tensors land in GTT (not VRAM) — correct behavior for UMA APU

---

## Deployment

All services run as rootless Podman quadlets managed by systemd.

| Service | Quadlet | Image |
|---------|---------|-------|
| ragpipe | `ragpipe.container` | `ghcr.io/aclater/ragpipe:main` |
| ragstuffer | `ragstuffer.container` | `ghcr.io/aclater/ragstuffer:main` |
| ragorchestrator | `ragorchestrator.container` | `ghcr.io/aclater/ragorchestrator:main` |
| ragwatch | `ragwatch.container` | `ghcr.io/aclater/ragwatch:main` |
| ragdeck | `ragdeck.container` | `ghcr.io/aclater/ragdeck:main` |
| llama-vulkan | `llama-vulkan.container` | `ghcr.io/aclater/llama-vulkan:main` |

Key quadlet settings:
- `Network=host` for all services (required for localhost connectivity)
- `USER 1001` — all containers run as non-root
- Python healthcheck (UBI10-minimal has no curl)
- `SecurityLabelDisable=true` on GPU containers accessing `/dev/kfd`

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate Qdrant collections per domain | Isolates retrieval domains, prevents cross-contamination |
| Citation format `[doc_id:chunk_id]` | Simple, unique, no ambiguity from multi-part chunk IDs |
| Title hydration at query time | Avoids storing titles in vector payloads, keeps Qdrant lean |
| CRAG short-circuits Self-RAG | Performance optimization — avoid unnecessary reflection passes |
| `DISABLE_WEB_SEARCH=true` | TAVILY_API_KEY not yet configured |
| MXR caching for warm start | 39x startup improvement (3:53 → 6s) |
| GTT allocation for inference | Correct behavior for UMA APU — VRAM is only 512MB |

---

## Related Documentation

- [ragorchestrator LangGraph structure](../ragorchestrator/docs/graph.md) — flow diagrams
- [Phase 4 Graph RAG spike](./spikes/phase-4-graph-based-facts-layer.md) — future architecture considerations
- [ragprobe Ragas evaluation](../ragprobe/README.md) — quality measurement methodology
