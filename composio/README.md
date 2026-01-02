# composio

![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.1.0](https://img.shields.io/badge/AppVersion-1.1.0-informational?style=flat-square)

A Helm chart for Composio

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://./charts/temporal | temporal(temporal) | 0.68.1 |
| https://charts.bitnami.com/bitnami | redis | 17.11.3 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| apollo.autoscaling.enabled | bool | `false` | Enable HPA |
| apollo.autoscaling.maxReplicas | int | `10` | Maximum number of replicas |
| apollo.autoscaling.minReplicas | int | `2` | Minimum number of replicas |
| apollo.autoscaling.scaleDownPercent | int | `10` | Scale down percentage |
| apollo.autoscaling.scaleDownPeriodSeconds | int | `60` | Scale down period (seconds) |
| apollo.autoscaling.scaleDownStabilizationWindowSeconds | int | `300` | Stabilization window for scale down (seconds) |
| apollo.autoscaling.scaleUpPercent | int | `100` | Scale up percentage |
| apollo.autoscaling.scaleUpPeriodSeconds | int | `15` | Scale up period (seconds) |
| apollo.autoscaling.scaleUpPods | int | `4` | Number of pods to scale up at once |
| apollo.autoscaling.scaleUpStabilizationWindowSeconds | int | `60` | Stabilization window for scale up (seconds) |
| apollo.autoscaling.targetCPUUtilizationPercentage | int | `70` | Target CPU utilization percentage |
| apollo.autoscaling.targetMemoryUtilizationPercentage | int | `80` | Target memory utilization percentage |
| apollo.database.urlSecret.key | string | `"url"` | Key name in the secret |
| apollo.database.urlSecret.name | string | `"external-postgres-secret"` | Secret name containing database URL |
| apollo.dbInit.enabled | bool | `true` | Enable database initialization |
| apollo.dbInit.image.pullPolicy | string | `"Always"` | Image pull policy |
| apollo.dbInit.image.repository | string | `"composio-self-host/apollo-db-init"` | Database init image repository |
| apollo.dbInit.image.tag | string | `"release-20251209_00"` | Database init image tag |
| apollo.image.pullPolicy | string | `"Always"` | Image pull policy |
| apollo.image.repository | string | `"composio-self-host/apollo"` | Apollo image repository |
| apollo.image.tag | string | `"release-20251209_00"` | Apollo image tag |
| apollo.ingress.annotations | object | `{}` | Ingress annotations |
| apollo.ingress.className | string | `""` | Ingress class name |
| apollo.ingress.enabled | bool | `false` | Enable ingress |
| apollo.ingress.host | string | `"abc.example.com"` | Hostname for Apollo ingress |
| apollo.ingress.tls | list | `[]` | TLS configuration |
| apollo.objectStorage.accessKey.key | string | `"S3_ACCESS_KEY_ID"` | Key name in the secret |
| apollo.objectStorage.accessKey.secretName | string | `"s3-cred"` | Secret name containing S3 access key |
| apollo.objectStorage.azureConnectionString.key | string | `"AZURE_CONNECTION_STRING"` | Key name in the secret |
| apollo.objectStorage.azureConnectionString.secretName | string | `"azure-cred"` | Secret name containing Azure connection string |
| apollo.objectStorage.backend | string | `"s3"` | Storage backend type (s3 or azure_blob_storage) |
| apollo.objectStorage.namespaces.permanent | string | `"composio-permanent"` | Bucket/container for permanent files |
| apollo.objectStorage.namespaces.temp | string | `"composio-temp"` | Bucket/container for temporary files |
| apollo.objectStorage.secretKey.key | string | `"S3_SECRET_ACCESS_KEY"` | Key name in the secret |
| apollo.objectStorage.secretKey.secretName | string | `"s3-cred"` | Secret name containing S3 secret key |
| apollo.replicaCount | int | `2` | Number of Apollo pod replicas |
| apollo.resources.limits.cpu | string | `"1"` | CPU limit for Apollo |
| apollo.resources.limits.memory | string | `"6Gi"` | Memory limit for Apollo |
| apollo.resources.requests.cpu | string | `"1"` | CPU request for Apollo |
| apollo.resources.requests.memory | string | `"5Gi"` | Memory request for Apollo |
| apollo.service.nodePort | int | `30900` | NodePort for external access (only applicable when type is NodePort) |
| apollo.service.port | int | `9900` | Service port |
| apollo.service.type | string | `"NodePort"` | Service type (ClusterIP, NodePort, LoadBalancer) |
| apollo.serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| apollo.serviceAccount.enabled | bool | `false` | Enable service account creation |
| apollo.serviceAccount.labels | object | `{}` | Labels to add to the service account |
| apollo.serviceAccount.name | string | `"composio-apollo"` | Name of the service account to create or use |
| apollo.smtp.enabled | bool | `false` | Enable SMTP |
| apollo.smtp.key | string | `"SMTP_CONNECTION_STRING"` | Key name in the secret |
| apollo.smtp.secretRef | string | `"connectionstring"` | Secret reference containing SMTP connection string |
| apollo.smtp.smtpAuthorEmail | string | `"admin@yourdomain.com"` | Email address for outgoing emails |
| aws.lambda.functionName | string | `"mercury"` | Lambda function name |
| aws.region | string | `"us-east-1"` | AWS region |
| aws.s3.lambdaBucketName | string | `"tools"` | S3 bucket name for Lambda functions |
| cassandra.enabled | bool | `false` | Enable Cassandra |
| dbInit.adminEmail | string | `"hello@composio.dev"` | Admin email for initial setup |
| dbInit.job.activeDeadlineSeconds | int | `2400` | Maximum time for job execution (seconds) |
| dbInit.job.backoffLimit | int | `3` | Maximum number of retries for failed jobs |
| dbInit.job.restartPolicy | string | `"OnFailure"` | Job restart policy |
| elasticsearch.enabled | bool | `false` | Enable Elasticsearch |
| externalRedis.enabled | bool | `true` | Enable external Redis. Set to true to use an external Redis instance |
| externalRedis.key | string | `"url"` | Key name in the secret containing the Redis URL |
| externalRedis.secretRef | string | `"redis-cred"` | Secret name containing Redis connection URL |
| externalSecrets.ecr.server | string | `"008971668139.dkr.ecr.us-east-1.amazonaws.com"` | ECR server URL |
| externalSecrets.ecr.token | string | `""` |  |
| externalSecrets.ecr.username | string | `"AWS"` | ECR username (typically "AWS") |
| frontend.enabled | bool | `false` | Enable frontend service |
| frontend.env.NEXT_PUBLIC_DISABLE_SOCIAL_LOGIN | string | `"true"` | Disable social login for self-hosted deployments |
| frontend.env.NEXT_PUBLIC_SELF_HOSTED | string | `"true"` | Enable self-hosted mode |
| frontend.env.NODE_ENV | string | `"production"` | Node environment |
| frontend.env.OVERRIDE_BACKEND_URL | string | `""` | Override backend URL (defaults to Apollo service URL) |
| frontend.env.PORT | string | `"3000"` | Server port |
| frontend.image.pullPolicy | string | `"Always"` | Image pull policy |
| frontend.image.repository | string | `"composio-self-host/frontend"` | Frontend image repository |
| frontend.image.tag | string | `"latest"` | Frontend image tag |
| frontend.ingress.annotations | object | `{}` | Ingress annotations |
| frontend.ingress.className | string | `""` | Ingress class name |
| frontend.ingress.enabled | bool | `false` | Enable ingress |
| frontend.ingress.host | string | `""` | Hostname for frontend ingress |
| frontend.ingress.tls | list | `[]` | TLS configuration |
| frontend.replicaCount | int | `1` | Number of frontend pod replicas |
| frontend.resources.limits.cpu | string | `"1"` | CPU limit for frontend |
| frontend.resources.limits.memory | string | `"3Gi"` | Memory limit for frontend |
| frontend.resources.requests.cpu | string | `"1"` | CPU request for frontend |
| frontend.resources.requests.memory | string | `"2Gi"` | Memory request for frontend |
| frontend.service.port | int | `3000` | Service port |
| frontend.service.type | string | `"ClusterIP"` | Service type |
| global.domain | string | `"localhost"` | Domain name for the deployment |
| global.environment | string | `"development"` | Environment name (e.g., development, staging, production) |
| global.imagePullSecrets | list | `[{"name":"ecr-secret"}]` | Image pull secrets for private registries |
| global.registry.name | string | `"008971668139.dkr.ecr.us-east-1.amazonaws.com"` | ECR registry URL |
| grafana.enabled | bool | `false` | Enable Grafana |
| grafana.replicas | int | `1` | Number of Grafana replicas |
| ingress.enabled | bool | `false` | Enable ingress |
| mercury.autoscaling.maxScale | int | `10` | Maximum number of replicas |
| mercury.autoscaling.minScale | int | `1` | Minimum number of replicas |
| mercury.autoscaling.target | int | `80` | Target metric value for autoscaling |
| mercury.awsLambda.enabled | bool | `false` | Enable AWS Lambda deployment |
| mercury.awsLambda.secretRef.name | string | `"lambda-cred"` | Secret name for Lambda credentials |
| mercury.containerConcurrency | int | `0` | Container concurrency (0 = unlimited) |
| mercury.enabled | bool | `true` | Enable Mercury service |
| mercury.image.pullPolicy | string | `"Always"` | Image pull policy |
| mercury.image.repository | string | `"composio-self-host/mercury"` | Mercury image repository |
| mercury.image.tag | string | `"release-20251209_00"` | Mercury image tag |
| mercury.ingress.annotations | object | `{}` | Ingress annotations |
| mercury.ingress.className | string | `""` | Ingress class name |
| mercury.ingress.enabled | bool | `false` | Enable ingress |
| mercury.ingress.host | string | `""` | Hostname for Mercury ingress |
| mercury.ingress.tls | list | `[]` | TLS configuration |
| mercury.knative.maxReplicas | int | `5` | Maximum number of replicas for Knative |
| mercury.knative.minReplicas | int | `1` | Minimum number of replicas for Knative |
| mercury.knative.replicas | int | `2` | Initial number of replicas |
| mercury.livenessProbe.enabled | bool | `false` | Enable liveness probe |
| mercury.readinessProbe.enabled | bool | `false` | Enable readiness probe |
| mercury.replicaCount | int | `1` | Number of Mercury pod replicas (when not using Knative) |
| mercury.resources.limits.cpu | string | `"2"` | CPU limit for Mercury |
| mercury.resources.limits.memory | string | `"4Gi"` | Memory limit for Mercury |
| mercury.resources.requests.cpu | string | `"1"` | CPU request for Mercury |
| mercury.resources.requests.memory | string | `"2Gi"` | Memory request for Mercury |
| mercury.securityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation |
| mercury.securityContext.capabilities.drop | list | `["ALL"]` | Drop all capabilities |
| mercury.securityContext.runAsNonRoot | bool | `true` | Run as non-root user |
| mercury.securityContext.runAsUser | int | `1000` | User ID to run as |
| mercury.securityContext.seccompProfile.type | string | `"RuntimeDefault"` | Seccomp profile type |
| mercury.service.port | int | `8080` | Service port |
| mercury.service.type | string | `"ClusterIP"` | Service type |
| mercury.timeoutSeconds | int | `300` | Request timeout in seconds |
| mercury.useKnative | bool | `false` | Use Knative for serverless deployment |
| mercury.volumeMounts | list | `[]` | Additional volume mounts |
| mercury.volumes | list | `[]` | Additional volumes |
| namespace.create | bool | `false` | Whether to create namespaces automatically |
| namespace.name | string | `"composio"` | Name of the namespace where Composio services will be deployed (defaults to "composio" if not specified) |
| openAI.enabled | bool | `true` | Enable OpenAI integration |
| openAI.key | string | `"API_KEY"` | Key name in the secret |
| openAI.secretRef | string | `"openai-cred"` | Secret name containing OpenAI API key |
| otel.apollo.metricsEndpoint | string | `"http://composio-otel-collector:4318/v1/metrics"` | HTTP endpoint for metrics |
| otel.apollo.serviceName | string | `"apollo"` | Apollo service name |
| otel.apollo.serviceVersion | string | `"1.0.0"` | Apollo service version |
| otel.collector.config.exporters.debug.verbosity | string | `"basic"` | Debug verbosity level |
| otel.collector.config.exporters.googlecloud.metric.prefix | string | `"custom.googleapis.com/composio/"` | Custom metrics prefix |
| otel.collector.config.exporters.googlecloud.project | string | `"self-host-kubernetes"` | GCP project ID |
| otel.collector.config.exporters.googlecloud.trace | object | `{}` |  |
| otel.collector.config.exporters.prometheus.endpoint | string | `"0.0.0.0:8889"` | Prometheus endpoint |
| otel.collector.config.extensions.health_check.endpoint | string | `"0.0.0.0:13133"` | Health check endpoint |
| otel.collector.config.extensions.pprof.endpoint | string | `"0.0.0.0:1777"` | Profiling endpoint |
| otel.collector.config.extensions.zpages.endpoint | string | `"0.0.0.0:55679"` | Zpages endpoint |
| otel.collector.config.processors.batch.send_batch_size | int | `1024` | Batch size |
| otel.collector.config.processors.batch.timeout | string | `"1s"` | Batch timeout |
| otel.collector.config.processors.memory_limiter.check_interval | string | `"1s"` | Check interval |
| otel.collector.config.processors.memory_limiter.limit_mib | int | `512` | Memory limit in MiB |
| otel.collector.config.receivers.jaeger.protocols.grpc.endpoint | string | `"0.0.0.0:14250"` | Jaeger gRPC endpoint |
| otel.collector.config.receivers.otlp.protocols.grpc.endpoint | string | `"0.0.0.0:4317"` | OTLP gRPC endpoint |
| otel.collector.config.receivers.otlp.protocols.http.endpoint | string | `"0.0.0.0:4318"` | OTLP HTTP endpoint |
| otel.collector.config.service.extensions | list | `["health_check","pprof","zpages"]` | Extensions to enable |
| otel.collector.config.service.pipelines.metrics.exporters | list | `["debug","prometheus"]` | Metrics exporters |
| otel.collector.config.service.pipelines.metrics.processors | list | `["memory_limiter","batch"]` | Metrics processors |
| otel.collector.config.service.pipelines.metrics.receivers | list | `["otlp"]` | Metrics receivers |
| otel.collector.config.service.pipelines.traces.exporters | list | `["debug"]` | Trace exporters |
| otel.collector.config.service.pipelines.traces.processors | list | `["memory_limiter","batch"]` | Trace processors |
| otel.collector.config.service.pipelines.traces.receivers | list | `["otlp","jaeger"]` | Trace receivers |
| otel.collector.enabled | bool | `true` | Enable OTEL collector |
| otel.collector.googleCloud.enabled | bool | `false` | Enable Google Cloud integration |
| otel.collector.googleCloud.projectId | string | `"self-host-kubernetes"` | GCP project ID |
| otel.collector.googleCloud.serviceAccount.annotations | object | `{"iam.gke.io/gcp-service-account":"otel-collector@self-host-kubernetes.iam.gserviceaccount.com"}` | Service account annotations (for Workload Identity) |
| otel.collector.googleCloud.serviceAccount.create | bool | `false` | Create service account |
| otel.collector.googleCloud.serviceAccount.name | string | `"otel-collector"` | Service account name |
| otel.collector.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| otel.collector.image.repository | string | `"otel/opentelemetry-collector-contrib"` | Collector image repository |
| otel.collector.image.tag | string | `"0.91.0"` | Collector image tag |
| otel.collector.replicaCount | int | `1` | Number of collector replicas |
| otel.collector.resources.limits.cpu | string | `"1000m"` | CPU limit for collector |
| otel.collector.resources.limits.memory | string | `"1Gi"` | Memory limit for collector |
| otel.collector.resources.requests.cpu | string | `"500m"` | CPU request for collector |
| otel.collector.resources.requests.memory | string | `"512Mi"` | Memory request for collector |
| otel.collector.service.ports.jaeger.port | int | `14250` | Jaeger port |
| otel.collector.service.ports.jaeger.protocol | string | `"TCP"` | Jaeger protocol |
| otel.collector.service.ports.jaeger.targetPort | int | `14250` | Jaeger target port |
| otel.collector.service.ports.otlp-http.port | int | `4318` | OTLP HTTP port |
| otel.collector.service.ports.otlp-http.protocol | string | `"TCP"` | OTLP HTTP protocol |
| otel.collector.service.ports.otlp-http.targetPort | int | `4318` | OTLP HTTP target port |
| otel.collector.service.ports.otlp.port | int | `4317` | OTLP gRPC port |
| otel.collector.service.ports.otlp.protocol | string | `"TCP"` | OTLP gRPC protocol |
| otel.collector.service.ports.otlp.targetPort | int | `4317` | OTLP gRPC target port |
| otel.collector.service.ports.prometheus.port | int | `8889` | Prometheus metrics port |
| otel.collector.service.ports.prometheus.protocol | string | `"TCP"` | Prometheus protocol |
| otel.collector.service.ports.prometheus.targetPort | int | `8889` | Prometheus metrics target port |
| otel.collector.service.type | string | `"ClusterIP"` | Service type |
| otel.enabled | bool | `true` | Enable OpenTelemetry |
| otel.environment | string | `"development"` | Environment name for telemetry |
| otel.exporter.otlp.endpoint | string | `"composio-otel-collector:4317"` | gRPC endpoint for OTLP (no protocol prefix needed) |
| otel.exporter.otlp.headers | string | `""` | Optional headers for authentication |
| otel.exporter.otlp.insecure | bool | `true` | Use insecure connection |
| otel.exporter.otlp.metricsEndpoint | string | `"composio-otel-collector:4317"` | Metrics endpoint for gRPC (optional, defaults to endpoint) |
| otel.exporter.otlp.tracesEndpoint | string | `"http://composio-otel-collector:4318/v1/traces"` | Trace endpoint (optional, defaults to endpoint) |
| otel.frontend.metricsEndpoint | string | `"http://composio-otel-collector:4318/v1/metrics"` | HTTP endpoint for metrics |
| otel.frontend.serviceName | string | `"frontend"` | Frontend service name |
| otel.frontend.serviceVersion | string | `"1.0.0"` | Frontend service version |
| otel.logs.enabled | bool | `false` | Enable log collection via OTEL |
| otel.mercury.metricsEndpoint | string | `"http://composio-otel-collector:4318/v1/metrics"` | HTTP endpoint for metrics |
| otel.mercury.serviceName | string | `"mercury-openapi"` | Mercury service name |
| otel.mercury.serviceVersion | string | `"1.0.0"` | Mercury service version |
| otel.metrics.enabled | bool | `true` | Enable metrics collection |
| otel.metrics.exportInterval | int | `60000` | Metrics export interval in milliseconds |
| otel.thermos.metricsEndpoint | string | `"http://composio-otel-collector:4318/v1/metrics"` | HTTP endpoint for metrics |
| otel.thermos.serviceName | string | `"thermos"` | Thermos service name |
| otel.thermos.serviceVersion | string | `"1.0.0"` | Thermos service version |
| otel.traces.enabled | bool | `true` | Enable trace collection |
| otel.traces.sampler | string | `"always_on"` | Sampling strategy (always_on, always_off, traceidratio) |
| otel.traces.samplerArg | float | `1` | Sampling ratio (0.0 to 1.0) |
| prometheus.enabled | bool | `false` | Enable Prometheus |
| prometheus.imagePullSecrets | list | `[]` | Image pull secrets |
| prometheus.nodeExporter.enabled | bool | `false` | Enable node exporter |
| rbac.create | bool | `false` | Create RBAC resources |
| rbac.namespaced | bool | `true` | Use namespaced RBAC |
| rbac.pspEnabled | bool | `false` | Enable Pod Security Policies |
| redis.architecture | string | `"standalone"` | Redis architecture (standalone or replication) |
| redis.auth.enabled | bool | `true` | Enable Redis authentication |
| redis.auth.password | string | `"redis123"` | Redis password |
| redis.enabled | bool | `false` | Enable internal Redis. Set to false when using externalRedis |
| redis.master.persistence.enabled | bool | `true` | Enable persistent storage |
| redis.master.persistence.size | string | `"8Gi"` | Size of persistent volume |
| redis.master.resources.limits.cpu | string | `"2"` | CPU limit for Redis master |
| redis.master.resources.limits.memory | string | `"4Gi"` | Memory limit for Redis master |
| redis.master.resources.requests.cpu | string | `"2"` | CPU request for Redis master |
| redis.master.resources.requests.memory | string | `"4Gi"` | Memory request for Redis master |
| redis.master.sysctl.enabled | bool | `false` | Disable sysctl for GKE Autopilot |
| redis.master.sysctlImage.enabled | bool | `false` | Disable sysctl image for GKE Autopilot |
| serviceAccount.annotations | object | `{}` | Service account annotations |
| serviceAccount.create | bool | `true` | Create service account |
| serviceAccount.name | string | `""` | Service account name (generated if not specified) |
| temporal.admintools.enabled | bool | `true` | Enable admin tools |
| temporal.admintools.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| temporal.admintools.image.repository | string | `"temporalio/admin-tools"` | Admin tools image repository |
| temporal.admintools.image.tag | string | `"1.28.0-tctl-1.18.2-cli-1.3.0"` | Admin tools image tag |
| temporal.admintools.livenessProbe.enabled | bool | `false` | Enable liveness probe |
| temporal.admintools.readinessProbe.enabled | bool | `false` | Enable readiness probe |
| temporal.cassandra.enabled | bool | `false` | Enable Cassandra |
| temporal.cassandra.image.pullPolicy | string | `"IfNotPresent"` |  |
| temporal.cassandra.image.repo | string | `"cassandra"` |  |
| temporal.cassandra.image.tag | string | `"3.11.3"` |  |
| temporal.elasticsearch.enabled | bool | `false` | Enable Elasticsearch |
| temporal.elasticsearch.imageTag | string | `"7.17.3"` |  |
| temporal.fullnameOverride | string | `"temporal-stack"` | Override the full name of Temporal resources |
| temporal.grafana.enabled | bool | `false` | Enable Grafana |
| temporal.mysql.enabled | bool | `false` | Enable MySQL |
| temporal.prometheus.enabled | bool | `false` | Enable Prometheus |
| temporal.prometheus.nodeExporter.enabled | bool | `false` | Enable node exporter |
| temporal.schema.createDatabase.enabled | bool | `true` | Enable database creation |
| temporal.schema.setup.backoffLimit | int | `100` | Maximum retries for schema setup |
| temporal.schema.setup.enabled | bool | `true` | Enable schema setup |
| temporal.schema.update.backoffLimit | int | `100` | Maximum retries for schema updates |
| temporal.schema.update.enabled | bool | `true` | Enable schema updates |
| temporal.server.config.logLevel | string | `"info"` | Log level (debug, info, warn, error) |
| temporal.server.config.namespaces.create | bool | `true` | Enable namespace creation |
| temporal.server.config.namespaces.namespace | list | `[{"name":"default","retention":"7d"},{"name":"batched-polling","retention":"10d"},{"name":"webhook","retention":"10d"}]` | List of namespaces to create |
| temporal.server.config.numHistoryShards | int | `512` | Number of history shards (affects scalability) |
| temporal.server.config.persistence.default.driver | string | `"sql"` | Database driver |
| temporal.server.config.persistence.default.sql.database | string | `"temporal"` | Database name |
| temporal.server.config.persistence.default.sql.driver | string | `"postgres12"` | SQL driver name |
| temporal.server.config.persistence.default.sql.existingSecret | string | `"temporal-password-secret"` | Secret name containing database password |
| temporal.server.config.persistence.default.sql.host | string | `"postgres-new.db"` | Database host |
| temporal.server.config.persistence.default.sql.maxConnLifetime | string | `"1h"` | Maximum connection lifetime |
| temporal.server.config.persistence.default.sql.maxConns | int | `20` | Maximum number of database connections |
| temporal.server.config.persistence.default.sql.maxIdleConns | int | `20` | Maximum number of idle connections |
| temporal.server.config.persistence.default.sql.port | int | `5432` | Database port |
| temporal.server.config.persistence.default.sql.user | string | `"composio"` | Database user |
| temporal.server.config.persistence.defaultStore | string | `"default"` | Default persistence store |
| temporal.server.config.persistence.visibility.driver | string | `"sql"` | Database driver |
| temporal.server.config.persistence.visibility.sql.database | string | `"temporal_visibility"` | Database name |
| temporal.server.config.persistence.visibility.sql.driver | string | `"postgres12"` | SQL driver name |
| temporal.server.config.persistence.visibility.sql.existingSecret | string | `"temporal-password-secret"` | Secret name containing database password |
| temporal.server.config.persistence.visibility.sql.host | string | `"postgres-new.db"` | Database host |
| temporal.server.config.persistence.visibility.sql.maxConnLifetime | string | `"1h"` | Maximum connection lifetime |
| temporal.server.config.persistence.visibility.sql.maxConns | int | `20` | Maximum number of database connections |
| temporal.server.config.persistence.visibility.sql.maxIdleConns | int | `20` | Maximum number of idle connections |
| temporal.server.config.persistence.visibility.sql.port | int | `5432` | Database port |
| temporal.server.config.persistence.visibility.sql.user | string | `"composio"` | Database user |
| temporal.server.enabled | bool | `true` | Enable Temporal server |
| temporal.server.frontend.livenessProbe.enabled | bool | `false` | Enable liveness probe |
| temporal.server.frontend.readinessProbe.enabled | bool | `false` | Enable readiness probe |
| temporal.server.frontend.service.httpPort | int | `7243` | HTTP port |
| temporal.server.frontend.service.membershipPort | int | `6933` | Membership port |
| temporal.server.frontend.service.port | int | `7233` | gRPC port |
| temporal.server.frontend.service.type | string | `"ClusterIP"` | Service type |
| temporal.server.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| temporal.server.image.repository | string | `"temporalio/server"` | Temporal server image repository |
| temporal.server.image.tag | string | `"1.28.0"` | Temporal server image tag |
| temporal.server.livenessProbe.enabled | bool | `false` | Enable liveness probe |
| temporal.server.readinessProbe.enabled | bool | `false` | Enable readiness probe |
| temporal.server.replicaCount | int | `2` | Number of Temporal server replicas |
| temporal.web.enabled | bool | `true` | Enable Temporal Web UI |
| temporal.web.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| temporal.web.image.repository | string | `"temporalio/ui"` | Web UI image repository |
| temporal.web.image.tag | string | `"2.38.3"` | Web UI image tag |
| temporal.web.livenessProbe.enabled | bool | `false` | Enable liveness probe |
| temporal.web.readinessProbe.enabled | bool | `false` | Enable readiness probe |
| temporal.web.replicaCount | int | `1` | Number of Web UI replicas |
| temporal.web.service.port | int | `8080` | Web UI HTTP port |
| temporal.web.service.type | string | `"ClusterIP"` | Service type |
| testFramework.enabled | bool | `false` | Enable test framework |
| thermos.autoscaling.enabled | bool | `false` | Enable HPA |
| thermos.autoscaling.maxReplicas | int | `10` | Maximum number of replicas |
| thermos.autoscaling.minReplicas | int | `2` | Minimum number of replicas |
| thermos.autoscaling.scaleDownPercent | int | `10` | Scale down percentage |
| thermos.autoscaling.scaleDownPeriodSeconds | int | `60` | Scale down period (seconds) |
| thermos.autoscaling.scaleDownStabilizationWindowSeconds | int | `300` | Stabilization window for scale down (seconds) |
| thermos.autoscaling.scaleUpPercent | int | `100` | Scale up percentage |
| thermos.autoscaling.scaleUpPeriodSeconds | int | `15` | Scale up period (seconds) |
| thermos.autoscaling.scaleUpPods | int | `4` | Number of pods to scale up at once |
| thermos.autoscaling.scaleUpStabilizationWindowSeconds | int | `60` | Stabilization window for scale up (seconds) |
| thermos.autoscaling.targetCPUUtilizationPercentage | int | `70` | Target CPU utilization percentage |
| thermos.autoscaling.targetMemoryUtilizationPercentage | int | `80` | Target memory utilization percentage |
| thermos.database.key | string | `"uri"` | Key name in the secret |
| thermos.database.secretRef | string | `"thermosdb"` | Secret reference containing database URI |
| thermos.dbInit.enabled | bool | `true` | Enable database initialization |
| thermos.dbInit.image.pullPolicy | string | `"Always"` | Image pull policy |
| thermos.dbInit.image.repository | string | `"composio-self-host/thermos-db-init"` | Database init image repository |
| thermos.dbInit.image.tag | string | `"release-20251209_00"` | Database init image tag |
| thermos.image.pullPolicy | string | `"Always"` | Image pull policy |
| thermos.image.repository | string | `"composio-self-host/thermos"` | Thermos image repository |
| thermos.image.tag | string | `"release-20251209_00"` | Thermos image tag |
| thermos.replicaCount | int | `2` | Number of Thermos pod replicas |
| thermos.resources.limits.cpu | string | `"2"` | CPU limit for Thermos |
| thermos.resources.limits.memory | string | `"5Gi"` | Memory limit for Thermos |
| thermos.resources.requests.cpu | string | `"2"` | CPU request for Thermos |
| thermos.resources.requests.memory | string | `"4Gi"` | Memory request for Thermos |
| thermos.service.port | int | `8180` | Service port |
| thermos.service.type | string | `"ClusterIP"` | Service type |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
