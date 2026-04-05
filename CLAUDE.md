# rag-suite

Modular, corpus-preferring RAG stack. Documents go in, grounded answers come out, hallucinations get caught.

## Components

| Repo | What it does | Status |
|------|-------------|--------|
| ragpipe | RAG proxy — semantic routing, retrieval, reranking, citation validation, grounding classification | Production |
| ragstuffer | Document ingestion — polls Google Drive, git repos, and web URLs; extracts, chunks, embeds, indexes | Production |
| ragprobe | Adversarial testing — 66+ tests across 13 categories for grounding quality, citation accuracy, and safety | Production |
| ragwatch | Observability — scrapes Prometheus metrics from ragpipe and ragstuffer, exposes /metrics and /metrics/summary | Production |
| ragdeck | Admin UI — single-pane management for collections, ingest, query log, probe runs, and metrics | Scaffold (health endpoint only) |
| framework-ai-stack | Reference deployment — full local stack on Fedora with Podman quadlets, auto-tuning, and systemd | Production |

## Architecture overview

```
Client → Open WebUI (:3000) → LiteLLM (:4000) → ragpipe (:8090)
                                                    │
                                    ┌───────────────┴───────────────┐
                                    │   Semantic Router (cosine sim) │
                                    └───────────────┬───────────────┘
                              ┌───────────────┼───────────────┐
                              ▼               ▼               ▼
                        personnel          nato              mpep
                        (Qdrant)         (Qdrant)         (Qdrant)
                              │               │               │
                              └───────────────┼───────────────┘
                                            ▼
                                     Postgres (:5432)
                                chunks + titles + query_log
                                            │
                          ┌─────────────────┼─────────────────┐
                          ▼                 ▼                 ▼
                    ragstuffer          ragwatch           ragdeck
                    (:8091)            (:9090)            (:8095)
                    (ingestion)        (metrics)          (admin UI)
```

### Semantic routing

ragpipe classifies queries using cosine similarity against pre-embedded route
examples and routes to the appropriate Qdrant collection. Each collection
(personnel, nato, mpep) is a separate retrieval domain.

Routes are hot-reloadable without restarting ragpipe:
```bash
curl -X POST http://localhost:8090/admin/reload-routes \
  -H "Authorization: Bearer $RAGPIPE_ADMIN_TOKEN"
```

### Title extraction pipeline

1. ragstuffer extracts titles per source type (PDF metadata, Markdown headings, etc.)
2. Titles stored in Postgres `chunks` table alongside chunk text
3. ragpipe surfaces titles in `rag_metadata.cited_chunks[].title` at query time

### Query log partitioning

`query_log` table is partitioned by day in Postgres:
```
query_log_20260405
query_log_20260406
query_log_20260407
...
```

This enables efficient time-series queries and archival.

## Shared Postgres schema

```
chunks         — Document chunk text + title (created by ragstuffer, read by ragpipe)
collections    — Collection registry with source_type
query_log      — Partitioned by day, written by ragpipe
LiteLLM_*      — LiteLLM proxy state and guardrail metrics
```

## GPU requirements

- **System**: AMD Ryzen AI Max+ 395 (gfx1151) with ROCm 7.x
- **GPU provider**: MIGraphXExecutionProvider only — ROCMExecutionProvider is ABI-incompatible with ROCm 7.x
- **Required env**: `HSA_OVERRIDE_GFX_VERSION=11.5.1`
- **⚠️ Startup time**: ragpipe takes ~3 minutes on first query after startup while MIGraphX compiles the inference graph

## Hot-reload endpoints

No need to restart ragpipe for configuration changes:
- `POST /admin/reload-prompt` — reload system prompt from file
- `POST /admin/reload-routes` — reload semantic routing config

Routes and system prompt are mounted from the host at `~/.config/ragpipe/routes.yaml`
and `~/.config/ragpipe/system-prompt.txt`.
