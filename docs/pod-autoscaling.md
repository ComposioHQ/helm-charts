# Pod autoscaling

Regular Kubernetes Deployments support optional CPU/memory Horizontal Pod
Autoscalers (HPA) for Apollo, Thermos, Mercury, toolkit registry, eGateway admin
and eGateway proxy. Autoscaling is disabled by default. Each workload has an
independent `autoscaling` block; enabling gateway autoscaling only creates HPAs
when `egateway.enabled` is also true.

`composio/values-autoscaling.yaml` is an opt-in profile for these six workloads:
2–10 replicas, 70% CPU and 80% memory utilization targets. Merge it over the
installation's existing values. In Managed VPC customer configuration, these
values belong under `application.values`, then go through the normal preview
and customer-approved deployment. Saving configuration alone does not deploy it.

```yaml
application:
  values:
    mercury:
      useKnative: false
      autoscaling:
        enabled: true
        minReplicas: 2
        maxReplicas: 10
        targetCPUUtilizationPercentage: 70
        targetMemoryUtilizationPercentage: 80
    toolkitRegistry:
      autoscaling:
        enabled: true
        minReplicas: 2
        maxReplicas: 10
    egateway:
      admin:
        autoscaling:
          enabled: true
      proxy:
        autoscaling:
          enabled: true
```

Use `apollo.autoscaling`, `thermos.autoscaling`, `mercury.autoscaling`,
`toolkitRegistry.autoscaling`, `egateway.admin.autoscaling` and
`egateway.proxy.autoscaling` in Helm values. The new HPA settings use the same
scaling-policy fields as Apollo/Thermos: `scaleDownStabilizationWindowSeconds`,
`scaleDownPercent`, `scaleDownPeriodSeconds`, `scaleUpStabilizationWindowSeconds`,
`scaleUpPercent`, `scaleUpPeriodSeconds` and `scaleUpPods`. Defaults are a
five-minute scale-down stabilization window with 10% removed per minute, and a
one-minute scale-up window with the larger of 100% or four pods added per
15 seconds. Set a CPU or memory target to `null` to disable that metric; at
least one target is required. Memory-based scaling can keep cache/heap-heavy
workloads scaled out even after traffic falls, so CPU-only scaling is available.

The cluster must provide the `metrics.k8s.io` resource metrics API, usually
through [Metrics Server](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#support-for-metrics-apis).
Containers need CPU/memory requests for the corresponding utilization metrics.
This chart does not install a cluster metrics provider or a node autoscaler.

When HPA is enabled, the Deployment omits `spec.replicas` so subsequent Helm
upgrades do not reset the autoscaler's count. Enabling HPA for an existing
Deployment can briefly reset replicas to Kubernetes' default of one during
the first handoff; review that transition in the deployment window. Disabling
HPA restores the configured `replicaCount`.

Mercury's existing Knative mode retains `autoscaling.minScale`, `maxScale` and
`target`; the Deployment HPA is never created when `mercury.useKnative: true`.
Toolkit registry replicas each serve the same read-only data baked into their
image; no database replication or shared writable volume is added. FusionAuth,
OpenSearch, migration jobs and scheduled jobs retain their existing settings.

After the approved deployment, check `kubectl get hpa -n <namespace>` and
`kubectl describe hpa -n <namespace> <name>`. The HPA must report available
metrics and `ScalingActive=True`; creating the resource alone does not verify
working autoscaling.
