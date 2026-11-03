## Enterprise MCP Gateway (eGateway) Setup

The `egateway` component deploys the Composio enterprise MCP gateway
([composio-enterprise](https://github.com/ComposioHQ/composio-enterprise)) next to the
rest of the Composio stack:

| Component | Port | Purpose |
|-----------|------|---------|
| `egateway-admin` | 3002 | Admin dashboard (Next.js) |
| `egateway-proxy` | 3001 | MCP proxy that AI clients connect to |
| `egateway-fusionauth` | 9011 | Bundled FusionAuth identity provider |
| `egateway-migrate` | — | Prisma migrations (pre-install/pre-upgrade hook) |
| `egw-*` CronJobs | — | Scheduled admin jobs (formerly Vercel crons) |

The gateway talks to the in-cluster Composio backend (`<release>-apollo:9900`) by default.

> **Images:** the `composio-self-host/egateway-{admin,proxy,migrate}` ECR repositories are
> placeholders until they are created and published by
> `publish-self-host-images.yml` in composio-enterprise. They are built from
> `apps/admin/Dockerfile`, `apps/proxy/Dockerfile` and `packages/db/Dockerfile`, and all
> three run as the non-root user `1001` (`egateway.podSecurityContext`).

### Prerequisites
- External Postgres reachable from the cluster, with `databaseMigration.enabled: true` so the
  `egatewaydb` and `fusionauthdb` databases are created.
- TLS enabled on that Postgres. Apollo's migration fails with `The server does not support
  SSL connections` otherwise.
- A Redis instance for the gateway.
- Three DNS names (defaults shown) and an Ingress controller:
  `egateway.<global.domain>`, `mcp.<global.domain>`, `auth.<global.domain>`.

### Secrets
Add these keys to the core secret (`secret.name`), or to a dedicated secret set in
`egateway.secretRef`:

| Key | Description |
|-----|-------------|
| `EGATEWAY_POSTGRES_URL` | `postgresql://user:pass@host:5432/egatewaydb` |
| `EGATEWAY_REDIS_URL` | `redis://:pass@host:6379` |
| `COMPOSIO_API_KEY_ENCRYPTION_SECRET` | Random string, at least 16 characters |
| `SAML_AUTHN_PROXY_HMAC_SECRET` | Random token |
| `FUSIONAUTH_API_KEY` | Random token; FusionAuth creates this API key on first boot |
| `FUSIONAUTH_WEBHOOK_SECRET` | Random token |
| `INTERNAL_SERVICE_TOKEN` | Random token |
| `CRON_SECRET` | Random token used by the CronJobs |
| `FUSIONAUTH_DATABASE_PASSWORD` | Password of the Postgres user for `fusionauthdb` |

### Example values
```yaml
global:
  domain: example.com

databaseMigration:
  enabled: true
  host: my-postgres.internal
  port: "5432"

egateway:
  enabled: true
  ingress:
    enabled: true
    className: nginx
    tls:
      - secretName: egateway-tls
        hosts: [egateway.example.com, mcp.example.com, auth.example.com]
```

### Authenticating to Composio

Each org stores a Composio project API key (`ak_...`), which the gateway encrypts and sends
as `x-api-key`. Get one from the in-cluster Apollo with its admin token:

```bash
kubectl -n <namespace> port-forward svc/<release>-apollo 9900:9900
curl -X POST http://localhost:9900/api/v3/admin/identify \
  -H "x-composio-admin-token: $COMPOSIO_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' -d '{"hash": "<name>"}'
```

The `apiKey` field in the response is the key. Newer Apollo images also serve
`POST /api/v3.1/self_hosted/bootstrap`, which takes a real email and returns the key as
`api_key`; the chart's default Apollo image (`r20260501_01`) answers 404 on that route.

### Creating the first organization

Run the CLI bundled in the admin image once the pods are ready. It needs the Composio key
above, and prints an onboarding link for the founder:

```bash
kubectl -n <namespace> exec deploy/<release>-composio-egateway-admin -- \
  bun apps/admin/ops/create-org.js \
    --name "Acme" --slug acme --teams engineering \
    --founder-email founder@acme.example.com \
    --composio-api-key "$COMPOSIO_PROJECT_KEY"
```

### Notes
- Admin and proxy run with `SENTRY_ENABLED`, `DATADOG_ENABLED` and `RESEND_ENABLED` set to
  `false`, so those SaaS integrations are off and their settings are not required. Without Resend, invite
  and password-reset emails are not sent.
- The proxy only accepts requests for hosts in `ALLOWED_HOSTS` and will not start without
  it. The chart sets it to the proxy host and the proxy Service name; override with
  `egateway.proxy.allowedHosts`.
- Admin readiness uses `/api/health` (Postgres, Redis, FusionAuth, Composio); liveness uses
  `/api/version` so a dependency outage does not restart the pod.
- The bundled FusionAuth is reached through its Service for server-to-server calls
  (`FUSIONAUTH_INTERNAL_URL` on admin, `FUSIONAUTH_URL` on the proxy), so the gateway can become ready before DNS, Ingress and TLS for the
  auth host work. Logins still need them, because browsers use `https://<auth host>`.
- `manifest-reverify`, `manifest-fix-drift` and `argument-profile` are not scheduled because
  they need `COMPOSIO_CATALOG_API_KEY`, `ANTHROPIC_API_KEY` and ClickHouse respectively.
- The `COMPOSIO_SEARCH_TOOLS` MCP tool needs Apollo search, which is off by default
  (`apollo.search.enabled`). Without it the tool returns an error; tools called by slug still work.
- FusionAuth uses its database as the search engine (no OpenSearch needed). Its kickstart
  only runs on an empty database: it creates the API key and sets the tenant issuer. Org
  tenants and applications are provisioned by the admin at runtime.
- Set `egateway.fusionauth.enabled: false` to use an existing FusionAuth instance, and pass
  its URLs through `egateway.admin.extraEnv` / `egateway.proxy.extraEnv`.
