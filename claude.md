# Claude.md - Composio Helm Charts

## Project Overview

This repository contains Helm charts for deploying the Composio platform on Kubernetes. The main chart (`composio/`) orchestrates a multi-service microservices architecture with support for standard Kubernetes, Knative serverless, and Replicated SaaS deployments.

## Tech Stack

- **Helm 3** - Kubernetes package manager
- **Kubernetes** - Container orchestration
- **GitHub Actions** - CI/CD automation
- **helm-unittest** - Chart testing framework
- **Replicated** - SaaS distribution platform
- **Knative** - Serverless deployment option

## Repository Structure

```
helm-charts/
├── composio/                   # Main Helm chart (v0.1.33)
│   ├── Chart.yaml              # Chart metadata and dependencies
│   ├── values.yaml             # Default configuration (~1,175 lines)
│   ├── values-override.yaml    # QA/staging overrides
│   ├── templates/              # Kubernetes manifests (29 templates)
│   │   ├── _helpers.tpl        # Shared template functions
│   │   ├── apollo/             # Main API service
│   │   ├── thermos/            # Workflow execution service
│   │   ├── mercury/            # Lambda/function orchestration
│   │   ├── frontend/           # Web UI (Next.js)
│   │   ├── database/           # Database initialization
│   │   ├── knative/            # Serverless support
│   │   └── ...
│   ├── tests/                  # helm-unittest test suite
│   └── charts/                 # Bundled dependencies (redis, temporal, replicated)
├── docs/                       # GitHub Pages documentation
├── manifests/                  # Replicated app manifests
├── .github/workflows/          # CI/CD workflows
├── example-values.yaml         # Production example
└── index.yaml                  # Helm repository index
```

## Core Services

| Service | Port | Purpose |
|---------|------|---------|
| **Apollo** | 9900 | Main API, database, storage, search |
| **Thermos** | 8180 | Workflow execution, Redis cache |
| **Mercury** | 8080 | Function orchestration (Knative-capable) |
| **Frontend** | 3000 | Next.js web UI |
| **Temporal** | 7233 | Workflow engine (subchart) |
| **Redis** | 6379 | Caching layer (Bitnami subchart) |

## Development Commands

### Linting and Validation

```bash
# Lint the chart
helm lint composio/

# Template validation (dry-run)
helm template my-release composio/ --debug

# Dependency update
helm dependency update composio/
```

### Testing

```bash
cd composio/

# Run all tests
./run-tests.sh

# Run specific service tests
./run-tests.sh apollo
./run-tests.sh mercury
./run-tests.sh thermos

# Verbose/debug modes
./run-tests.sh verbose
./run-tests.sh debug

# Include subchart tests
./run-tests.sh with-subchart
```

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

```yaml
# Feature toggles
apollo:
  enabled: true
  replicaCount: 1
  image:
    repository: composio/apollo
    tag: latest
  resources:
    requests:
      cpu: "0.5"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
  ingress:
    enabled: false
```

### Template Patterns

1. **Conditional rendering**: `{{- if .Values.<service>.enabled }}`
2. **Image reference**: `{{ include "chart.registry" . }}/{{ .Values.<service>.image.repository }}:{{ .Values.<service>.image.tag }}`
3. **Resource naming**: `{{ .Release.Name }}-<service>`
4. **Secret references**: Use `valueFrom.secretKeyRef` for sensitive data

### Helper Functions (composio/templates/_helpers.tpl)

- `composio.name` - Chart name expansion
- `composio.coreSecretName` - Core secret reference
- `chart.registry` - Container registry formatting
- Secret lookups: `composio-admin-token`, `encryption-key`, `jwt-secret`

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yaml` | Pull requests | Lint + template validation |
| `helm-release.yaml` | Manual | Package chart, create release |
| `release.yml` | Manual/merge | Release to Replicated Unstable |
| `release-qa.yaml` | Manual/pre-release | Deploy to GKE QA cluster |
| `secrets-detection.yml` | PRs | Gitleaks secret scanning |

## Writing Tests

Tests use `helm-unittest` plugin. Location: `composio/tests/`

```yaml
# Example test structure
suite: apollo deployment tests
templates:
  - apollo/deployment.yaml
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

### Test Conventions

- One test file per template/service: `<service>_test.yaml`
- Use `set:` blocks to override values per test
- Test both enabled and disabled states
- Verify resource limits, health checks, security contexts
- Use `hasDocuments: count:` for conditional rendering tests

## Important Files

| File | Purpose |
|------|---------|
| `composio/Chart.yaml` | Chart version, dependencies |
| `composio/values.yaml` | All configurable options |
| `composio/templates/_helpers.tpl` | Shared template functions |
| `example-values.yaml` | Production configuration example |
| `manifests/composio.yaml` | Replicated manifest |

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

1. **Standard Kubernetes** - Default Deployments/Services
2. **Knative Serverless** - Set `mercury.useKnative: true`
3. **Replicated SaaS** - Set `replicated.enabled: true`

## Branch Strategy

- `master` - Main development branch
- `release-stable` - Stable releases, auto-PR from CI
- PRs trigger CI validation before merge

## Secrets Management

Secrets are referenced via `composio-composio-secrets` (configurable via `secret.name`). Key secrets:
- Database credentials
- API keys (OpenAI, Composio)
- JWT secrets
- Encryption keys
- ECR authentication tokens

Never hardcode secrets in values files. Use secret references or external secret management.

## Code Style

- 2-space indentation in YAML
- Use `nindent` for proper indentation in includes
- Add `##` comments for configurable options in values.yaml
- Follow Kubernetes label conventions (`app.kubernetes.io/*`)
- Always specify resource requests/limits
- Include liveness/readiness probes for all deployments
