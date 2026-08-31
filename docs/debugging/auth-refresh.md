# Debugging auth refresh failures (self-hosted)

This guide is for operators of a self-hosted Composio deployment who need to
work out why a connection's credentials stop working — a connected account that
keeps expiring, tool calls that start returning 401, or a toolkit whose tokens
never seem to refresh.

Everything here uses only what you have in your own cluster: the Composio HTTP
API, your Kubernetes logs, and your Redis. You never need to query the Composio
databases directly, and nothing here depends on Composio's internal
observability stack.

Work through the steps in order and stop at the first one that answers the
question. Most investigations end at Step 1.

---

## 1. Background: when Composio refreshes a credential

Apollo refreshes credentials **just in time (JIT)**, while it is resolving
authorization for a call that is about to hit the provider. The refresh runs
only when all of these hold:

- The auth scheme has a refresh implementation. Only `OAUTH2`, `DCR_OAUTH`,
  `S2S_OAUTH2` and `BASIC_WITH_JWT` are ever refreshed. An `API_KEY`,
  `BEARER_TOKEN` or `BASIC` connection has nothing to refresh — when it starts
  failing auth, the credential itself has to be re-entered.
- Apollo has a stored access-token expiry for the connection, and that expiry
  falls inside the next **five minutes**. A connection with no derived expiry
  is skipped silently, with no log line.
- The connection is in a refreshable state (not `EXPIRED`, not disabled).
- No post-failure backoff is currently in effect for that connection.

There is a second path, **keep-alive refresh**, which protects idle connections
whose *refresh token* would expire before the connection is next used. It is
scheduled through Thermos and requires extra configuration on self-hosted — see
[Keep-alive refresh is off by default](#keep-alive-refresh-is-off-by-default).

When a refresh attempt fails, Apollo probes the stored credential against the
toolkit's "current user" endpoint to decide whether the credential is actually
dead:

| Refresh outcome | Credential probe | What happens to the connection |
|---|---|---|
| Success | not run | new credential stored, status `ACTIVE`, failure tracking cleared |
| Any provider failure | `alive` | stays `ACTIVE`, failure tracking cleared |
| `auth_rejected` | `dead` | marked `EXPIRED` immediately |
| Anything else | `dead` / `inconclusive` / `not_checked` | failure budget accrues; `EXPIRED` when it runs out |
| Apollo-internal error | not run | status and failure tracking unchanged |

The failure budget is a wall-clock window, not a retry count. It is controlled
by `MAX_AUTH_FAILURE_DURATION_MINUTES` on Apollo (default `2880`, i.e. 48
hours), and its start timestamp lives in Redis.

---

## 2. Turn on debug logs first

Before you start digging, enable debug logging on Apollo. Several of the checks
below depend on lines that Apollo only emits at debug level.

Add the environment variable to your values file and upgrade:

```yaml
apollo:
  env:
    - name: ENABLE_DEBUG_LOGS
      value: "true"
```

```bash
helm upgrade composio composio/ -f my-values.yaml -n composio
kubectl rollout status deploy/composio-apollo -n composio
```

`ENABLE_DEBUG_LOGS` drops Apollo's log level from `info` to `debug`. It takes
effect at process start, so the pods must restart — a `helm upgrade` that
changes the value does that for you.

### What debug logs give you that info logs do not

These are the debug-only lines that matter for an auth refresh investigation.

**Every internal error object gets logged.** Apollo normally logs only the
errors explicitly marked for logging; the rest are returned to the caller and
never written out. With debug on, *every* constructed error is written at
`ERROR` level with its message. For refresh this surfaces otherwise-invisible
failures such as `Toolkit auth scheme not found`, `Failed to verify connected
account credential`, and `Connected account identifier does not match loaded
connection` — all of which abort a refresh before it ever reaches the provider,
and therefore never produce an `Auth refresh failed` line.

**Which connected account a call actually used.** `Finding connection` (the
toolkit slug and connected-account id that were requested) and `Found
connection` (the `ca_` id that was actually selected), plus `Finding
connections (bulk)` for multi-toolkit calls. This is how you catch a call that
authenticated with a different connection than you expected — a 401 that no
amount of refreshing will fix.

**Confirmation that the refresh request was built.** `Token payload for
refresh` is emitted once the OAuth2 refresh body has been constructed, so its
presence proves execution reached the token request and the failure is on the
provider side of that call. No credential values are logged.

**Connection-data status mismatch.** `Mismatched status: expected X, got Y`
means the status inside the encrypted connection payload disagrees with the
status column on the row. This is invisible at info level and points at a
partially-applied write.

**An encrypted dump of the resolved auth.** `Auth metadata` carries an
`encryptedAuthMetadata` field: the fully resolved authorization data for that
execution, encrypted at the call site with your deployment's own encryption key
so it never lands in your logs as plaintext. Its presence tells you auth
resolution completed for that execution. Only your deployment can decrypt it —
Composio does not hold your key — so it is not something to send to support,
and the plaintext behind it contains live credentials.

**Auth-config field mapping.** `strict and generic field mappings` prints how
the auth config's fields map to their generic names. Useful when a refresh
fails because a field such as `client_id` did not resolve to anything.

**Per-execution trace lines.** `Executing <TOOL> using apollo implementation…`
and `Executing tool <slug> via Thermos <version>` tie a specific 401 to a tool,
a version and a request id.

**Log backend confirmation.** `Using PostgresLogger for tool execution logs`
confirms tool-execution logging is going to the self-hosted Postgres table
rather than ClickHouse.

> Debug level is verbose across the whole service, not just the auth paths.
> Turn it on for the investigation and turn it back off afterwards.

---

## 3. Reading Apollo logs in Kubernetes

Apollo writes one JSON object per line to stdout. Each line carries a
`message`, a Stackdriver-style `severity` (`DEBUG` / `INFO` / `WARNING` /
`ERROR` / `CRITICAL`), a `timestamp`, and any structured fields the call site
added, flattened onto the top level of the object.

The Apollo pods are labelled `app=apollo`.

### Works everywhere: kubectl

```bash
# All auth-refresh failures in the last hour
kubectl logs -n composio -l app=apollo --since=1h --tail=-1 \
  | jq -c 'select(.message == "Auth refresh failed")'

# Everything Apollo logged about one connection
kubectl logs -n composio -l app=apollo --since=24h --tail=-1 \
  | jq -c 'select(.connectionNanoId == "ca_YOUR_ID" or .connectionId == "ca_YOUR_ID")'

# Refresh outcomes for one toolkit, condensed
kubectl logs -n composio -l app=apollo --since=24h --tail=-1 \
  | jq -c 'select(.toolkitSlug == "gmail" and (.message == "Auth refresh failed" or .message == "Token refresh succeeded"))
           | {message, failureKind, livenessKind, terminal, httpStatus, providerCode, connectionNanoId}'
```

Both `connectionNanoId` and `connectionId` are needed: the JIT entrypoint tags
its early lines with `connectionId`, and switches to `connectionNanoId` (plus
`toolkitSlug` and `authScheme`) once the toolkit has been resolved.

### GKE — Cloud Logging

The GKE logging agent parses Apollo's JSON into `jsonPayload` and honours the
`severity` field, so structured fields are queryable directly:

```
resource.type="k8s_container"
resource.labels.namespace_name="composio"
labels."k8s-pod/app"="apollo"
jsonPayload.message="Auth refresh failed"
```

```
resource.type="k8s_container"
labels."k8s-pod/app"="apollo"
(jsonPayload.connectionNanoId="ca_YOUR_ID" OR jsonPayload.connectionId="ca_YOUR_ID")
```

```
resource.type="k8s_container"
labels."k8s-pod/app"="apollo"
jsonPayload.toolkitSlug="gmail"
jsonPayload.failureKind="auth_rejected"
```

To see only the debug lines from section 2:

```
resource.type="k8s_container"
labels."k8s-pod/app"="apollo"
severity="DEBUG"
jsonPayload.message=~"Found connection|Token payload for refresh|Mismatched status"
```

### EKS — CloudWatch Logs Insights

The exact field names depend on your log shipper. With Fluent Bit configured to
parse the container JSON and merge it into the record (`Merge_Log On`), the
Apollo fields land at the top level:

```
fields @timestamp, message, connectionNanoId, toolkitSlug, failureKind, livenessKind, httpStatus, providerCode
| filter kubernetes.labels.app = "apollo"
| filter message = "Auth refresh failed"
| sort @timestamp desc
| limit 100
```

```
fields @timestamp, message, failureKind, livenessKind, terminal
| filter kubernetes.labels.app = "apollo"
| filter connectionNanoId = "ca_YOUR_ID" or connectionId = "ca_YOUR_ID"
| sort @timestamp desc
```

If your shipper leaves the Apollo line as a raw string in `log`, parse it first:

```
fields @timestamp, @message
| filter kubernetes.labels.app = "apollo"
| parse log '"message":"*"' as msg
| filter msg = "Auth refresh failed"
| sort @timestamp desc
```

A failure-shape breakdown:

```
fields failureKind, livenessKind
| filter kubernetes.labels.app = "apollo"
| filter message = "Auth refresh failed"
| stats count(*) by failureKind, livenessKind
```

### Self-managed stacks (Loki, Elasticsearch, Splunk)

Any shipper that parses JSON works the same way. The only thing that changes is
the query syntax — filter on `message`, then on `connectionNanoId` /
`toolkitSlug` / `failureKind`. For Loki:

```
{app="apollo"} | json | message = "Auth refresh failed" | toolkitSlug = "gmail"
```

---

## 4. Log field reference

Two messages carry the refresh outcome. Match them exactly.

### `Auth refresh failed` (severity `WARNING`)

| Field | Meaning |
|---|---|
| `connectionNanoId` | the `ca_` id |
| `toolkitSlug` | toolkit the connection belongs to |
| `authScheme` | `OAUTH2`, `DCR_OAUTH`, `S2S_OAUTH2`, `BASIC_WITH_JWT` |
| `failureKind` | `auth_rejected`, `rate_limited`, `provider_unavailable`, `provider_protocol_error` |
| `failureMessage` | short description of the failure |
| `livenessKind` | `alive`, `dead`, `inconclusive`, `not_checked` |
| `livenessReason` | `timeout`, `transport_error`, `rate_limited`, `provider_unavailable`, `endpoint_not_found`, `not_configured`, `proxy_execute_disabled` |
| `terminal` | whether this attempt ended the refresh (no more retries) |
| `budgetMs` | remaining failure budget in milliseconds |
| `httpStatus` | HTTP status the provider's token endpoint returned |
| `providerCode` | the provider's own error code (present on `auth_rejected`) |
| `contentType` | content type of the token-endpoint response |
| `responseHeaders` | response headers, with sensitive ones redacted |
| `responseBodyPreview` | truncated response body, in plaintext |
| `encryptedBodyPreview` | the same preview, encrypted — used instead of the plaintext one when the response failed to parse as a token response |

### `Token refresh succeeded` (severity `INFO`)

Carries `connectionNanoId`, `toolkitSlug`, `authScheme` and `authConfigKind`.

### Other lines worth searching for

| Message | Severity | What it tells you |
|---|---|---|
| `Current user endpoint check completed` | INFO | the liveness probe ran; `status` is the verdict |
| `Auth refresh failure streak for connection <id>` | INFO | `firstFailureAt`, `elapsedMs` and `budgetMs` for the connection's current streak |
| `Refresh took over a lapsed connected-account lease` | WARNING | a previous refresh died or outran its lease; clustered on one toolkit it means a slow token endpoint |
| `Refresh skipped after lease acquire: connection no longer refreshable` | INFO | the connection was revoked/expired between the pre-check and the refresh |
| `Connection is REVOKED, attempting refresh anyway` | WARNING | refresh proceeded on a revoked connection |
| `Connected account non-sensitive data did not match its schema` | WARNING | the stored expiry metadata is malformed, which silently disables JIT refresh for that connection |
| `Failed to persist refreshed connection data` | ERROR | the provider returned a new token but Apollo could not store it |
| `Scheduled a keep-alive refresh` | INFO | keep-alive enrolled the connection; includes `fireAt` and `refreshTokenExpiresAt` |
| `Failed to schedule a keep-alive refresh` | ERROR | keep-alive could not be armed; see the section below |

---

## 5. Step 0 — Identify the connection through the API

Self-hosted deployments do not query the Composio database directly. Use the
API with a project API key (`x-api-key`).

```bash
export COMPOSIO_BASE_URL="https://composio.your-domain.com"
export COMPOSIO_API_KEY="ak_..."

curl -s "$COMPOSIO_BASE_URL/api/v3/connected_accounts/ca_YOUR_ID" \
  -H "x-api-key: $COMPOSIO_API_KEY" | jq
```

Read five things off the response:

- **`state.authScheme`** — if it is not `OAUTH2`, `DCR_OAUTH`, `S2S_OAUTH2` or
  `BASIC_WITH_JWT`, **stop here**. That credential is never refreshed; there is
  no refresh to debug, and the fix is for the end user to re-enter the
  credential. This is the single most common way the question itself turns out
  to be wrong. (The top-level `authScheme` and `auth_config.auth_scheme` fields
  carry the same value but are deprecated.)
- **`status`** — `ACTIVE`, `EXPIRED`, `REVOKED`, `INITIATED`, `FAILED`, …
- **`status_reason`** — a human-readable explanation of how the connection got
  into its current status. This is the field that most often ends the
  investigation on its own. Values you will see include `Permanent auth error
  during token refresh`, `Max auth failures reached`, `Authorization was denied
  at the provider`, `Auth config is disabled`, `Revoked via user-initiated
  revoke endpoint`, and reasons that embed the provider's own text, prefixed
  `Access revoked; Details: …` or `Credential refresh failing persistently,
  unable to establish liveness; Details: …`.
- **`state.val.expires_at` / `state.val.expires_in`** — the provider-reported
  expiry, if the provider supplied one. Token values themselves are masked or
  redacted in the response; these expiry fields are not.
- **`is_disabled` and `auth_config.is_disabled`** — a disabled auth config
  blocks every connection under it, and shows up as `status_reason: Auth config
  is disabled`.

A one-liner for the fields that matter:

```bash
curl -s "$COMPOSIO_BASE_URL/api/v3/connected_accounts/ca_YOUR_ID" \
  -H "x-api-key: $COMPOSIO_API_KEY" \
  | jq '{scheme: .state.authScheme, status, status_reason,
         expires_at: .state.val.expires_at, expires_in: .state.val.expires_in,
         is_disabled, auth_config_disabled: .auth_config.is_disabled}'
```

To list every connection for a toolkit and see the status distribution:

```bash
curl -s "$COMPOSIO_BASE_URL/api/v3/connected_accounts?toolkit_slugs=gmail&limit=100" \
  -H "x-api-key: $COMPOSIO_API_KEY" \
  | jq -r '.items[] | [.id, .status, (.status_reason // "-")] | @tsv'
```

---

## 6. Step 1 — Confirm there is actually a problem

Run both probes before diagnosing anything. Their *combination* selects the
branch in Step 2.

### Probe A — refresh outcomes (Apollo logs)

Count successes against failures over the same window. Use the ratio, never the
raw failure count.

```bash
kubectl logs -n composio -l app=apollo --since=24h --tail=-1 \
  | jq -r 'select(.toolkitSlug == "gmail" and (.message == "Auth refresh failed" or .message == "Token refresh succeeded"))
           | .message' \
  | sort | uniq -c
```

For a single connection, group its failures by shape:

```bash
kubectl logs -n composio -l app=apollo --since=24h --tail=-1 \
  | jq -r 'select((.connectionNanoId == "ca_YOUR_ID" or .connectionId == "ca_YOUR_ID") and .message == "Auth refresh failed")
           | [.failureKind, .livenessKind, (.terminal|tostring), (.httpStatus|tostring)] | @tsv' \
  | sort | uniq -c
```

### Probe B — tool-execution outcomes (logs API)

On self-hosted, tool execution logs are stored in your own Postgres, in the
`self_hosted.tool_execution_logs_self_hosted` table (ClickHouse is not used —
Apollo runs with `USE_CLICKHOUSE_FOR_LOGS=false`). You do not query that table
directly; read it through the logs API, which decrypts the payloads for you.

```bash
# Failed executions for one connection over the last 24h
NOW=$(date +%s000); FROM=$(( NOW - 86400000 ))

curl -s -X POST "$COMPOSIO_BASE_URL/api/v3.1/logs/tool_execution" \
  -H "x-api-key: $COMPOSIO_API_KEY" -H "Content-Type: application/json" \
  -d "{
        \"limit\": 50,
        \"time_range\": {\"from\": $FROM, \"to\": $NOW},
        \"filters\": [
          {\"field\": \"connected_account_id\", \"operator\": \"==\", \"value\": \"ca_YOUR_ID\"},
          {\"field\": \"status\", \"operator\": \"==\", \"value\": \"failed\"}
        ]
      }" | jq '.logs[] | {id, timestamp, tool: .metadata.tool.slug}'
```

Filterable fields are `tool_slug`, `toolkit_slug`, `connected_account_id`,
`auth_config_id`, `status` (`success` / `failed`), `user_id`, `session_id`,
`sandbox_id`, `request_id` and `log_id`. Operators are `==`, `!=`, `contains`
and `not_contains`.

Then fetch one failed log to read the provider's verbatim error body — this is
usually the whole answer:

```bash
curl -s "$COMPOSIO_BASE_URL/api/v3.1/logs/tool_execution/LOG_ID" \
  -H "x-api-key: $COMPOSIO_API_KEY" \
  | jq '{status,
         tool: .metadata.tool.slug,
         http_status: .data.response.body.data.status_code,
         http_error: .data.response.body.data.http_error,
         error: .data.response.body.error}'
```

`data.response.body.error` is the provider's verbatim error payload, and
`data.response.body.data.status_code` is the HTTP status the provider returned.
There is no filter on status code, so filter by `status: failed` and read the
status code back per log to separate 401s from the rest.

Note that **403 is not 401**: 403 is usually a missing scope or permission, and
no amount of refreshing fixes it.

### Read the result

| | 401s present | no 401s |
|---|---|---|
| **refresh failing** | genuinely broken refresh → [7.1](#71-refresh-is-failing) | write-only credential or dead connection → [7.2](#72-refresh-fails-but-nothing-401s) |
| **refresh clean** | JIT never fired, revocation, or a one-off 401 → [7.3](#73-clean-refresh-but-401s) | no issue — report and stop |

### Check the scope before diagnosing

Scope changes the answer more than any single log field.

- Starting from a **toolkit**: group the failures by connection. Failures
  concentrated on one or two connections, while the rest of the toolkit
  refreshes fine, mean those grants were revoked — not that the toolkit is
  broken.
- Starting from a **connection**: ask the inverse. If the whole toolkit is
  failing, this connection is not the story.
- Either way, when the same connection returned a `200` within a few minutes of
  a `401`, do not read the `200` as clearing refresh on its own. Tool execution
  resolves its credential through the JIT path, so that `200` may have used a
  token JIT had just replaced. Check **both** refresh messages for the
  connection over that window and read the pair:

  ```bash
  kubectl logs -n composio -l app=apollo --since=1h --tail=-1 \
    | jq -r 'select(.connectionNanoId == "ca_YOUR_ID" or .connectionId == "ca_YOUR_ID")
             | select(.message == "Auth refresh failed" or .message == "Token refresh succeeded")
             | "\(.timestamp) \(.message)"'
  ```

  - **Neither message.** Nothing refreshed in the window, so refresh did not
    produce the `401`. It was provider flakiness or a rate limit surfaced as
    `401`. Stop there.
  - **`Token refresh succeeded` between the `401` and the `200`.** Refresh is
    working; the `401` was served just before it fired. That is a timing
    finding, not flakiness — the expiry Apollo derived left a window where the
    provider had already rejected the token. Continue to
    [7.3](#73-clean-refresh-but-401s) and check the stored expiry.
  - **`Auth refresh failed` present.** Refresh is implicated regardless of the
    interleaved 200s. Go to [7.1](#71-refresh-is-failing).

---

## 7. Step 2 — Root cause

### 7.1 Refresh is failing

Pull the raw `Auth refresh failed` lines and read the fields rather than the
prose:

```bash
kubectl logs -n composio -l app=apollo --since=24h --tail=-1 \
  | jq 'select(.message == "Auth refresh failed" and .toolkitSlug == "gmail")
        | {failureKind, httpStatus, providerCode, responseBodyPreview, livenessKind, livenessReason, terminal}'
```

Interpretation:

- **`auth_rejected` + `dead`** — the provider rejected the refresh *and* an
  independent probe confirmed the credential is dead. Conclusive: the grant is
  gone. The user must re-authorize.
- **`auth_rejected` + `alive`** — the refresh fails but the credential still
  works. Either the refresh parameters are wrong, or the OAuth credential is
  never actually sent (see 7.2).
- **`rate_limited` / `provider_unavailable`** — provider-side. Check whether it
  correlates with your own retry volume before blaming the provider.
- **`provider_protocol_error`** — the response did not parse as a token
  response. `responseBodyPreview` usually shows an HTML error page or a login
  redirect, which normally means the configured token URL is wrong or is being
  intercepted by a proxy. On self-hosted this is frequently an **egress
  problem**: an outbound proxy, TLS interception, or a firewall returning its
  own page instead of the provider's.
- **`livenessKind: inconclusive` with `endpoint_not_found`** — the toolkit's
  current-user endpoint has moved or is misconfigured, so the probe cannot
  reach a verdict and failures accumulate instead of expiring the connection.
- **`livenessKind: not_checked` with `not_configured`** — no probe endpoint is
  configured for that toolkit.

Because a self-hosted Apollo has to reach the provider's token endpoint
directly, rule out network causes before anything else when `httpStatus` is
missing or `failureKind` is `provider_unavailable`:

The Apollo image is deliberately minimal and ships no `curl`, but Node is
always present, so probe egress from the Apollo pod itself — that is the network
namespace and proxy configuration that matters:

```bash
kubectl exec -n composio deploy/composio-apollo -- \
  node -e 'fetch("https://oauth2.googleapis.com/token",{method:"POST"})
    .then(r=>console.log("status",r.status))
    .catch(e=>console.log("failed",e.cause?.message??e.message))'
```

A `failed` line naming a DNS, TLS or connection error is an egress problem, not
a Composio one. A status code (even a 4xx, which is the expected answer to an
empty token request) means the provider is reachable.

### 7.2 Refresh fails but nothing 401s

Some toolkits authenticate with a static credential (a bot token, an API key, a
PAT) even though the connection also holds an OAuth credential. That OAuth
credential is stored and refreshed but never sent — so every refresh failure on
it is harmless, and the liveness probe will report `alive` forever because it
authenticates with the static credential too.

The signal is exactly the pattern in this row: refresh failing, zero 401s, and
tool calls succeeding. If tool executions are healthy, this is cosmetic log
noise. Raise it with Composio support with the toolkit slug and a sample
`Auth refresh failed` line, and do not treat it as an outage.

### 7.3 Clean refresh but 401s

Three candidates, cheapest first.

**JIT never fired because there is no stored expiry.** If Apollo has no
access-token expiry for the connection, JIT refresh is skipped and **nothing is
logged**. The absence of any refresh log for a connection that is 401ing is the
finding, not a dead end. Confirm it:

```bash
# No lines at all for this connection over a window where it definitely 401'd?
kubectl logs -n composio -l app=apollo --since=24h --tail=-1 \
  | jq -c 'select(.connectionNanoId == "ca_YOUR_ID" or .connectionId == "ca_YOUR_ID")' | head
```

Also search for `Connected account non-sensitive data did not match its schema`,
which is the malformed-metadata variant of the same problem. Either case needs
Composio support: the fix is in the toolkit's expiry configuration, and existing
connections have to be re-authorized to pick up a corrected expiry.

**The grant was revoked at the provider.** Read the provider's own error text
from a failed execution log (Probe B above). Providers state revocation
explicitly — password changed, grant revoked, token invalid — with their own
error codes. That string is usually the entire answer, and the fix is for the
end user to reconnect.

**Backoff or a status gate is suppressing the refresh.** A recent failure buys a
quiet window that grows to 30 minutes, and `EXPIRED` connections are skipped
outright. Both live in Redis, which you operate, so you can check and clear
them:

Redis is external to the chart (`externalRedis`), so use whatever access you
normally have to it. From inside the cluster, run a throwaway pod that reads the
URL from the Secret at runtime rather than passing it on the command line — a
`--env` value would be written into the pod spec, where anyone with pod read
access (and your audit log) can see the Redis password:

```bash
kubectl run redis-cli --rm -it --restart=Never -n composio \
  --image=redis:7-alpine \
  --overrides='{"spec":{"containers":[{"name":"redis-cli","image":"redis:7-alpine",
    "stdin":true,"tty":true,"command":["sh"],
    "env":[{"name":"REDIS_URL","valueFrom":{"secretKeyRef":
      {"name":"composio-composio-secrets","key":"REDIS_URL"}}}]}]}}'

# then, inside the pod:
redis-cli -u "$REDIS_URL" GET "auth_refresh_backoff:ca_YOUR_ID"
redis-cli -u "$REDIS_URL" GET "auth_failure_first_at:ca_YOUR_ID"
```

The Secret name and key come from `externalRedis.secretRef` and
`externalRedis.key` — adjust the override if you changed either. Delete the pod
when you are done (`--rm` handles it on a clean exit).

`auth_refresh_backoff:<ca_id>` holds the quiet-window end time;
`auth_failure_first_at:<ca_id>` holds the epoch-milliseconds start of the
current failure streak (kept for 30 days).

Deleting these keys clears the backoff and resets the streak clock, which is a
legitimate way to force an immediate retry after you have fixed a network or
configuration problem. Deleting them does not fix a genuinely revoked grant.

> Both mechanisms fail open. If Redis is unavailable, refresh is never blocked
> by backoff and connections are never expired by the failure budget — so a
> Redis outage shows up as *more* refresh attempts, not fewer.

---

## 8. Self-hosted specifics

### Keep-alive refresh is off by default

Keep-alive refresh protects a connection that sits idle long enough for its
*refresh token* to expire. Apollo schedules it through Thermos, which needs both
Temporal and the Thermos worker database. Both are off in the shipped defaults
(`features.temporal: false`, `thermos.workerDb.enabled: false`), so keep-alive
is **not armed** on a default install and idle connections are protected by JIT
refresh alone.

If that matters for your workload — long-lived integrations with providers that
issue short-lived refresh tokens — enable both:

```yaml
features:
  temporal: true

thermos:
  workerDb:
    enabled: true
```

You can tell keep-alive is not armed from the Apollo logs:

```bash
kubectl logs -n composio -l app=apollo --since=24h --tail=-1 \
  | jq -c 'select(.message == "Failed to schedule a keep-alive refresh")
           | {connectionNanoId, toolkitSlug, failureKind, failureMessage}'
```

`workerdb unavailable for callback registration` or `timer manager unavailable
for callback registration` in `failureMessage` is exactly this configuration
gap. When keep-alive *is* working you will instead see `Scheduled a keep-alive
refresh` with a `fireAt`.

### What differs from Composio Cloud

If you are following advice written for Composio's hosted service, these are
the differences that matter:

- **Tool execution logs are in Postgres**, in
  `self_hosted.tool_execution_logs_self_hosted`, not ClickHouse. Read them
  through `/api/v3.1/logs/tool_execution`; the request and response payloads are
  encrypted at rest and the API decrypts them for you.
- **There is no Datadog**, and no `apollo.auth_refresh.*` metrics. The two log
  messages those metrics were built on — `Auth refresh failed` and `Token
  refresh succeeded` — are emitted identically here, so build the same
  ratio from your own log stack.
- **Connection state comes from the API, not SQL.** `status` and
  `status_reason` on `GET /api/v3/connected_accounts/{id}` carry what a direct
  database query would tell you.
- **The forced-refresh test endpoint is unavailable.** Self-hosted Apollo runs
  with `COMPOSIO_ENV=production`, which disables the internal test harness
  unconditionally. To trigger a refresh, execute a tool that uses the
  connection.

### Related environment variables

| Variable | Default | Effect |
|---|---|---|
| `ENABLE_DEBUG_LOGS` | `false` | Drops the Apollo log level to `debug`; see section 2 |
| `MAX_AUTH_FAILURE_DURATION_MINUTES` | `2880` | How long a connection may keep failing refresh before it is marked `EXPIRED` |

Both are set through `apollo.env`:

```yaml
apollo:
  env:
    - name: ENABLE_DEBUG_LOGS
      value: "true"
    - name: MAX_AUTH_FAILURE_DURATION_MINUTES
      value: "2880"
```

---

## 9. Escalating to Composio support

If the investigation lands on a toolkit configuration problem — a wrong token
URL, refresh parameters the provider rejects, a missing or wrong expiry
derivation, a stale current-user endpoint — that configuration lives in
Composio's toolkit definitions and is not something you can change from your
values file. Open a support ticket with:

1. The toolkit slug and auth scheme.
2. The connected-account id (`ca_…`) and its `status` / `status_reason` from
   the API.
3. A few full `Auth refresh failed` lines, including `failureKind`,
   `httpStatus`, `providerCode`, `responseBodyPreview`, `livenessKind` and
   `livenessReason`.
4. The `id` of a failed tool execution log, and the error body from
   `GET /api/v3.1/logs/tool_execution/{id}`.
5. The success/failure ratio for the toolkit and the window you measured it
   over.

Review what you send. `responseBodyPreview`, provider error bodies and
`status_reason` are plaintext passthroughs of what the provider returned: they
normally carry error codes and messages rather than credentials, but they are
not sanitized, so read them before attaching. Do not send
`encryptedAuthMetadata` — only your deployment holds the key, so it is
unreadable to support, and its plaintext is a live credential.
