# kube-state-metrics

![Version: 5.20.0](https://img.shields.io/badge/Version-5.20.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.12.0](https://img.shields.io/badge/AppVersion-2.12.0-informational?style=flat-square)

Install kube-state-metrics to generate and expose cluster-level metrics

**Homepage:** <https://github.com/kubernetes/kube-state-metrics/>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| tariq1890 | <tariq.ibrahim@mulesoft.com> |  |
| mrueg | <manuel@rueg.eu> |  |
| dotdc | <david@0xdc.me> |  |

## Source Code

* <https://github.com/kubernetes/kube-state-metrics/>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| annotations | object | `{}` |  |
| autosharding.enabled | bool | `false` |  |
| collectors[0] | string | `"certificatesigningrequests"` |  |
| collectors[10] | string | `"limitranges"` |  |
| collectors[11] | string | `"mutatingwebhookconfigurations"` |  |
| collectors[12] | string | `"namespaces"` |  |
| collectors[13] | string | `"networkpolicies"` |  |
| collectors[14] | string | `"nodes"` |  |
| collectors[15] | string | `"persistentvolumeclaims"` |  |
| collectors[16] | string | `"persistentvolumes"` |  |
| collectors[17] | string | `"poddisruptionbudgets"` |  |
| collectors[18] | string | `"pods"` |  |
| collectors[19] | string | `"replicasets"` |  |
| collectors[1] | string | `"configmaps"` |  |
| collectors[20] | string | `"replicationcontrollers"` |  |
| collectors[21] | string | `"resourcequotas"` |  |
| collectors[22] | string | `"secrets"` |  |
| collectors[23] | string | `"services"` |  |
| collectors[24] | string | `"statefulsets"` |  |
| collectors[25] | string | `"storageclasses"` |  |
| collectors[26] | string | `"validatingwebhookconfigurations"` |  |
| collectors[27] | string | `"volumeattachments"` |  |
| collectors[2] | string | `"cronjobs"` |  |
| collectors[3] | string | `"daemonsets"` |  |
| collectors[4] | string | `"deployments"` |  |
| collectors[5] | string | `"endpoints"` |  |
| collectors[6] | string | `"horizontalpodautoscalers"` |  |
| collectors[7] | string | `"ingresses"` |  |
| collectors[8] | string | `"jobs"` |  |
| collectors[9] | string | `"leases"` |  |
| containerSecurityContext.allowPrivilegeEscalation | bool | `false` |  |
| containerSecurityContext.capabilities.drop[0] | string | `"ALL"` |  |
| containerSecurityContext.readOnlyRootFilesystem | bool | `true` |  |
| containers | list | `[]` |  |
| customLabels | object | `{}` |  |
| customResourceState.config | object | `{}` |  |
| customResourceState.enabled | bool | `false` |  |
| extraArgs | list | `[]` |  |
| extraManifests | list | `[]` |  |
| global.imagePullSecrets | list | `[]` |  |
| global.imageRegistry | string | `""` |  |
| hostNetwork | bool | `false` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.registry | string | `"registry.k8s.io"` |  |
| image.repository | string | `"kube-state-metrics/kube-state-metrics"` |  |
| image.sha | string | `""` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| initContainers | list | `[]` |  |
| kubeRBACProxy.containerSecurityContext.allowPrivilegeEscalation | bool | `false` |  |
| kubeRBACProxy.containerSecurityContext.capabilities.drop[0] | string | `"ALL"` |  |
| kubeRBACProxy.containerSecurityContext.readOnlyRootFilesystem | bool | `true` |  |
| kubeRBACProxy.enabled | bool | `false` |  |
| kubeRBACProxy.extraArgs | list | `[]` |  |
| kubeRBACProxy.image.pullPolicy | string | `"IfNotPresent"` |  |
| kubeRBACProxy.image.registry | string | `"quay.io"` |  |
| kubeRBACProxy.image.repository | string | `"brancz/kube-rbac-proxy"` |  |
| kubeRBACProxy.image.sha | string | `""` |  |
| kubeRBACProxy.image.tag | string | `"v0.18.0"` |  |
| kubeRBACProxy.resources | object | `{}` |  |
| kubeRBACProxy.volumeMounts | list | `[]` |  |
| kubeTargetVersionOverride | string | `""` |  |
| kubeconfig.enabled | bool | `false` |  |
| kubeconfig.secret | string | `nil` |  |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.httpHeaders | list | `[]` |  |
| livenessProbe.httpGet.scheme | string | `"http"` |  |
| livenessProbe.initialDelaySeconds | int | `5` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| livenessProbe.successThreshold | int | `1` |  |
| livenessProbe.timeoutSeconds | int | `5` |  |
| metricAllowlist | list | `[]` |  |
| metricAnnotationsAllowList | list | `[]` |  |
| metricDenylist | list | `[]` |  |
| metricLabelsAllowlist | list | `[]` |  |
| namespaceOverride | string | `""` |  |
| namespaces | string | `""` |  |
| namespacesDenylist | string | `""` |  |
| networkPolicy.enabled | bool | `false` |  |
| networkPolicy.flavor | string | `"kubernetes"` | Flavor of the network policy to use. Can be: * kubernetes for networking.k8s.io/v1/NetworkPolicy * cilium     for cilium.io/v2/CiliumNetworkPolicy |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podDisruptionBudget | object | `{}` |  |
| podSecurityPolicy.additionalVolumes | list | `[]` |  |
| podSecurityPolicy.annotations | object | `{}` |  |
| podSecurityPolicy.enabled | bool | `false` |  |
| prometheus.monitor.additionalLabels | object | `{}` |  |
| prometheus.monitor.annotations | object | `{}` |  |
| prometheus.monitor.enabled | bool | `false` |  |
| prometheus.monitor.http.bearerTokenFile | string | `""` |  |
| prometheus.monitor.http.bearerTokenSecret | object | `{}` |  |
| prometheus.monitor.http.enableHttp2 | bool | `false` |  |
| prometheus.monitor.http.honorLabels | bool | `false` |  |
| prometheus.monitor.http.interval | string | `""` |  |
| prometheus.monitor.http.metricRelabelings | list | `[]` |  |
| prometheus.monitor.http.proxyUrl | string | `""` |  |
| prometheus.monitor.http.relabelings | list | `[]` |  |
| prometheus.monitor.http.scheme | string | `""` |  |
| prometheus.monitor.http.scrapeTimeout | string | `""` |  |
| prometheus.monitor.http.tlsConfig | object | `{}` |  |
| prometheus.monitor.jobLabel | string | `""` |  |
| prometheus.monitor.labelLimit | int | `0` |  |
| prometheus.monitor.labelNameLengthLimit | int | `0` |  |
| prometheus.monitor.labelValueLengthLimit | int | `0` |  |
| prometheus.monitor.metrics.bearerTokenFile | string | `""` |  |
| prometheus.monitor.metrics.bearerTokenSecret | object | `{}` |  |
| prometheus.monitor.metrics.enableHttp2 | bool | `false` |  |
| prometheus.monitor.metrics.honorLabels | bool | `false` |  |
| prometheus.monitor.metrics.interval | string | `""` |  |
| prometheus.monitor.metrics.metricRelabelings | list | `[]` |  |
| prometheus.monitor.metrics.proxyUrl | string | `""` |  |
| prometheus.monitor.metrics.relabelings | list | `[]` |  |
| prometheus.monitor.metrics.scheme | string | `""` |  |
| prometheus.monitor.metrics.scrapeTimeout | string | `""` |  |
| prometheus.monitor.metrics.tlsConfig | object | `{}` |  |
| prometheus.monitor.namespace | string | `""` |  |
| prometheus.monitor.namespaceSelector | list | `[]` |  |
| prometheus.monitor.podTargetLabels | list | `[]` |  |
| prometheus.monitor.sampleLimit | int | `0` |  |
| prometheus.monitor.selectorOverride | object | `{}` |  |
| prometheus.monitor.targetLabels | list | `[]` |  |
| prometheus.monitor.targetLimit | int | `0` |  |
| prometheusScrape | bool | `true` |  |
| rbac.create | bool | `true` |  |
| rbac.extraRules | list | `[]` |  |
| rbac.useClusterRole | bool | `true` |  |
| readinessProbe.failureThreshold | int | `3` |  |
| readinessProbe.httpGet.httpHeaders | list | `[]` |  |
| readinessProbe.httpGet.scheme | string | `"http"` |  |
| readinessProbe.initialDelaySeconds | int | `5` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.successThreshold | int | `1` |  |
| readinessProbe.timeoutSeconds | int | `5` |  |
| releaseLabel | bool | `false` |  |
| releaseNamespace | bool | `false` |  |
| replicas | int | `1` |  |
| resources | object | `{}` |  |
| revisionHistoryLimit | int | `10` |  |
| securityContext.enabled | bool | `true` |  |
| securityContext.fsGroup | int | `65534` |  |
| securityContext.runAsGroup | int | `65534` |  |
| securityContext.runAsNonRoot | bool | `true` |  |
| securityContext.runAsUser | int | `65534` |  |
| securityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| selectorOverride | object | `{}` |  |
| selfMonitor.enabled | bool | `false` |  |
| service.annotations | object | `{}` |  |
| service.clusterIP | string | `""` |  |
| service.ipDualStack.enabled | bool | `false` |  |
| service.ipDualStack.ipFamilies[0] | string | `"IPv6"` |  |
| service.ipDualStack.ipFamilies[1] | string | `"IPv4"` |  |
| service.ipDualStack.ipFamilyPolicy | string | `"PreferDualStack"` |  |
| service.loadBalancerIP | string | `""` |  |
| service.loadBalancerSourceRanges | list | `[]` |  |
| service.nodePort | int | `0` |  |
| service.port | int | `8080` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.imagePullSecrets | list | `[]` |  |
| serviceAccount.name | string | `nil` |  |
| tolerations | list | `[]` |  |
| topologySpreadConstraints | list | `[]` |  |
| verticalPodAutoscaler.controlledResources | list | `[]` |  |
| verticalPodAutoscaler.enabled | bool | `false` |  |
| verticalPodAutoscaler.maxAllowed | object | `{}` |  |
| verticalPodAutoscaler.minAllowed | object | `{}` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
