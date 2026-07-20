# External Redis Only Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the chart-managed Redis/Valkey implementation while preserving optional external Redis and Sentinel wiring.

**Architecture:** `externalRedis.enabled` remains the sole opt-in for Redis environment configuration. Apollo renders a direct external `REDIS_URL` or the configured external Sentinel environment variables only when that flag is enabled; the chart otherwise emits no Redis connection variable or Redis workload.

**Tech Stack:** Helm templates, Helm values YAML, helm-unittest, Helm lint.

## Global Constraints

- Base the branch and PR on `release-stable`.
- Keep `externalRedis.enabled` defaulting to `false`.
- When `externalRedis.enabled` is false, do not populate `REDIS_URL`.
- Do not modify historical packaged release artifacts or archived documentation.
- Remove all active chart-managed Redis/Valkey sources, not external Redis/Sentinel support.

---

### Task 1: Define the external-only rendering contract

**Files:**
- Modify: `composio/tests/apollo_test.yaml`
- Modify: `composio/tests/helpers_test.yaml`
- Modify: `composio/tests/pod_disruption_budget_test.yaml`
- Modify: `composio/tests/test-values.yaml`
- Delete: `composio/tests/redis_test.yaml`

**Interfaces:**
- Consumes: `externalRedis.enabled`, `externalRedis.secretRef`, `externalRedis.key`, and optional `externalRedis.sentinel` values.
- Produces: tests proving disabled external Redis emits no Redis variables and enabled direct/Sentinel configurations retain their current environment contract.

- [x] **Step 1: Add the failing disabled-external-Redis assertion**

Add this case to `composio/tests/apollo_test.yaml` before the direct external Redis case:

```yaml
  - it: should not configure Redis when external Redis is disabled
    documentSelector:
      path: kind
      value: Deployment
    set:
      externalRedis.enabled: false
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: REDIS_URL
          any: true
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: REDIS_SENTINEL_HOSTS
          any: true
```

Remove the obsolete bundled-Redis Sentinel failure case and every test-only
`redis.enabled` setting. Keep the existing direct external Redis and Sentinel
assertions, but remove their `redis.enabled: false` settings.

- [x] **Step 2: Run the focused test to verify it fails**

Run from `composio/`: `helm unittest . -f tests/apollo_test.yaml`

Expected: FAIL because the current default embedded Redis path emits `REDIS_URL`.

### Task 2: Delete the chart-managed Redis implementation

**Files:**
- Modify: `composio/values.yaml`
- Modify: `composio/templates/apollo/apollo.yaml`
- Modify: `composio/templates/_helpers.tpl`
- Modify: `composio/templates/NOTES.txt`
- Delete: `composio/templates/redis/secret.yaml`
- Delete: `composio/templates/redis/service.yaml`
- Delete: `composio/templates/redis/statefulset.yaml`
- Delete: `composio/charts/.helm_ls_cache/redis/values.yaml`
- Delete: `composio/tmp-redis/preflight-redis.yaml`

**Interfaces:**
- Consumes: Task 1’s external-only Apollo assertions.
- Produces: a chart with no `redis` values, helper, template, bundled image, service, StatefulSet, or Secret.

- [x] **Step 1: Remove the embedded Redis values and templates**

Delete the complete `redis:` mapping in `composio/values.yaml` and delete the
three `composio/templates/redis/` files plus the tracked Redis cache/scratch
artifacts. Do not change the `externalRedis:` mapping.

- [x] **Step 2: Simplify Apollo and validation logic**

In `composio/templates/apollo/apollo.yaml`, remove the `$redisValues`,
`$redisSentinel`, `$redisSentinelService`, `$redisSentinelServicePorts`,
`$redisTls`, `$redisAuth`, and `$internalRedisSentinelEnabled` variables;
remove the mutual-exclusion, neither-source, bundled Sentinel, and bundled TLS
`fail` blocks; and delete the internal Sentinel/URL environment branch. Leave
only the existing external Sentinel branch followed by the
`else if $externalRedis.enabled` direct `REDIS_URL` branch.

Delete `composio.redis.fullname`, remove the Redis validation call and helper
from `_helpers.tpl`, and remove the bundled-cache password notice from
`NOTES.txt`.

- [x] **Step 3: Run focused tests to verify the green state**

Run from `composio/`:

```bash
helm unittest . -f tests/apollo_test.yaml
helm unittest . -f tests/helpers_test.yaml
helm unittest . -f tests/pod_disruption_budget_test.yaml
```

Expected: PASS with no test values relying on `redis.*`.

### Task 3: Remove active bundled-Redis documentation

**Files:**
- Modify: `composio/README.md`
- Modify: `docs/redis-sentinel.md`
- Modify: `docs/configuration.html`
- Modify: `docs/guides.html`
- Modify: `docs/migrate-to-replicated/example-override.yaml`
- Modify: `docs/migrate-to-replicated/override.yaml`
- Modify: `docs/prerequisites/compute.md`
- Modify: `overwrite-values.yaml`

**Interfaces:**
- Consumes: external Redis and Sentinel values retained in Task 2.
- Produces: current user-facing instructions that never advise `redis.enabled`
  or claim the chart bundles a Redis-compatible cache.

- [x] **Step 1: Update configuration examples and reference tables**

Remove all `redis.enabled: false` example blocks. Replace statements that
describe an internal/bundled cache with external Redis requirements. In
`composio/README.md`, remove every `redis.*` table row and the internal Redis
password/upgrade section while retaining the direct and Sentinel external
examples. In `docs/configuration.html`, remove bundled-cache rows/examples and
state that `externalRedis.enabled` controls optional external injection.

- [x] **Step 2: Update operational guides**

Remove the bundled-cache limitation and bundled-only common mistakes from
`docs/redis-sentinel.md`; delete the “leave empty to use bundled Redis” text
from `docs/guides.html`; replace the internal Redis resource section in
`docs/prerequisites/compute.md` with an external Redis sizing responsibility;
and update the root and migration override comments to describe external Redis
without an internal fallback.

### Task 4: Verify and commit the chart change

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-external-redis-only.md`

**Interfaces:**
- Consumes: the chart changes from Tasks 1–3.
- Produces: a linted, fully rendered external-only chart and a clean commit.

- [x] **Step 1: Run full chart verification**

Run from `composio/`:

```bash
helm unittest . -f 'tests/*_test.yaml'
helm lint .
helm template composio . --debug > /tmp/composio-external-redis-only.yaml
```

Then confirm no bundled resources or stale active source references remain:

```bash
rg -n 'redis\.enabled|\.Values\.redis|composio\.redis|bundled Redis|internal Redis|Valkey' \
  composio docs overwrite-values.yaml \
  --glob '!composio/charts/**' \
  --glob '!archive/**'
```

Expected: the render succeeds, all Helm unit tests pass, and the search has no
matches except external Redis protocol references that do not describe an
embedded chart component.

- [x] **Step 2: Inspect and commit**

Run: `git diff --check && git status --short`

Commit the verified implementation with:

```bash
git add composio docs overwrite-values.yaml
git commit -m "feat: remove bundled Redis from chart"
```
