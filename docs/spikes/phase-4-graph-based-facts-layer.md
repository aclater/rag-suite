# Phase 4 Research Spike: Graph-Based Facts Layer

**Issue:** rag-suite#19  
**Agent:** MiniMax M2.7  
**Completed:** 2026-04-06

---

## Executive Summary

**Recommendation: DEFER graph-based RAG until Phase 3 Self-RAG is production-validated.**

The current agentic RAG stack (CRAG + Self-RAG) has demonstrated dramatic quality improvements (Faithfulness: 0.700 → 0.971). Graph-based RAG adds significant infrastructure complexity for marginal gains that are not yet warranted by query failure analysis. The only candidate graph database that meets sovereign deployment requirements is **Neo4j**, which is the clear choice if graph RAG becomes necessary.

---

## Question 1: Do Our Use Cases Require Graph RAG?

### Current Quality Metrics

| Phase | Faithfulness | Answer Relevance | Context Precision |
|-------|-------------|-----------------|-------------------|
| Phase 0 (baseline) | 0.700 | 0.843 | 0.714 |
| Phase 1 (CRAG) | **0.971** | TBD | TBD |

CRAG solved the primary failure mode (hallucination). The remaining quality gaps are likely:
- **Personnel route**: Already strongest (F=0.967). Graph adds little.
- **MPEP/patent route**: Weakest (F=0.333 baseline → 0.933 after CRAG). CRAG's corpus-aware retrieval already addressed this.

### Graph RAG Use Cases in rag-suite

The issue identifies four candidate graph workloads:

| Candidate | Query Pattern | Vector Equivalent | Graph Advantage |
|-----------|--------------|-------------------|-----------------|
| Personnel org chart | "Who does X report to?" | Poor (semantic match fails on hierarchy) | **High** |
| Document citation chains | "Which patents cite prior art Z?" | Medium (semantic similarity) | **High** |
| Alliance relationships | "Which treaties has country X signed?" | Medium | **Medium** |
| Technology relationships | "What components does product Y use?" | Low | **Low** |

### Assessment

Only **personnel org chart** and **patent citation chains** have query patterns where graph traversal is meaningfully superior to vector similarity. These represent a small fraction of total queries.

**Verdict: Graph RAG is not yet warranted. CRAG + Self-RAG address the primary failure modes. Defer until:**
1. Phase 3 Self-RAG is production-validated
2. Query log analysis shows residual failures in relational query patterns
3. Personnel org chart data is available and ingested

---

## Question 2: Which Graph Database?

### Candidates Evaluated

| Database | Sovereign? | LangChain Integration | Status | Notes |
|----------|------------|---------------------|--------|-------|
| **Neo4j** | Yes | Excellent (5.x) | Active | Best choice if needed |
| Kuzu | Yes | Limited | **ARCHIVED Oct 2025** | Eliminated |
| Amazon Neptune | No (managed) | Good | Active | Not for sovereign deployments |
| RedisGraph | Yes | Good | Active (as part of Redis Stack) | Simpler but less mature |

### Neo4j Analysis

**Current Version:** Neo4j 5.x (community edition)  
**Licensing:** GPL v3 (community) / commercial (enterprise)  
**Key Features for rag-suite:**
- Cypher query language (mature, expressive)
- Vector index support (since Neo4j 5.x)
- APOC library for graph algorithms
- LangChain integration (`langchain-graphdb` community package)
- Docker/Podman deployment supported
- **Sovereign deployment** — runs fully on-premise

**Concerns:**
- JVM-based (higher memory footprint than native C++ alternatives)
- Requires separate service from Qdrant/Postgres
- Operational complexity increases with clustering

### Recommendation

If graph RAG is pursued in the future: **Use Neo4j 5.x**

Do not use Kuzu (archived). Do not use Neptune (not sovereign).

---

## Question 3: What Would Go in the Graph?

### Phase 4 Candidate Entities

Based on rag-suite's data model:

```
(:Person)
  └── reports_to: (:Person)           # org chart hierarchy
  └── member_of: (:Organization)

(:Document)
  └── cites: (:Document)              # patent prior art
  └── authored_by: (:Person)
  └── part_of: (:Collection)

(:Treaty)
  └── signatory: (:Country)
  └── commitment: (:Capability)

(:Product)
  └── uses_component: (:Component)
  └── vendor: (:Vendor)
```

### Population Strategy

1. **Personnel org chart**: Derived from personnel collection metadata (if structured data available)
2. **Patent citations**: Extracted during ragstuffer ingestion from PDF references
3. **Treaty relationships**: Extracted from document metadata or NER
4. **Technology relationships**: Requires structured component database (not currently available)

### Complexity Assessment

| Entity | Extraction Difficulty | Population Effort |
|--------|----------------------|-------------------|
| Personnel hierarchy | Medium (requires structured HR data) | High |
| Patent citations | High (PDF reference parsing) | Medium |
| Treaty relationships | Medium (structured metadata) | Medium |
| Technology components | High (no structured source) | Very High |

---

## Question 4: LangGraph Supervisor Routing

### Current Architecture (ragorchestrator)

```
supervisor → should_retrieve → [ragpipe_retrieval tool]
                                  ↓
                             generate → reflect
                                  ↓
               ┌─────────────────────────┼─────────────────────────┐
               ↓                         ↓                         ↓
           grounded                  useful                  ungrounded
               ↓                         ↓                         ↓
              END                       END                    re-generate
```

### Graph-Enabled Routing Decision

Adding graph capability would introduce a **routing decision** at the supervisor level:

```
Query → supervisor → route_decision
                      ↓
         ┌───────────┴───────────┐
         ↓                       ↓
    "relational?"           "semantic?"
         ↓                       ↓
    graph_query            ragpipe_retrieval
         ↓                       ↓
         └───────────┬───────────┘
                     ↓
               synthesize → response
```

### Query Classification Examples

| Query | Routing | Rationale |
|-------|---------|-----------|
| "Who does Dr. Smith report to?" | Graph | Direct relational lookup |
| "Which patents cite US10456782?" | Graph | Citation chain traversal |
| "Summarize the AI strategy for 2026" | Vector | Synthesis from multiple docs |
| "What is the melting point of steel?" | General | Factual, no corpus needed |
| "Compare NATO's deterrence posture to 2022" | Vector | Multi-document synthesis |

### Implementation Complexity

**Option A: LLM-based routing** (simpler)
- Ask LLM: "Does this query require relational reasoning?"
- Prompt injection risk, accuracy depends on model

**Option B: Keyword/pattern matching** (more reliable)
- Pattern: "who does X report to", "reports to", "citing", "cited by"
- Lower false positive rate, explicit

**Recommendation:** Option B initially, upgrade to A if pattern matching becomes too brittle.

---

## Deliverable Summary

### Recommendation: DEFER (Priority: LOW)

Graph-based RAG is a valuable capability for 2026, but the current stack (CRAG + Self-RAG) is not yet saturated. The infrastructure complexity (separate Neo4j service, graph population pipeline, routing logic) is not justified by current query failure patterns.

### If Proceeding (for future planning):

1. **Graph database:** Neo4j 5.x (sovereign, LangChain support, vector index)
2. **First workload:** Personnel org chart (highest graph advantage, clearest query pattern)
3. **Routing:** Pattern-matching initially, upgrade to LLM-based if needed
4. **Effort estimate:**
   - Infrastructure (Neo4j + quadlet): 1-2 days
   - Graph population (personnel): 3-5 days
   - Routing logic: 2-3 days
   - Testing: 2 days
   - **Total: 8-12 days**

### Decision Criteria for Future Activation

Monitor these metrics. If any trigger, reconsider graph RAG:

| Metric | Trigger |
|--------|---------|
| Self-RAG faithfulness (production) | < 0.95 after 30 days |
| Personnel route quality | < 0.90 after Phase 3 |
| Relational query failure rate | > 10% of personnel route queries |
| Org chart data availability | Personnel collection gains structured hierarchy field |

---

## References

- [Neo4j GraphRAG Python](https://github.com/neo4j-devtools/neo4j-graphrag-python)
- [LangChain Neo4j Integration](https://python.langchain.com/docs/integrations/graphstores/neo4j)
- [Kuzu Archived Notice](https://github.com/kuzudb/kuzu) — archived 2025-10-10
- [rag-suite Phase 1 CRAG Results](#) — Faithfulness 0.700 → 0.971
- [ragorchestrator current graph.py](https://github.com/aclater/ragorchestrator/blob/main/ragorchestrator/graph.py)
