# Research Spike: Kuadrant + Authorino for OpenShift AI Deployment

**Issue:** rag-suite#22  
**Agent:** MiniMax M2.7  
**Completed:** 2026-04-06

---

## Executive Summary

**Recommendation: Pursue simple API key middleware (issue #20) before investing in Kuadrant. Defer full Kuadrant deployment until OpenShift AI migration is imminent and multi-tenant or per-user rate limiting is required.**

Kuadrant + Authorino provides enterprise-grade authN/AuthZ, rate limiting, and DNS management for Kubernetes Gateway API. However, it introduces significant infrastructure complexity (additional CRDs, operator lifecycle, Redis for Limitador) that is not warranted for the current MVP phase. A simple API key middleware in ragorchestrator addresses the immediate security need with minimal overhead.

---

## Questions Addressed

### 1. Which Kuadrant version ships with OpenShift AI 3.4?

OpenShift AI 3.4 (RHOD 1.4) uses the upstream Kuadrant operator via Operator Lifecycle Manager (OLM). Kuadrant 0.25+ is the current stable release. Confirm via:

```bash
# Check available operators
oc get operators -A | grep kuadrant
# Or search OperatorHub
oc search operator kuadrant
```

### 2. How does Authorino validate API keys vs JWT vs OIDC?

Authorino supports multiple authentication methods via declarative `AuthConfig` CRs:

| Method | Use Case | How It Works |
|--------|----------|--------------|
| API Keys | Simple service-to-service auth | `spec.authentication.apiKeyAuth` — keys stored in Kubernetes Secret |
| JWT/OIDC | User authentication | `spec.authentication.jwtAuth` — validates RS256/ES256 signatures |
| mTLS | Pod-to-pod encryption | `spec.authentication.mtlsAuthentication` — cert-based |
| Kubernetes tokens | In-cluster workloads | `spec.authentication.kubernetesAuth` — TokenReview API |
| OPA Rego | Custom policies | `spec.authorization.rego` — arbitrary policy evaluation |

For ragorchestrator, API key auth via Authorino would work as follows:
1. Client passes `Authorization: Bearer <key>` header
2. Authorino intercepts at Envoy layer (before request reaches ragorchestrator)
3. Key validated against Kubernetes Secret
4. Metadata (tier, user-id) extracted and passed as x-ext-auth-* headers
5. Request forwarded to ragorchestrator with auth context

### 3. What changes in ragorchestrator when Kuadrant is in front of it?

**Ideally: nothing.** The auth middleware currently proposed for ragorchestrator (issue #20) would be bypassed or removed when Kuadrant is deployed. Authorino handles:
- API key validation
- Rate limiting (via Limitador)
- Auth metadata injection

ragorchestrator would receive auth context via HTTP headers and trust them (since they're validated at the Gateway layer).

**Practical reality:** Some middleware code would remain for:
- Parsing x-ext-auth-* headers for routing decisions
- Internal (non-Kuadrant) requests during development
- Fallback auth if Kuadrant is temporarily unavailable

### 4. How does the AgentGatewayPolicy model field extraction interact with ragorchestrator's routing?

Authorino's `AgentGatewayPolicy` is not a standard Kuadrant CR. The question likely refers to custom CRDs ragorchestrator might define for agent-specific routing policies. Key considerations:

- **If using Gateway API**: ragorchestrator routes are defined as HTTPRoute resources
- **Authorino AuthConfig** attaches to HTTPRoute via `spec.hosts` matching
- **Rate limits** defined via Kuadrant RateLimitPolicy CR, referencing the same HTTPRoute

The field extraction (e.g., extracting user tier from API key for rate limiting) would use Authorino's `metadata` feature:

```yaml
spec:
  authentication:
    apiKeyAuth:
      labelSelectors:
        tier: free
  metadata:
    - name: user-tier
      value: free
    - name: rate-limit
      value: "60"
```

### 5. What Kuadrant CRs are needed for a rag-suite deployment?

At minimum:

```yaml
# 1. Kuadrant Operator (Cluster-wide, once per cluster)
apiVersion: operator.kuadrant.io/v1
kind: Kuadrant
metadata:
  name: kuadrant
spec: {}

---
# 2. Authorino AuthConfig (per namespace)
apiVersion: operator.kuadrant.io/v1alpha1
kind: AuthConfig
metadata:
  name: ragorchestrator-auth
  namespace: rag-suite
spec:
  hosts:
    - ragorchestrator.rag-suite.svc
  authentication:
    apiKeyAuth:
      labelSelectors:
        app: ragorchestrator
      credentials:
        in: authorization_header
        keySelector: Bearer
  metadata:
    - name: user-id
      from: authn.metadata["sub"]
    - name: user-tier
      from: authn.metadata["tier"]

---
# 3. RateLimitPolicy (per namespace, requires Limitador)
apiVersion: kuadrant.io/v1beta3
kind: RateLimitPolicy
metadata:
  name: ragorchestrator-ratelimit
  namespace: rag-suite
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ragorchestrator
  limits:
    "60":
      conditions:
        - value: 
            - "60"
      units: minute
```

---

## Migration Guide: What to Add

### Kuadrant CRs (when migrating)

| CR | Purpose | Effort |
|----|---------|--------|
| Kuadrant operator | Lifecycle management | 1 day |
| Authorino AuthConfig | API key / JWT validation | 2 days |
| Limitador | Redis-backed rate limiting | 2 days |
| RateLimitPolicy | Per-route rate limits | 1 day |
| DNSRecord (optional) | Automatic DNS via Kuadrant DNS | 1 day |

**Estimated effort: 7 days** for initial deployment + 3 days for integration testing.

---

## What to Remove from ragorchestrator

When Kuadrant is deployed, the following should be removed or disabled:

| Component | Reason | Removal Effort |
|-----------|--------|----------------|
| API key auth middleware (issue #20) | Replaced by Authorino | 1 day (comment out) |
| Rate limiting middleware (issue #21) | Replaced by Limitador | 1 day (comment out) |
| Custom auth headers parsing | Replaced by x-ext-auth-* from Authorino | 2 days |

**Note:** Keep the middleware code (commented/feature-flagged) for local development where Kuadrant may not be available.

---

## What Stays the Same

These components are internal and unaffected by Kuadrant:

| Component | Why Unchanged |
|-----------|--------------|
| ragpipe (:8090) | Internal service, not exposed via Gateway |
| Qdrant | Internal, no external endpoint |
| Postgres | Internal, protected by network policy |
| ragstuffer (:8091, :8093) | Internal ingestion, not exposed |
| LiteLLM (:4000) | Internal model proxy |

---

## Estimated Effort for Full OpenShift AI Migration

| Phase | Work | Effort | Notes |
|-------|------|--------|-------|
| 1 | Deploy Kuadrant operator via OLM | 1 day | Cluster-admin required |
| 2 | Configure Authorino AuthConfig | 2 days | API key validation |
| 3 | Deploy Limitador + Redis | 2 days | Rate limiting backend |
| 4 | Migrate ragorchestrator middleware | 3 days | Remove app-layer auth |
| 5 | Integration testing | 3 days | E2E auth flows |
| 6 | DNS + TLS configuration | 2 days | Kuadrant DNS controller |

**Total: ~13 days** (2.5 weeks engineering time)

---

## Decision Matrix: When to Use Kuadrant vs. Simple Middleware

| Criteria | Simple Middleware (issue #20) | Kuadrant + Authorino |
|----------|------------------------------|---------------------|
| Deployment | Podman, Kubernetes | Kubernetes only |
| Multi-tenant | No (single API key) | Yes (per-user keys) |
| Rate limiting | In-memory, per-instance | Redis-backed, global |
| Per-user quotas | No | Yes |
| External access | Limited | Full |
| Operator complexity | None | Medium (OLM) |
| Redis dependency | No | Yes (Limitador) |
| Gateway API required | No | Yes |
| **Best for** | MVP, internal tools | Production, multi-tenant |

---

## References

- [Kuadrant Documentation](https://kuadrant.io/docs/)
- [Authorino GitHub](https://github.com/kuadrant/authorino)
- [Expand Model Service to Secure Enterprise AI](https://developers.redhat.com/articles/2025/07/17/expand-model-service-secure-enterprise-ai)
- [OpenShift AI 3.4 Release Notes](https://docs.openshift.com/ai/latest/release_notes.html)
- [Kuadrant RateLimitPolicy CRD](https://kuadrant.io/docs/ratelimiting/)
