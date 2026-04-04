# RAG Suite

A modular, corpus-preferring RAG stack. Documents go in, grounded answers come out, hallucinations get caught.

## Components

| Repo | What it does |
|------|-------------|
| [ragpipe](https://github.com/aclater/ragpipe) | RAG proxy — semantic routing, retrieval, reranking, citation validation, grounding classification |
| [ragstuffer](https://github.com/aclater/ragstuffer) | Document ingestion — polls Google Drive, git repos, and web URLs; extracts, chunks, embeds, indexes |
| [ragprobe](https://github.com/aclater/ragprobe) | Adversarial testing — 66+ tests across 13 categories for grounding quality, citation accuracy, and safety |
| [framework-ai-stack](https://github.com/aclater/framework-ai-stack) | Reference deployment — full local stack on Fedora with Podman quadlets, auto-tuning, and systemd |

## How they fit together

```
                   Google Drive / git repos / web URLs
                                |
                           ragstuffer
                         extract + chunk
                          embed + index
                           /        \
                     Postgres       Qdrant
                    (chunk text)  (vectors + refs)
                           \        /
  client ──► LiteLLM ──► ragpipe ──► model
                          │
                    classify query
                    search Qdrant
                    hydrate from Postgres
                    rerank (cross-encoder)
                    inject context + citations
                    forward to LLM
                    validate citations
                    classify grounding
                    emit audit log
                          │
                       ragprobe
                   (adversarial eval)
```

## Design principles

- **Corpus-preferring grounding** — retrieved documents are the primary source of truth. General knowledge is allowed but flagged with a warning prefix so consumers can distinguish.
- **Citation validation by code, not by the LLM** — ragpipe parses `[doc_id:chunk_id]` citations from model output and validates them against the retrieved set. Hallucinated references are stripped from non-streaming responses; streaming responses are validated post-hoc and invalid citations are logged.
- **Grounding classification** — every response is classified as `corpus`, `general`, or `mixed`, available in `rag_metadata` for downstream consumers.
- **Text-free audit logging** — grounding decisions are logged without echoing document text or user queries, safe for compliance-sensitive environments.
- **Separation of concerns** — ingestion, retrieval, inference, and testing are independent services. Swap any component without touching the others.
- **Semantic routing** — ragpipe classifies queries and routes them to different LLMs, vector collections, and document stores per routing domain. A medical corpus and a finance corpus can share the same endpoint with separate retrieval pipelines.

## Quick start

The fastest path to a running stack is [framework-ai-stack](https://github.com/aclater/framework-ai-stack):

```bash
git clone https://github.com/aclater/framework-ai-stack
cd framework-ai-stack
./llm-stack.sh setup    # auto-tunes for your hardware, pulls model, starts services
```

This brings up Postgres, Qdrant, ramalama (model serving), ragpipe, LiteLLM, Open WebUI, and ragstuffer as rootless Podman containers managed by systemd quadlets.

To run the components individually, see each repo's README.

## Running adversarial tests

Once ragpipe is running:

```bash
git clone https://github.com/aclater/ragprobe
cd ragprobe
npm install
cp targets.yaml.example targets.yaml   # point at your ragpipe instance
npx promptfoo eval
```

## Tech stack

- **Runtime**: Python (ragpipe, ragstuffer), Node.js (ragprobe), Bash (framework-ai-stack)
- **Embedding**: ONNX Runtime (bge-base-en-v1.5), no fastembed — 708 MB RSS
- **Reranking**: ONNX Runtime (MiniLM-L-6-v2 cross-encoder)
- **Vector DB**: Qdrant with int8 scalar quantization (reference payloads only)
- **Document store**: PostgreSQL (full chunk text, asyncpg pool)
- **Containers**: Rootless Podman, systemd quadlets, UBI base images, SELinux enforcing
- **Testing**: promptfoo with custom Python assertions, pytest

## License

Each component is licensed independently. See the LICENSE file in each repo.
