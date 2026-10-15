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
> `publish-self-host-images.yml` in composio-enterprise.

### Prerequisites
- External Postgres reachable from the cluster, with `databaseMigration.enabled: true` so the
  `egatewaydb` and `fusionauthdb` databases are created.
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

### Notes
- Admin runs with `SELF_HOSTED=true`, so Datadog, Sentry and Resend are optional. Without
  Resend, invite and password-reset emails are not sent.
- FusionAuth uses its database as the search engine (no OpenSearch needed). Its kickstart
  only runs on an empty database: it creates the API key and sets the tenant issuer. Org
  tenants and applications are provisioned by the admin at runtime.
- Set `egateway.fusionauth.enabled: false` to use an existing FusionAuth instance, and pass
  its URLs through `egateway.admin.extraEnv` / `egateway.proxy.extraEnv`.
