# External Redis Only Chart Design

## Goal

Remove the chart-managed Redis/Valkey implementation from the Composio Helm
chart. Redis configuration, when requested, is supplied only through the
existing external Redis Secret contract.

## Runtime Contract

`externalRedis.enabled` remains optional and defaults to `false`.

- When it is `true`, Apollo receives either `REDIS_URL` from
  `externalRedis.secretRef` / `externalRedis.key`, or the configured external
  Sentinel environment variables.
- When it is `false`, the chart does not render a Redis connection environment
  variable.
- The chart has no embedded Redis/Valkey workload, service, password Secret,
  values block, or internal fallback path.

## Chart Changes

- Delete the Redis templates and their helm-unittest suite.
- Delete the top-level `redis` values block, Redis helper, and validation for
  the former embedded implementation.
- Simplify Apollo to use only the existing external Redis and external Sentinel
  branches. Preserve the current `externalRedis.enabled` guard so no
  `REDIS_URL` is populated when the option is not enabled.
- Remove the tracked Redis development cache and scratch preflight artifact.
- Update current README and documented override examples to remove
  `redis.enabled: false` and claims that the chart includes an internal cache.
  Historical packaged releases and archived historical documentation are out
  of scope because they describe artifacts already released.

## Validation

Helm unit tests will prove that Apollo injects `REDIS_URL` only when external
Redis is enabled and that the default render contains no Redis workload. Run
the chart's Helm unit tests, lint, and a default `helm template` render.
