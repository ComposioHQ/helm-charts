# Datadog Alert List for Composio Stack

**Team:** Composio  
**Last Updated:** 2025-11-03  
**Environment:** Production

---

## Alert 1: 4xx Error rate > 50% on {{span.resource_name}}

**Priority:** P2 - High  
**Type:** Trace Analytics  
**Status:** Active

### Query
```
trace-analytics("(count[service:apollo resource_name:hono* @hono.response.status_code:[400 TO 499] env:production -resource_name:*identify* -resource_name:*manage* -@hono.response.status_code:401 -resource_name:*DELETE* !@hono.response.status_code:403] / max(count[service:apollo resource_name:hono* env:production -@hono.response.status_code:401 -@hono.response.status_code:401 -@hono.response.status_code:404], 1000)) * 100").last("5m") > 200
```

### Thresholds
- **Alert:** > 200% (effective 50% after calculation)
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-composio-alerts @pagerduty-oncall`
- **Tags:** `service:apollo, env:production, error_type:4xx`

---

## Alert 2: 5xx Error rate > 10% on {{span.resource_name}}

**Priority:** P1 - Critical  
**Type:** Trace Analytics  
**Status:** Active

### Query
```
trace-analytics("(count[service:apollo resource_name:hono* @hono.response.status_code:[500 TO 599] env:production -resource_name:identify* -resource_name:manage* -resource_name:proxy*] / max(count[service:apollo resource_name:hono* env:production -resource_name:identify* -resource_name:manage* -resource_name:manage* -resource_name:proxy*], 300)) * 100").last("5m") > 20
```

### Thresholds
- **Alert:** > 20% (effective 10% after calculation)
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-composio-critical @pagerduty-oncall`
- **Tags:** `service:apollo, env:production, error_type:5xx`

---

## Alert 3: ALB High 5XX Error rate

**Priority:** P1 - Critical  
**Type:** Metric  
**Status:** Active

### Query
```
avg(last_5m):avg:aws.elb.httpcode_elb_5xx{*} > 10
```

### Thresholds
- **Alert:** > 10 errors
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-infrastructure-critical @pagerduty-oncall`
- **Tags:** `service:alb, aws:elb, error_type:5xx`

---

## Alert 4: All tool calls failed in last 15 mins

**Priority:** P1 - Critical  
**Type:** Metric  
**Status:** Active

### Query
```
sum(last_15m):100 * cutoff_min(sum:mercury.tool_call{env:production, error:true} by {toolkit_name,tool_name,toolkit_version}.as_count(), 25) / cutoff_min(sum:mercury.tool_call{env:production} by {toolkit_name,tool_name,toolkit_version}.as_count(), 25) >= 100
```

### Thresholds
- **Alert:** >= 100% (all calls failing)
- **Evaluation Window:** last 15 minutes

### Notifications
- **Alert:** `@slack-composio-critical @pagerduty-oncall`
- **Tags:** `service:mercury, env:production, alert_type:tool_failure`

---

## Alert 5: Apollo Tool Execution Failed Anomaly Monitor

**Priority:** P2 - High  
**Type:** Anomaly Detection  
**Status:** Active

### Query
```
avg(last_4h):anomalies(avg:system.load.1{*}, 'basic', 2, direction='above', interval=60, alert_window='last_15m', count_default_zero='true') >= 1
```

### Thresholds
- **Alert:** >= 1 (anomaly detected)
- **Evaluation Window:** last 4 hours, alert window last 15 minutes

### Notifications
- **Alert:** `@slack-composio-alerts`
- **Tags:** `service:apollo, anomaly:tool_execution`

---

## Alert 6: Apollo Tool Execution Failures - Anomaly Detection

**Priority:** P2 - High  
**Type:** Anomaly Detection  
**Status:** Active

### Query
```
avg(last_4h):anomalies(avg:system.load.1{*}, 'basic', 2, direction='both', interval=60, alert_window='last_15m', count_default_zero='true') >= 0.01
```

### Thresholds
- **Alert:** >= 0.01 (anomaly detected in either direction)
- **Evaluation Window:** last 4 hours, alert window last 15 minutes

### Notifications
- **Alert:** `@slack-composio-alerts`
- **Tags:** `service:apollo, anomaly:tool_execution`

---

## Alert 7: CPU load is high with {{threshold}} on {{ecs_service.name}}

**Priority:** P2 - High  
**Type:** Metric  
**Status:** Active

### Query
```
avg(last_1h):avg:aws.ecs.service.memory_utilization{clustername:prod_cluster} by {servicename} > 75
```

### Thresholds
- **Alert:** > 75%
- **Evaluation Window:** last 1 hour

### Notifications
- **Alert:** `@slack-infrastructure-alerts @pagerduty-oncall`
- **Tags:** `aws:ecs, cluster:prod_cluster, resource:cpu`

---

## Alert 8: Error rate is high on mcp-server production

**Priority:** P1 - Critical  
**Type:** Anomaly Detection  
**Status:** Active

### Query
```
avg(last_1h):anomalies(avg:trace.http.server.request.errors{env:production,service:mcp-server-next}.as_rate(), 'basic', 2, direction='above', alert_window='last_5m', interval=20, count_default_zero='true') >= 0.9
```

### Thresholds
- **Alert:** >= 0.9 (anomaly confidence)
- **Evaluation Window:** last 1 hour, alert window last 5 minutes

### Notifications
- **Alert:** `@slack-composio-critical @pagerduty-oncall`
- **Tags:** `service:mcp-server-next, env:production, anomaly:error_rate`

---

## Alert 9: High Error Rate on {{functionname.name}} in {{region.name}} for {{aws_account.name}}

**Priority:** P2 - High  
**Type:** Metric  
**Status:** Active

### Query
```
sum(last_15m):sum:aws.lambda.errors{*} by {functionname,region,aws_account}.as_count() / sum:aws.lambda.invocations{*} by {functionname,region,aws_account}.as_count() >= 0.1
```

### Thresholds
- **Alert:** >= 10% error rate
- **Evaluation Window:** last 15 minutes

### Notifications
- **Alert:** `@slack-serverless-alerts @pagerduty-oncall`
- **Tags:** `aws:lambda, resource:error_rate`

---

## Alert 10: Important Endpoint 5xx Error rate > {{threshold}}%

**Priority:** P1 - Critical  
**Type:** Trace Analytics  
**Status:** Active

### Query
```
trace-analytics("(count[service:apollo env:production @hono.response.status_code:[500 TO 599] (@hono.request.path:"/api/v3/toolkits" (@hono.request.method:GET AND @hono.request.path:"/api/v3/auth_configs") OR (@hono.request.method:GET AND @hono.request.path:"/api/v3/connected_accounts") OR @hono.request.path:"/api/v3/tools" OR @hono.request.path:"/api/v3/connected_accounts/:nanoid" OR @hono.request.path:"/api/v3/internal/connected_accounts/link/:token" OR @hono.request.path:"/api/v3/tools/:tool_slug")] / max(count[service:apollo env:production (@hono.request.path:"/api/v3/toolkits" (@hono.request.method:GET AND @hono.request.path:"/api/v3/auth_configs") OR (@hono.request.method:GET AND @hono.request.path:"/api/v3/connected_accounts") OR @hono.request.path:"/api/v3/tools" OR @hono.request.path:"/api/v3/tools/execute/:tool_slug" OR @hono.request.path:"/api/v3/connected_accounts/:nanoid" OR @hono.request.path:"/api/v3/internal/connected_accounts/link/:token" OR @hono.request.path:"/api/v3/tools/:tool_slug")], 300)) * 100").last("5m") > 20
```

### Thresholds
- **Alert:** > 20%
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-composio-critical @pagerduty-oncall`
- **Tags:** `service:apollo, env:production, endpoints:critical`

---

## Alert 11: Lambda High Error Rate

**Priority:** P2 - High  
**Type:** Metric  
**Status:** Active

### Query
```
avg(last_5m):sum:aws.lambda.errors{*} / sum:aws.lambda.invocations{*} > 0.05
```

### Thresholds
- **Alert:** > 5% error rate
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-serverless-alerts`
- **Tags:** `aws:lambda, resource:error_rate`

---

## Alert 12: Memory usage on {{servicename.name}} is high with {{threshold}}

**Priority:** P2 - High  
**Type:** Metric  
**Status:** Active

### Query
```
avg(last_1h):avg:aws.ecs.service.memory_utilization{clustername:prod_cluster} by {servicename} > 75
```

### Thresholds
- **Alert:** > 75%
- **Evaluation Window:** last 1 hour

### Notifications
- **Alert:** `@slack-infrastructure-alerts @pagerduty-oncall`
- **Tags:** `aws:ecs, cluster:prod_cluster, resource:memory`

---

## Alert 13: Polling Triggers Workflows are stopping

**Priority:** P1 - Critical  
**Type:** Metric  
**Status:** Active

### Query
```
avg(last_5m):per_hour(sum:temporal_workflow_completed{namespace:polling-prod.kl3mw,workflow_type:polltriggerworkflow}) / 60 > 10
```

### Thresholds
- **Alert:** > 10 completions per minute
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-composio-critical @pagerduty-oncall`
- **Tags:** `service:temporal, workflow:polling, namespace:polling-prod`

---

## Alert 14: Thermos HTTP Request Errors >1%

**Priority:** P2 - High  
**Type:** Metric  
**Status:** Active

### Query
```
sum(last_5m):sum:trace.http.request.errors{env:production, service:thermos}.as_count() / sum:trace.http.request.hits{env:production, service:thermos}.as_count() * 100 > 1
```

### Thresholds
- **Alert:** > 1% error rate
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-composio-alerts`
- **Tags:** `service:thermos, env:production, error_type:http`

---

## Alert 15: Tool anomaly alert

**Priority:** P2 - High  
**Type:** Anomaly Detection  
**Status:** Active

### Query
```
avg(last_4h):anomalies(cutoff_min(sum:mercury.tool_call{env:production, error:true} by {toolkit_name,tool_name}.as_count(), 5) / cutoff_min(sum:mercury.tool_call{env:production} by {toolkit_name,tool_name}.as_count(), 5) * 100, 'basic', 2, direction='both', interval=60, alert_window='last_15m', count_default_zero='true') >= 1
```

### Thresholds
- **Alert:** >= 1 (anomaly detected)
- **Evaluation Window:** last 4 hours, alert window last 15 minutes

### Notifications
- **Alert:** `@slack-composio-alerts`
- **Tags:** `service:mercury, env:production, anomaly:tool_errors`

---

## Alert 16: [AWS] RDS CPU utilization is high

**Priority:** P1 - Critical  
**Type:** Metric  
**Status:** Active

### Query
```
max(last_15m):avg:aws.rds.cpuutilization{! dbinstanceidentifier:stagingrds} by {dbinstanceidentifier} > 80
```

### Thresholds
- **Alert:** > 80%
- **Evaluation Window:** last 15 minutes

### Notifications
- **Alert:** `@slack-database-critical @pagerduty-dba`
- **Tags:** `aws:rds, resource:cpu`

---

## Alert 17: [AWS] RDS Storage utilization is high

**Priority:** P1 - Critical  
**Type:** Metric  
**Status:** Active

### Query
```
avg(last_15m):100 - ((avg:aws.rds.free_storage_space{*} by {dbinstanceidentifier,engine} / avg:aws.rds.total_storage_space{*} by {dbinstanceidentifier,engine}) * 100) > 90
```

### Thresholds
- **Alert:** > 90% storage used
- **Evaluation Window:** last 15 minutes

### Notifications
- **Alert:** `@slack-database-critical @pagerduty-dba`
- **Tags:** `aws:rds, resource:storage`

---

## Alert 18: [Mercury] OTA Module Load Failures

**Priority:** P2 - High  
**Type:** Log Analytics  
**Status:** Active

### Query
```
logs("\"No module named 'ota'\" env:production").index("*").rollup("count").last("5m") > 1
```

### Thresholds
- **Alert:** > 1 occurrence
- **Evaluation Window:** last 5 minutes

### Notifications
- **Alert:** `@slack-composio-alerts`
- **Tags:** `service:mercury, env:production, error_type:module_load`

---

## Quick Reference Table

| # | Alert Name | Priority | Type | Threshold | Service | Status |
|---|------------|----------|------|-----------|---------|--------|
| 1 | 4xx Error rate > 50% | P2 | Trace | > 200% | Apollo | Active |
| 2 | 5xx Error rate > 10% | P1 | Trace | > 20% | Apollo | Active |
| 3 | ALB High 5XX Error | P1 | Metric | > 10 | ALB | Active |
| 4 | All tool calls failed | P1 | Metric | >= 100% | Mercury | Active |
| 5 | Apollo Tool Exec Anomaly | P2 | Anomaly | >= 1 | Apollo | Active |
| 6 | Apollo Tool Failures Anomaly | P2 | Anomaly | >= 0.01 | Apollo | Active |
| 7 | CPU load high on ECS | P2 | Metric | > 75% | ECS | Active |
| 8 | MCP Server Error Rate | P1 | Anomaly | >= 0.9 | MCP | Active |
| 9 | Lambda High Error Rate | P2 | Metric | >= 10% | Lambda | Active |
| 10 | Important Endpoint 5xx | P1 | Trace | > 20% | Apollo | Active |
| 11 | Lambda High Error Rate | P2 | Metric | > 5% | Lambda | Active |
| 12 | Memory usage high on ECS | P2 | Metric | > 75% | ECS | Active |
| 13 | Polling Triggers Stopping | P1 | Metric | > 10/min | Temporal | Active |
| 14 | Thermos HTTP Errors | P2 | Metric | > 1% | Thermos | Active |
| 15 | Tool anomaly | P2 | Anomaly | >= 1 | Mercury | Active |
| 16 | RDS CPU utilization high | P1 | Metric | > 80% | RDS | Active |
| 17 | RDS Storage high | P1 | Metric | > 90% | RDS | Active |
| 18 | Mercury OTA Module Load | P2 | Log | > 1 | Mercury | Active |

---

## Notes

- All alerts are configured for production environment
- Critical (P1) alerts trigger PagerDuty notifications
- Alert thresholds should be reviewed quarterly
- Update notification channels as team structure changes

