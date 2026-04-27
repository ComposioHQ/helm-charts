# AGENTS.md — Composio Helm Charts

Guide for AI agents (Claude, Codex, etc.) and human contributors working in this repository. Companion to `claude.md` (which already exists and overlaps); this file is the authoritative onboarding doc.

## What this repo is

Helm charts for deploying the **Composio platform** — a multi-service backend that connects LLMs to 500+ third-party tools — onto Kubernetes. The published chart powers Composio's on-prem / self-hosted offering and is also distributed via Replicated for the SaaS-managed enterprise install.

- Repo: `https://github.com/ComposioHQ/helm-charts`
- Default branch (GitHub `HEAD`): `release-stable` — this is also the branch every doc URL in `README.md` links to. There is no `master` branch; commit history that looks like "main development" still flows through `release-stable`.
- Helm repo (GitHub Pages): `https://composiohq.github.io/helm-charts/`
- Enterprise portal: `https://enterprise.composio.io/composio-rodent`
- Replicated app slug: `composio-rodent`
- Architecture diagram: `docs/architecture/composio_architecture.png`

## Top-level layout

```
helm-charts/
├── composio/                  # The main Helm chart (only chart in the repo)
│   ├── Chart.yaml             # name=composio, version=0.1.110, appVersion=0.1.110
│   ├── Chart.lock             # Locked subchart versions
│   ├── values.yaml            # ~1.4k lines, full default config
│   ├── README.md              # Chart-level README
│   ├── run-tests.sh           # helm-unittest runner (auto-installs plugin)
│   ├── templates/             # 36 K8s template files across 8 service dirs
│   ├── tests/                 # 19 helm-unittest test files
│   ├── charts/                # Bundled subcharts (redis, temporal, replicated)
│   └── tmp-redis/             # Scratch/dev artifacts (not user-facing)
├── docs/                      # GitHub Pages site (CNAME, _config.yml, .html, .md)
│   ├── architecture/          # Architecture diagram + python source
│   ├── monitoring/alerts/     # Datadog alert setup
│   ├── post-installation/     # OTEL config etc.
│   ├── prerequisites/         # Compute sizing
│   ├── upgradation/           # Upgrade guides
│   ├── migrate-to-replicated/ # Migration from raw Helm to Replicated
│   ├── azure-blob-storage.md  # Object store config
│   ├── gcs-s3-storage.md
│   ├── frontend-setup.md
│   ├── smtp-setup.md
│   └── redis-sentinel.md
├── manifests/                 # Replicated/KOTS app manifests
│   ├── composio.yaml          # KOTS HelmChart resource (pins chartVersion)
│   ├── replicated-app.yaml    # KOTS Application
│   ├── k8s-app.yaml           # KOTS k8s app
│   ├── embedded-cluster.yaml  # Replicated embedded-cluster spec
│   ├── config.yaml            # KOTS config
│   └── composio-0.1.40.tgz    # Pinned chart artifact for Replicated
├── helm-release/              # Packaged chart artifacts served via GitHub Pages
│   └── composio-*.tgz
├── archive/                   # Historical examples (configuration, installation, secret-setup.sh)
├── overwrite-values.yaml      # Annotated example of common production overrides
├── temporal-workflow-metrics.md  # Runbook for Temporal worker metrics
├── index.yaml                 # Helm repository index (served from gh-pages)
├── claude.md                  # Older agent-focused doc (kept; values may drift)
├── README.md                  # User-facing entry point (links to docs)
└── .github/workflows/         # CI / nightly release / changelog / secret scan
```

## Architecture being deployed

The chart deploys a microservices stack. Service-to-service ports below are the in-chart container ports.

| Service   | Lang / Framework | Port | Purpose                                                     |
|-----------|------------------|------|-------------------------------------------------------------|
| Apollo    | TS (Next.js + Hono) | 9900 | Main API gateway: auth, CRUD, routing, search, file storage |
| Thermos   | Go               | 8180 | Tool execution orchestration, trigger processing            |
| Mercury   | Python (Lambda-style) | 8080 | Executes tool code against third-party APIs                 |
| Frontend  | TS (Next.js)     | 3000 | Web UI                                                      |
| Temporal  | (subchart)       | 7233 | Workflow engine for trigger processing & auth-token refresh |
| Redis     | (Bitnami subchart) | 6379 | Caching layer                                               |
| Weaviate  | (in-chart)       | —    | Optional vector DB; usually disabled in prod                |

`docs/architecture/composio_architecture.png` shows the full picture. Source code for each service lives in separate repos (hermes for Apollo+Thermos, mercury, etc.) — this repo only ships the K8s packaging.

## Deployment modes

The same chart supports three modes, toggled via values:

1. **Replicated SaaS / KOTS** — `replicated.enabled: true`. **This is the shipped default** in `composio/values.yaml` (and the mode `chart.registry` rewrites image URLs for via the `artifacts.composio.io` proxy). Uses `manifests/composio.yaml` (KOTS HelmChart) and `templates/replicated/` for the pull secret. Embedded-cluster install via `manifests/embedded-cluster.yaml`.
2. **Standard Kubernetes** — set `replicated.enabled: false` to render vanilla Deployments/Services with the raw ECR registry under `global.registry.name`. Most production overrides do this (see `overwrite-values.yaml`).
3. **Knative serverless** — set `mercury.useKnative: true` (and the `knative:` block). Renders Knative Services + CRDs from `templates/knative/`. Orthogonal to the Replicated/standard split.

Optional features are gated by the `features:` block. `features.temporal: true` enables the Temporal subchart but does **not** by itself deploy the Thermos misc-worker pod that runs trigger / auth-refresh logic — that requires `thermosMiscWorkers.enabled: true` in addition.

## Templates: where to look

Each service has its own subdirectory under `composio/templates/`. Common files per service: `<service>.yaml` (Deployment + Service), `<service>-configmap.yaml`, `<service>-ingress.yaml`, `service-account.yaml`.

```
templates/
├── _helpers.tpl                # Shared template functions (registry, secret names, labels)
├── NOTES.txt                   # Post-install hints
├── ecr-secret.yaml             # Image pull secret from externalSecrets.ecr.*
├── otel-collector.yaml         # OpenTelemetry collector
├── poddisruptionbudgets.yaml   # Optional PDBs (added in v0.1.x)
├── apollo/                     # apollo.yaml, apollo-configmap.yaml, apollo-db-init.job.yaml,
│                               # apollo-ingress.yaml, service-account.yaml
├── thermos/                    # thermos.yaml, thermos-config.yaml, thermos-db-init-job.yaml,
│                               # thermos-misc-workers.yaml, toolkit-registry.yaml, service-account.yaml
├── mercury/                    # mercury.yaml, mercury-configmap.yaml, mercury-ingress.yaml,
│                               # mercury-service.yaml, service-account.yaml
├── frontend/                   # frontend.yaml, frontend-configmap.yaml, frontend-ingress.yaml,
│                               # service-account.yaml
├── database/                   # postgres-init-job.yaml (creates app DBs in an external Postgres)
├── knative/                    # knative-serving.yaml, knative-crds.yaml
├── weaviate/                   # weaviate.yaml, service-account.yaml
├── replicated/                 # replicated-pull-secret.yaml
└── preflight-checks/           # preflight-config.yaml + DB / S3 / Azure / OpenAI / SMTP probes
```

`Thermos` has two non-obvious bits:

- `thermos-misc-workers.yaml` — runs Thermos in `THERMOS_MODE=miscellaneous_worker` (trigger / auth-refresh logic). Gated by its own toggle `thermosMiscWorkers.enabled` (default `false`); `features.temporal` is a separate switch and does **not** turn the misc workers on by itself.
- `toolkit-registry.yaml` — sidecar/companion deployment used by on-prem Thermos for toolkit discovery (default-on as of `910cb20`).

## Values.yaml: top-level keys

`composio/values.yaml` is the single source of truth (~1392 lines). Top-level blocks, in roughly the order they appear:

- `features.*` — feature toggles (currently `temporal`).
- `secret.name` — name of the external Secret holding all platform credentials.
- `namespace.{create,name}` — whether the chart creates its own namespace.
- `replicated.{enabled,registry,app}` — Replicated mode + custom registry domain.
- `global.{environment,domain,registry,imagePullSecrets,disableK8SecretCheck}` — applied to every deployment.
- `databaseMigration.*` — one-shot Postgres init job (creates `apollo`, `thermos`, `mercury`, `temporal` databases).
- `externalSecrets.ecr.*` — values used to render the ECR auth Secret at install time (`--set externalSecrets.ecr.token=...`).
- `externalRedis.*` — production Redis (incl. Sentinel options); set `externalRedis.enabled: true` and `redis.enabled: false` for prod.
- `redis.*` — embedded Bitnami Redis (dev only).
- `apollo.*`, `thermos.*`, `mercury.*`, `frontend.*`, `weaviate.*` — per-service config (image, replicas, resources, ingress, service account, env, probes, PDB).
- `temporal.*` — passthrough to the Temporal subchart when `features.temporal: true`.
- `otel.*` — OpenTelemetry collector config.
- `*.knative` — Knative-mode overrides (only relevant when `mercury.useKnative: true`).

Always-true conventions:

- Image references are rendered via `{{ include "chart.registry" . }}/{{ .Values.<svc>.image.repository }}:{{ .Values.<svc>.image.tag }}`.
- Resource names use `{{ .Release.Name }}-<service>` (e.g. `composio-apollo`).
- Sensitive values come from `secret.name` (default `composio-composio-secrets`) via `valueFrom.secretKeyRef`. Never hardcode secrets.
- Conditional rendering: optional services and feature blocks are gated by `{{- if .Values.<thing>.enabled }}` (e.g. `weaviate.enabled`, `redis.enabled`, `mercury.enabled`, `frontend.enabled`, `thermosMiscWorkers.enabled`, `databaseMigration.enabled`). The core services `apollo` and `thermos` do **not** have a top-level `enabled` field — their main templates render unconditionally and there is no supported way to disable them via values.

`overwrite-values.yaml` at the repo root is an annotated example of the most common production tweaks (external DB, disabling Weaviate, Temporal config, etc.). Consult it before adding new config knobs.

## Local development workflow

Prerequisites:

- Helm 3 (CI uses `v3.14.4`)
- `helm-unittest` plugin (`run-tests.sh` auto-installs it; CI pins `0.7.2`)
- `chart-testing` (`ct`) for lint, only needed if reproducing CI exactly

Common commands (all run from the repo root unless noted):

```bash
# Lint + render
helm lint composio/
helm dependency update composio/
helm template my-release composio/ --debug

# Unit tests (helm-unittest)
cd composio
./run-tests.sh                   # all
./run-tests.sh apollo            # one service
./run-tests.sh thermos
./run-tests.sh mercury
./run-tests.sh verbose           # -v
./run-tests.sh debug
./run-tests.sh with-subchart     # include bundled charts

# Direct equivalents
helm unittest . -f 'tests/*_test.yaml'
helm unittest . -f 'tests/apollo_test.yaml'

# chart-testing lint (matches CI)
ct lint --check-version-increment=false --target-branch release-stable
```

Installing into a real cluster:

```bash
# Default (dev) values
helm install composio composio/ -n composio --create-namespace

# Custom values
helm install composio composio/ -f my-values.yaml -n composio

# Upgrade
helm upgrade composio composio/ -f my-values.yaml -n composio

# ECR auth at install time
helm install composio composio/ \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  -n composio --create-namespace
```

## Tests: structure and conventions

`composio/tests/` contains 19 `*_test.yaml` files driven by `helm-unittest`. Conventions:

- One test file per template/service: `apollo_test.yaml`, `thermos_test.yaml`, `mercury_test.yaml`, `frontend_test.yaml`, etc.
- Cross-cutting suites: `helpers_test.yaml`, `ingress_test.yaml`, `pod_disruption_budget_test.yaml`, `preflight_test.yaml`, `secret_stripping_test.yaml`, `service_account_test.yaml`.
- `tests/test-values.yaml` holds shared values used across suites.
- Each test typically uses `set:` to override a small subset of values, then asserts `isKind`, `equal` on a `path`, or `hasDocuments` for conditional rendering.
- When changing a template, update or add tests in the matching `*_test.yaml`. Cover both `enabled: true` and `enabled: false` paths.

Skeleton:

```yaml
suite: apollo deployment tests
templates:
  - apollo/apollo.yaml
tests:
  - it: should create deployment when enabled
    set:
      apollo.enabled: true
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: metadata.name
          value: RELEASE-NAME-apollo
```

## CI / CD

GitHub Actions in `.github/workflows/`:

| Workflow                              | Trigger                                                 | What it does |
|---------------------------------------|---------------------------------------------------------|--------------|
| `ci.yaml`                             | `pull_request`                                          | `ct lint`, `helm template --dry-run`, `helm unittest` |
| `secrets-detection.yml`               | PRs                                                     | Gitleaks scan |
| `nighty-release.yml`                  | Cron (18:30 UTC) + `workflow_dispatch`                  | Retags ECR images, bumps chart version, opens nightly release PR, kicks off on-prem trigger tests |
| `nightly-onprem-trigger-tests.yml`    | `pull_request_target` (label `nightly-release` or open) | Resolves a Replicated release and runs on-prem trigger E2E tests |
| `generate-release-changelog.yml`      | `workflow_dispatch`                                     | Diffs two chart versions / OCI refs and writes a Markdown changelog |

Key invariants enforced by CI:

- Templates must render with `helm template --debug --dry-run` against default values.
- `helm-unittest` suite must pass.
- Subchart deps (`bitnami`, `temporal`) are added before lint.
- `--check-version-increment=false` is passed to `ct lint`, so the chart version is **not** auto-bumped — bump `composio/Chart.yaml` explicitly when a release is intended.

## Release & distribution

The chart is published two ways:

1. **GitHub Pages Helm repo** — packaged `.tgz` files land in `helm-release/` and `index.yaml` is regenerated. Hosted at `https://composiohq.github.io/helm-charts/`. Older PR `helm-release.yaml` automation is referenced in `claude.md`; verify the live workflow before relying on it.
2. **Replicated** — `manifests/composio.yaml` is a KOTS `HelmChart` resource that pins `spec.chart.chartVersion` (currently `0.1.110`). KOTS resolves the chart by `name` + `chartVersion`; the manifest does **not** reference a specific `.tgz` filename. The `manifests/composio-*.tgz` you see committed alongside it (e.g. `composio-0.1.40.tgz`) is a historical/seed artifact and is not regenerated on every chart bump — the actual chart artifact for a Replicated release is produced by the release pipeline (`nighty-release.yml` → Replicated registry).

Versions to bump when cutting a release:

- `composio/Chart.yaml` → `version` and `appVersion`
- `manifests/composio.yaml` → `spec.chart.chartVersion`

Image tags used by the nightly release flow are inputs to `nighty-release.yml` (apollo, apollo-db-init, thermos, thermos-db-init, mercury, frontend, weaviate, thermos-toolkit-registry — all default `latest`).

## Common workflows for agents

### Adding a new service

1. Create `composio/templates/<service>/` with at minimum `<service>.yaml`, `<service>-configmap.yaml`, and a service-account if needed.
2. Add a `<service>:` block to `values.yaml` with `enabled`, `image`, `replicaCount`, `resources`, `service`, `ingress`, `serviceAccount`. Document each option with the `# --` helm-docs marker (the existing values use `# --`, not `##`); plain `##` comments are dropped by `helm-docs` and won't appear in the generated table in `composio/README.md`.
3. Gate every template with `{{- if .Values.<service>.enabled }} ... {{- end }}` if the service is meant to be optional. (Note: the existing core services `apollo` and `thermos` are intentionally *not* gated — don't follow them as the pattern for a new optional service.)
4. Add helpers to `_helpers.tpl` if you need shared name/label logic.
5. Create `composio/tests/<service>_test.yaml` covering enabled/disabled, default image, custom resources, ingress on/off.
6. Run `helm unittest . -f tests/<service>_test.yaml -v` (the `run-tests.sh` shortcut only knows about hardcoded targets — `apollo`, `mercury`, `thermos`, `minio`, `knative`, `helpers`, `secrets`, `db`, `ingress` — so add a new `case` arm to the script if you want a friendly alias) and `helm template . --debug` before opening a PR.

### Modifying an existing service

1. Read the template + the matching `<service>:` block in `values.yaml`.
2. If you add a new value, default it conservatively (don't change behavior for existing installs without a values change).
3. Update the matching `tests/<service>_test.yaml`.
4. Run lint, render, and tests locally.
5. Bump `composio/Chart.yaml` only if the change is user-visible enough to warrant a release.

### Updating a subchart

```bash
cd composio
# edit Chart.yaml dependencies
helm dependency update
git add Chart.yaml Chart.lock charts/
```

`composio/charts/` already contains pre-fetched `redis-17.11.3.tgz`, `temporal-0.68.1.tgz`, and `replicated-1.18.1.tgz` — re-vendor them when bumping versions.

### Touching secrets

- Default secret name: `composio-composio-secrets` (`secret.name`).
- ECR pull secret is rendered from `externalSecrets.ecr.{token,server,username}` into `templates/ecr-secret.yaml` (or pulled from Replicated when in that mode).
- Database credentials, API keys (OpenAI, Composio), JWT secrets, encryption keys all flow through `secret.name`. Never inline secrets in values files.
- `tests/secret_stripping_test.yaml` enforces that secrets aren't accidentally rendered into ConfigMaps. Keep it green.

## Branch / PR conventions

- Open PRs against `release-stable` (the actual default branch on GitHub). Recent merged PRs (#251, #249, #248, #244, #241) all targeted `release-stable`. The `master` branch referenced in older docs and `claude.md` does not exist.
- Nightly release automation in `nighty-release.yml` opens its own PRs against `release-stable`.
- Conventional-commit style titles are used in history (`feat:`, `fix:`, `chore:`). Match the surrounding style.
- Required PR description sections used by other Composio repos (`# Description`, `# How did I test this PR`) are not enforced here, but are recommended.
- PRs labeled `nightly-release` trigger the on-prem trigger tests.

## Gotchas worth remembering

- **Versions in `claude.md` may drift.** It still references chart `0.1.33` while `Chart.yaml` is `0.1.110`. Trust `Chart.yaml`.
- **`overwrite-values.yaml` ≠ `composio/values.yaml`.** The root file is a documented production override example, not the chart's defaults.
- **`composio/tmp-redis/`** is dev scratch; don't add tests or docs that depend on it.
- **`archive/`** holds older `example-values.yaml` and `secret-setup.sh` — useful as historical reference but not the canonical entrypoint.
- **Embedded Redis (`redis.enabled: true`)** is dev-only. Production must use `externalRedis.enabled: true` (Sentinel optional).
- **`features.temporal: true` requires `temporal.server.enabled: true`** plus a SQL persistence config (see `overwrite-values.yaml`).
- **Knative mode pulls in CRDs** from `templates/knative/knative-crds.yaml`. Cluster must allow CRD installs.
- **Weaviate is opt-out**: most production overrides set `weaviate.enabled: false`.
- **`docs/` is GitHub Pages**, not generated. Edits to `.md`/`.html` files there ship to the public site (`composiohq.github.io/helm-charts`). Treat changes as user-facing copy.
- **No Go/Node/Python source here.** All application changes live in the upstream service repos (hermes, mercury, etc.).

## Quick reference

```bash
# Render the chart with the production override example
helm template composio composio/ -f overwrite-values.yaml --debug | less

# Run a single test suite
cd composio && helm unittest . -f tests/apollo_test.yaml -v

# Reproduce the CI lint locally
ct lint --check-version-increment=false --target-branch release-stable

# Package the chart locally (mirrors what release jobs do)
helm package composio/ -d helm-release/
helm repo index . --url https://composiohq.github.io/helm-charts
```

## Related docs in this repo

- `README.md` — public entrypoint, links to enterprise portal and docs.
- `claude.md` — earlier agent-onboarding doc (overlaps with this file).
- `temporal-workflow-metrics.md` — Temporal worker metric runbook.
- `docs/architecture/README.md` — architecture diagram details.
- `docs/migrate-to-replicated/README.md` — migration guide for moving an existing Helm install to Replicated.
- `docs/post-installation/index.md` — OTEL config and post-install steps.
- `docs/upgradation/index.md` — upgrade guidance.
- `composio/tests/README.md` — test suite reference.
