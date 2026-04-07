# Operational Runbook

Quick reference for common rag-suite operational tasks.

## Health Check — Full Stack

```bash
curl -s -4 http://localhost:8090/health  # ragpipe
curl -s -4 http://localhost:8091/health  # ragstuffer
curl -s -4 http://localhost:8095/health  # ragorchestrator
curl -s -4 http://localhost:9090/health  # ragwatch
curl -s -4 http://localhost:8092/health  # ragdeck
```

Or via ragwatch:
```bash
curl -s http://localhost:9090/metrics/summary | python3 -m json.tool
```

## Restart a Service

```bash
systemctl --user restart ragpipe
systemctl --user restart ragstuffer
systemctl --user restart ragorchestrator
systemctl --user restart ragwatch
systemctl --user restart ragdeck
```

**Expected startup times:**

| Service | Cold start | Warm start (MXR cached) |
|---------|-----------|--------------------------|
| ragpipe | ~3:53 (first boot) | ~6s |
| ragstuffer | ~30s | ~5s |
| ragorchestrator | ~10s | ~10s |
| ragwatch | ~2s | ~2s |
| ragdeck | ~5s | ~5s |

**Do not restart ragpipe casually** — cold start takes ~4 minutes on first boot. Use hot-reload endpoints instead:
```bash
# Reload routes without restart
curl -X POST http://localhost:8090/admin/reload-routes \
  -H "Authorization: Bearer $RAGPIPE_ADMIN_TOKEN"

# Reload system prompt without restart
curl -X POST http://localhost:8090/admin/reload-prompt \
  -H "Authorization: Bearer $RAGPIPE_ADMIN_TOKEN"
```

## Trigger ragstuffer Ingestion Manually

```bash
# Via ragdeck admin UI at http://localhost:8092
# Or trigger via the ingest endpoint if exposed
curl -X POST http://localhost:8091/ingest/trigger \
  -H "Authorization: Bearer $RAGSTUFFER_ADMIN_TOKEN"
```

## View Query Logs in Postgres

```bash
psql "postgresql://user:pass@localhost:5432/ragpipe" -c "
SELECT created_at, grounding, route, cited_count, latency_ms
FROM query_log
WHERE created_at > NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC
LIMIT 50;"
```

View partitions:
```bash
psql "postgresql://user:pass@localhost:5432/ragpipe" -c "\dt query_log_*"
```

Query a specific partition:
```bash
psql "postgresql://user:pass@localhost:5432/ragpipe" -c "
SELECT * FROM query_log_20260407
WHERE grounding = 'general'
LIMIT 20;"
```

## Run ragprobe Eval and Compare Targets

```bash
cd ~/git/ragprobe

# Run eval against a target
python -m ragprobe --target ragpipe-v1 --model Qwen3-32B

# Compare two eval runs
python scripts/compare_targets.py --eval-run-id <run1> --eval-run-id <run2>

# List available eval runs
psql "postgresql://user:pass@localhost:5432/ragpipe" -c "
SELECT eval_run_id, eval_run_at, target, model, COUNT(*) as questions
FROM probe_results
GROUP BY eval_run_id, eval_run_at, target, model
ORDER BY eval_run_at DESC
LIMIT 10;"
```

## Check GTT Memory Usage

```bash
# GTT usage on gfx1151
rocm-smi --showmeminfo gtt

# What's consuming GTT (model weights + KV cache)
rocm-smi --showmeminfo vram

# Total GTT available ~113GB
cat /sys/class/drm/card0/device/mem_info_gtt_total  # bytes
```

## Pull and Apply New Container Image

```bash
# Pull latest image
podman pull ghcr.io/aclater/ragpipe:main

# Restart service to pick up new image
systemctl --user restart ragpipe

# Verify version
curl -s http://localhost:8090/health
```

**Always pin to tag in quadlets** — never use `:latest` in production.

## Roll Back a Bad Deployment

```bash
# List recent image versions
podman images ghcr.io/aclater/ragpipe

# Roll back to previous image tag
podman tag ghcr.io/aclater/ragpipe:<previous-tag> ghcr.io/aclater/ragpipe:main
systemctl --user restart ragpipe

# Or edit the quadlet to pin a specific digest
sudo vim ~/.config/containers/systemd/ragpipe.container
systemctl --user daemon-reload
systemctl --user restart ragpipe
```

Check quadlet file:
```bash
cat ~/.config/containers/systemd/ragpipe.container | grep Image
```

## Check CI Status Across All Repos

```bash
for repo in ragpipe ragstuffer ragwatch ragdeck ragprobe rag-suite framework-ai-stack ragorchestrator; do
  echo "=== aclater/$repo ==="
  gh run list --repo aclater/$repo --limit 1 --json name,status,conclusion \
    --jq '.[] | "\(.name): \(.status) | \(.conclusion // "pending")"'
done
```

View a specific failing workflow:
```bash
gh run view <run-id> --repo aclater/<repo> --log
```

## Hot-Reload Without Restart

```bash
# Reload ragpipe routes (YAML config hot-reload)
curl -X POST http://localhost:8090/admin/reload-routes \
  -H "Authorization: Bearer $RAGPIPE_ADMIN_TOKEN"

# Reload ragpipe system prompt
curl -X POST http://localhost:8090/admin/reload-prompt \
  -H "Authorization: Bearer $RAGPIPE_ADMIN_TOKEN"

# Check MXR cache status
curl http://localhost:8090/admin/mxr-status \
  -H "Authorization: Bearer $RAGPIPE_ADMIN_TOKEN"
```

## Check Prometheus Metrics

```bash
# ragpipe metrics
curl http://localhost:8090/metrics

# ragwatch summary (JSON for Grafana)
curl http://localhost:9090/metrics/summary | python3 -m json.tool

# ragorchestrator metrics
curl http://localhost:8095/metrics
```

## Force CPU Mode (gfx1151 only)

If MIGraphX is causing issues on gfx1151:
```bash
RAGPIPE_FORCE_CPU=1 systemctl --user restart ragpipe
```

## View Logs

```bash
journalctl --user -u ragpipe -f
journalctl --user -u ragstuffer -f
journalctl --user -u ragorchestrator -f
journalctl --user -u ragwatch -f
```
