# Claude.md - Composio Helm Charts

> See also `AGENTS.md` — the longer, authoritative onboarding doc. This file is the
> condensed version; keep the two consistent when either drifts.

## Project Overview

This repository contains the Helm chart for deploying the Composio platform on Kubernetes.
The single chart (`composio/`) orchestrates a multi-service microservices architecture with
support for Replicated/KOTS (the shipped default), standard Kubernetes, and Knative
serverless deployments. No application source code lives here — only the K8s packaging.

## Tech Stack

- **Helm 3** - Kubernetes package manager
- **Kubernetes** - Container orchestration
- **GitHub Actions** - CI/CD automation
- **helm-unittest** - Chart testing framework
- **Replicated / KOTS** - Enterprise distribution platform
- **Knative** - Serverless deployment option (Mercury)
- **Grype** - Container CVE scanning in CI

## Repository Structure

```
helm-charts/
├── composio/                   # The only Helm chart in the repo (v0.2.13)
│   ├── Chart.yaml              # Chart metadata and dependencies
│   ├── Chart.lock              # Locked subchart versions
│   ├── values.yaml             # Default configuration (~1,384 lines)
│   ├── README.md               # Chart-level README
│   ├── run-tests.sh            # helm-unittest runner (auto-installs the plugin)
│   ├── scripts/                # lint_pod_scheduling.py (run by CI)
│   ├── templates/              # Kubernetes manifests (38 files across 9 dirs)
│   │   ├── _helpers.tpl        # Shared template functions
│   │   ├── apollo/             # Main API service
│   │   ├── thermos/            # Tool execution, misc workers, toolkit registry
│   │   ├── mercury/            # Function/tool-code execution
│   │   ├── frontend/           # Web UI (Next.js)
│   │   ├── database/           # Postgres init job
│   │   ├── knative/            # Serverless support
│   │   ├── weaviate/           # Optional vector DB
│   │   ├── replicated/         # Replicated pull secret
│   │   └── preflight-checks/   # DB / S3 / Azure / OpenAI / SMTP probes
│   ├── tests/                  # helm-unittest suites (21 *_test.yaml + test-values.yaml)
│   └── charts/                 # Bundled subcharts (temporal, replicated)
├── docs/                       # GitHub Pages documentation site
├── manifests/                  # Replicated / KOTS app manifests
├── helm-release/               # Packaged chart .tgz artifacts served via Pages
├── archive/                    # Historical examples (incl. example-values.yaml)
├── .github/
│   ├── workflows/              # CI, nightly release, CVE scans, changelog
│   ├── actions/slack-notify/   # Composite action used by the report workflows
│   └── scripts/                # CVE tooling + its tests
├── AGENTS.md                   # Authoritative onboarding doc
├── overwrite-values.yaml       # Annotated production override example
└── index.yaml                  # Helm repository index
```

## Core Services

| Service | Port | Purpose |
|---------|------|---------|
| **Apollo** | 9900 | Main API gateway: auth, CRUD, routing, storage, search |
| **Thermos** | 8180 | Tool execution orchestration, trigger processing |
| **Mercury** | 8080 | Executes tool code against third-party APIs (Knative-capable) |
| **Frontend** | 3000 | Next.js web UI (`frontend.enabled`, default `false`) |
| **Temporal** | 7233 | Workflow engine subchart (`features.temporal`, default `false`) |
| **Toolkit Registry** | 5432 | Read-only Postgres image of the toolkit catalog, queried by Thermos |
| **Weaviate** | 8080 / 50051 | Optional vector DB (`weaviate.enabled`, default `true`) |

**Redis is not deployed by this chart.** It must be supplied externally and is wired in via
the `externalRedis` block (plain URL or Sentinel mode). See `docs/redis-sentinel.md`.

Postgres is likewise external; the chart only ships init/migration jobs against it.

## Development Commands

### Linting and Validation

```bash
# Lint the chart
helm lint composio/

# Template validation (dry-run) — must run from inside composio/
cd composio && helm dependency update && helm template . --debug --dry-run

# Pod scheduling lint (same check CI runs)
python3 composio/scripts/lint_pod_scheduling.py
```

### Testing

```bash
cd composio/

# Run all tests
./run-tests.sh

# Run specific suites
./run-tests.sh apollo
./run-tests.sh mercury
./run-tests.sh thermos
./run-tests.sh knative
./run-tests.sh helpers
./run-tests.sh secrets     # ecr_secret_test.yaml
./run-tests.sh db          # db_init_test.yaml
./run-tests.sh ingress

# Verbose/debug modes
./run-tests.sh verbose
./run-tests.sh debug

# Include subchart tests
./run-tests.sh with-subchart
```

The script auto-installs the `helm-unittest` plugin if it is missing. Note the `minio`
target still exists in the script but its test file was removed.

### Installation

```bash
# Install with default values
helm install composio composio/ -n composio --create-namespace

# Install with custom values
helm install composio composio/ -f my-values.yaml -n composio

# Upgrade existing release
helm upgrade composio composio/ -f my-values.yaml -n composio
```

## Key Configuration Patterns

### Values.yaml Structure

Note that Apollo and Thermos have **no `enabled` toggle** — they are always rendered.
The blocks that do gate on `enabled` are `mercury` (default `true`), `weaviate` (`true`),
`replicated` (`true`), and — all defaulting to `false` — `frontend`, `otel`,
`databaseMigration`, `thermosMiscWorkers`, `externalRedis`, `openAI`, `ingress`,
`prometheus`, `grafana`, `testFramework`, `elasticsearch` and `cassandra`.
(The last five are legacy/monitoring passthroughs and deploy nothing from this chart.)

```yaml
apollo:
  replicaCount: 2
  image:
    repository: composio-self-host/apollo   # rewritten by chart.registry per mode
    tag: "r20260501_01"                     # date-stamped release tags, not "latest"
    pullPolicy: Always
    imageName: ""                           # full override; wins over repository
  service:
    type: NodePort
    port: 9900
    nodePort: 30900
  resources:
    requests:
      cpu: "1"
      memory: "5Gi"
    limits:
      cpu: "1"
      memory: "6Gi"
  ingress:
    enabled: false
  podDisruptionBudget:
    enabled: false
    maxUnavailable: 1
```

Feature gates live in the top-level `features:` block. `features.temporal` deploys the
Temporal subchart but does **not** by itself start the Thermos trigger/auth-refresh
workers — that needs `thermosMiscWorkers.enabled: true` as well.

### Template Patterns

1. **Conditional rendering**: `{{- if .Values.<service>.enabled }}`
2. **Image reference**: `{{ include "composio.imageReference" (dict "image" .Values.<service>.image "context" .) }}`
3. **Resource naming**: `{{ include "composio.fullname" . }}-<service>`
4. **Secret references**: use `valueFrom.secretKeyRef`, usually via `getSecretCred`

### Helper Functions (composio/templates/_helpers.tpl)

Naming/labels: `composio.name`, `composio.fullname`, `composio.chart`, `composio.labels`,
`composio.selectorLabels`, per-service `composio.apollo.*` / `composio.thermos.*` /
`composio.dbInit.*`, `composio.namespace`, `composio.serviceAccountName`,
`composio.podDisruptionBudget`.

Images/registry: `chart.registry`, `composio.image`, `composio.imageReference`,
`composio.imagePullSecrets`, `replicated.imagePullSecrets`.

Secrets: `composio.coreSecretName`, `getSecretCred`, and the token helpers
`composio-admin-token`, `encryption-key`, `jwt-secret`, `temporal-encryption-key`.

Temporal/Thermos: `composio.temporalEnabled`, `composio.temporal.fullname`,
`composio.temporal.frontendAddress`, `composio.temporalNamespaceWaitInitContainer`,
`composio.thermosWorkerDb*`, `composio.toolkitRegistryDbUrl`.

Validation/util: `composio.validateValues`, `composio.validateValues.database`,
`composio.uriComponent`, `composio.shellQuote`, `hash`, and the `apollo.parseSmtpUrl` /
`apollo.smtp*` family.

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yaml` | Pull requests | `ct lint`, `helm template`, pod-scheduling lint, helm-unittest |
| `nighty-release.yml` | Nightly cron + manual | Cut a release and push it to a Replicated channel |
| `grype-cve-scan.yml` | `workflow_call` | Render the chart and Grype-scan every image |
| `released-cve-audit.yml` | Daily cron + manual | Re-scan already-published Replicated releases |
| `nightly-onprem-trigger-tests.yml` | `pull_request_target` | On-prem trigger integration tests |
| `generate-release-changelog.yml` | Manual | Diff two chart versions into a changelog |
| `secrets-detection.yml` | PRs | Gitleaks secret scanning (reports to `buzz-security`) |

`nighty-release.yml` and `released-cve-audit.yml` post their reports to Slack via the
`.github/actions/slack-notify` composite action. `grype-cve-scan.yml` is called by them
rather than notifying on its own.

## Writing Tests

Tests use the `helm-unittest` plugin. Location: `composio/tests/`.

```yaml
# Example test structure
suite: apollo deployment tests
templates:
  - apollo/apollo.yaml     # template paths are the real filenames
tests:
  - it: should create the apollo deployment
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: metadata.name
          value: RELEASE-NAME-apollo
```

### Test Conventions

- One test file per template/service: `<service>_test.yaml`
- Use `set:` blocks to override values per test
- Test both enabled and disabled states (for services that have an `enabled` flag)
- Verify resource limits, health checks, security contexts
- Use `hasDocuments: count:` for conditional rendering tests

## Important Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Full onboarding doc — read this first |
| `composio/Chart.yaml` | Chart version, dependencies |
| `composio/values.yaml` | All configurable options |
| `composio/templates/_helpers.tpl` | Shared template functions |
| `composio/scripts/lint_pod_scheduling.py` | Affinity/tolerations lint enforced by CI |
| `overwrite-values.yaml` | Production override example |
| `archive/example-values.yaml` | Older example values (historical) |
| `manifests/composio.yaml` | KOTS HelmChart resource (pins chartVersion) |

## Common Tasks

### Adding a New Service

1. Create template directory: `composio/templates/<service>/`
2. Add deployment, service, configmap templates
3. Add configuration section in `values.yaml`
4. Create tests in `composio/tests/<service>_test.yaml`
5. Update `_helpers.tpl` if new helpers needed

### Modifying Existing Service

1. Read the current template and values
2. Update `values.yaml` with new options (add comments)
3. Modify templates in `composio/templates/<service>/`
4. Update/add tests to cover changes
5. Run `./run-tests.sh <service>` to verify

### Updating Dependencies

```bash
cd composio/
# Edit Chart.yaml dependencies
helm dependency update
# Verify Chart.lock is updated
```

## Deployment Modes

1. **Replicated / KOTS** - `replicated.enabled: true`. **This is the shipped default** in
   `values.yaml`; images resolve through the `artifacts.composio.io` proxy and
   `manifests/` supplies the KOTS resources.
2. **Standard Kubernetes** - `replicated.enabled: false` renders vanilla
   Deployments/Services pulling from the ECR registry in `global.registry.name`.
   Most production overrides do this (see `overwrite-values.yaml`).
3. **Knative Serverless** - `mercury.useKnative: true`. Orthogonal to the two above.

## Branch Strategy

- `release-stable` - the default branch and the target of every PR. There is no `master`;
  all development flows through `release-stable`.
- Nightly release jobs create `nightly-r<date>_<n>` branches automatically.
- PRs trigger CI validation before merge.

## Secrets Management

Secrets are referenced via `composio-composio-secrets` (configurable via `secret.name`).
Keys consumed by the templates include:

- `POSTGRES_URL`, `THERMOS_DATABASE_URL` - database connections
- `OPENAI_API_KEY` - via the `openAI` block
- `REDIS_URL` (plus Sentinel username/password keys) - via `externalRedis`
- `JWT_SECRET`, `ENCRYPTION_KEY`, `TEMPORAL_TRIGGER_ENCRYPTION_KEY`
- `COMPOSIO_ADMIN_TOKEN`
- `AWS_BEDROCK_ACCESS_KEY_ID`, `AWS_BEDROCK_SECRET_ACCESS_KEY`
- ECR authentication via `externalSecrets.ecr.*`

Never hardcode secrets in values files. Use secret references or external secret management.

## Code Style

- 2-space indentation in YAML
- Use `nindent` for proper indentation in includes
- Document configurable options in values.yaml with `# --` comments (helm-docs style)
- Follow Kubernetes label conventions (`app.kubernetes.io/*`)
- Always specify resource requests/limits
- Include liveness/readiness probes for all deployments
