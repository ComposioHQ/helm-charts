# Temporal Workflow Metrics

Thermos uses Temporal Cloud to orchestrate background workflows — auth refresh, trigger processing, cleanup, and MCP toolkit sync. Each workflow emits execution metrics to Datadog (via StatsD) and optionally to OpenTelemetry.

## Metric Overview

All workflows emit three core metrics:

| Metric | Type | Description |
|--------|------|-------------|
| `thermos.workflow.execution.total` | Counter | Incremented on every workflow run. Tagged with `workflow:<name>` and `status:success\|failure`. |
| `thermos.workflow.execution.duration` | Distribution | Execution duration in milliseconds. Tagged with `workflow:<name>` and `status:success\|failure`. |
| `thermos.workflow.last_success_epoch` | Gauge | Unix epoch of the last successful run. Used for staleness alerting. |

### Tags

All workflow metrics include:
- `workflow:<name>` — workflow identifier (see table below)
- `status:success` or `status:failure` — execution outcome

Some workflows add extra tags (e.g., `toolkit:<slug>`, `trigger_name:<name>`).

## Additional Domain-Specific Metrics

Beyond the three core workflow metrics, each domain emits its own counters:

- **Auth Refresh**: `auth_refresh.workflow.{success,failed,skipped}` (tagged by `app`, `group`)
- **Webhook Triggers**: `webhook.trigger.{matched,non_matched,tool_error,apollo_error,e2e_latency}`
- **Polling Triggers**: `polling.trigger.runs.{total,chunked,unchunked,duplicate}`, `polling.trigger.{tool_error,chunk_updates_error,apollo_updates_error,auth_refresh_error}`
- **Webhook Trigger Refresh**: `webhook.trigger_refresh.{total,success,not_required,failed}`
- **MCP Toolkit Sync**: `mcp_toolkit_sync.workflow.{completed,failed,skipped,no_change,no_connected_account}`, `mcp_toolkit_sync.tools.synced`

