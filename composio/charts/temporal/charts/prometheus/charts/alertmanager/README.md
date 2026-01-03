# alertmanager

![Version: 1.11.0](https://img.shields.io/badge/Version-1.11.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.27.0](https://img.shields.io/badge/AppVersion-v0.27.0-informational?style=flat-square)

The Alertmanager handles alerts sent by client applications such as the Prometheus server.

**Homepage:** <https://prometheus.io/>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| monotek | <monotek23@gmail.com> |  |
| naseemkullah | <naseem@transit.app> |  |

## Source Code

* <https://github.com/prometheus/alertmanager>

## Requirements

Kubernetes: `>=1.19.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalPeers | list | `[]` |  |
| affinity | object | `{}` |  |
| automountServiceAccountToken | bool | `true` |  |
| baseURL | string | `""` |  |
| command | list | `[]` |  |
| config.enabled | bool | `true` |  |
| config.global | object | `{}` |  |
| config.receivers[0].name | string | `"default-receiver"` |  |
| config.route.group_interval | string | `"5m"` |  |
| config.route.group_wait | string | `"10s"` |  |
| config.route.receiver | string | `"default-receiver"` |  |
| config.route.repeat_interval | string | `"3h"` |  |
| config.templates[0] | string | `"/etc/alertmanager/*.tmpl"` |  |
| configAnnotations | object | `{}` |  |
| configmapReload.enabled | bool | `false` |  |
| configmapReload.extraArgs | object | `{}` |  |
| configmapReload.extraEnv | list | `[]` |  |
| configmapReload.extraVolumeMounts | list | `[]` |  |
| configmapReload.image.pullPolicy | string | `"IfNotPresent"` |  |
| configmapReload.image.repository | string | `"quay.io/prometheus-operator/prometheus-config-reloader"` |  |
| configmapReload.image.tag | string | `"v0.66.0"` |  |
| configmapReload.name | string | `"configmap-reload"` |  |
| configmapReload.resources | object | `{}` |  |
| configmapReload.securityContext | object | `{}` |  |
| dnsConfig | object | `{}` |  |
| extraArgs | object | `{}` |  |
| extraContainers | list | `[]` |  |
| extraEnv | list | `[]` |  |
| extraInitContainers | list | `[]` |  |
| extraSecretMounts | list | `[]` |  |
| extraVolumeMounts | list | `[]` |  |
| extraVolumes | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| hostAliases | list | `[]` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"quay.io/prometheus/alertmanager"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"alertmanager.domain.com"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| ingressPerReplica.annotations | object | `{}` |  |
| ingressPerReplica.className | string | `""` |  |
| ingressPerReplica.enabled | bool | `false` |  |
| ingressPerReplica.hostDomain | string | `"domain.com"` |  |
| ingressPerReplica.hostPrefix | string | `"alertmanager"` |  |
| ingressPerReplica.labels | object | `{}` |  |
| ingressPerReplica.pathType | string | `"ImplementationSpecific"` |  |
| ingressPerReplica.paths[0] | string | `"/"` |  |
| ingressPerReplica.tlsSecretName | string | `""` |  |
| ingressPerReplica.tlsSecretPerReplica.enabled | bool | `false` |  |
| ingressPerReplica.tlsSecretPerReplica.prefix | string | `"alertmanager"` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| minReadySeconds | int | `0` |  |
| nameOverride | string | `""` |  |
| namespaceOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| persistence.accessModes[0] | string | `"ReadWriteOnce"` |  |
| persistence.enabled | bool | `true` |  |
| persistence.size | string | `"50Mi"` |  |
| podAnnotations | object | `{}` |  |
| podAntiAffinity | string | `""` |  |
| podAntiAffinityTopologyKey | string | `"kubernetes.io/hostname"` |  |
| podDisruptionBudget | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext.fsGroup | int | `65534` |  |
| priorityClassName | string | `""` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | string | `"http"` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| revisionHistoryLimit | int | `10` |  |
| schedulerName | string | `""` |  |
| securityContext.runAsGroup | int | `65534` |  |
| securityContext.runAsNonRoot | bool | `true` |  |
| securityContext.runAsUser | int | `65534` |  |
| service.annotations | object | `{}` |  |
| service.clusterPort | int | `9094` |  |
| service.extraPorts | list | `[]` |  |
| service.ipDualStack.enabled | bool | `false` |  |
| service.ipDualStack.ipFamilies[0] | string | `"IPv6"` |  |
| service.ipDualStack.ipFamilies[1] | string | `"IPv4"` |  |
| service.ipDualStack.ipFamilyPolicy | string | `"PreferDualStack"` |  |
| service.labels | object | `{}` |  |
| service.loadBalancerIP | string | `""` |  |
| service.loadBalancerSourceRanges | list | `[]` |  |
| service.port | int | `9093` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| servicePerReplica.annotations | object | `{}` |  |
| servicePerReplica.enabled | bool | `false` |  |
| servicePerReplica.externalTrafficPolicy | string | `"Cluster"` |  |
| servicePerReplica.loadBalancerSourceRanges | list | `[]` |  |
| servicePerReplica.type | string | `"ClusterIP"` |  |
| statefulSet.annotations | object | `{}` |  |
| templates | object | `{}` |  |
| testFramework.annotations."helm.sh/hook" | string | `"test-success"` |  |
| testFramework.enabled | bool | `false` |  |
| tolerations | list | `[]` |  |
| topologySpreadConstraints | list | `[]` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
