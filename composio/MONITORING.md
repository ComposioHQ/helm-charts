# Composio Monitoring Setup

This document describes the monitoring capabilities added to the Composio Helm chart, including Prometheus, Grafana, and OpenTelemetry instrumentation.

## Overview

The monitoring stack includes:

- **OpenTelemetry Collector**: Collects metrics, traces, and logs from all services
- **Prometheus**: Stores and queries time-series metrics
- **Grafana**: Visualizes metrics with pre-configured dashboards
- **Service Instrumentation**: All services are instrumented with OpenTelemetry

## Enabling Monitoring

To enable monitoring, set the following in your `values.yaml` or via command line:

```bash
helm install composio . --set monitoring.enabled=true
```

Or in your `values.yaml`:

```yaml
monitoring:
  enabled: true
```

## Components

### OpenTelemetry Collector

The OpenTelemetry Collector is deployed as a sidecar and collects:
- **Metrics**: Application metrics, system metrics, and custom business metrics
- **Traces**: Distributed tracing across all services
- **Logs**: Structured logging with correlation IDs

**Configuration**:
- **OTLP gRPC Endpoint**: `4317`
- **OTLP HTTP Endpoint**: `4318`
- **Prometheus Metrics Endpoint**: `9464`

### Prometheus

Prometheus is configured to scrape metrics from:
- OpenTelemetry Collector
- All Composio services (Apollo, MCP, Thermos, Mercury, MinIO)
- Kubernetes cluster metrics

**Features**:
- Persistent storage (8Gi by default)
- 15-second scrape intervals
- Service discovery via ServiceMonitors

### Grafana

Grafana comes with pre-configured dashboards for:
- **Composio Services Overview**: Service health, request rates, response times
- **Error Rates**: 5xx error monitoring
- **Resource Usage**: CPU and memory consumption
- **Custom Metrics**: Business-specific metrics

**Access**:
- **URL**: `http://<grafana-service>:3000`
- **Default Credentials**: `admin` / `admin123`

## Service Instrumentation

All services are automatically instrumented with OpenTelemetry when monitoring is enabled:

### Environment Variables Added

Each service gets the following OpenTelemetry environment variables:

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://<release-name>-otel-collector:4318"
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "http/protobuf"
- name: OTEL_SERVICE_NAME
  value: "<service-name>"
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "service.name=<service-name>,service.version=<version>,deployment.environment=<env>"
- name: OTEL_TRACES_SAMPLER
  value: "parentbased_always_on"
- name: OTEL_METRICS_EXPORTER
  value: "otlp"
- name: OTEL_TRACES_EXPORTER
  value: "otlp"
- name: OTEL_LOGS_EXPORTER
  value: "otlp"
```

### Instrumented Services

1. **Apollo** (`apollo`): Main API service
2. **MCP** (`mcp`): Model Context Protocol server
3. **Thermos** (`thermos`): Workflow orchestration service
4. **Mercury** (`mercury`): Lambda execution service
5. **MinIO** (`minio`): S3-compatible object storage

## Metrics Available

### HTTP Metrics
- `http_requests_total`: Total HTTP requests
- `http_request_duration_seconds`: Request duration histogram
- `http_requests_in_flight`: Current requests in flight

### System Metrics
- `container_cpu_usage_seconds_total`: CPU usage
- `container_memory_usage_bytes`: Memory usage
- `up`: Service health status

### Custom Business Metrics
- Service-specific metrics from each application
- Database connection metrics
- Cache hit/miss ratios
- External API call metrics

## Dashboards

### Composio Services Overview

This dashboard includes:
- **Service Health**: Up/down status for all services
- **Request Rate**: Requests per second by service and method
- **Response Time**: 95th percentile response times
- **Error Rate**: 5xx error rates
- **Memory Usage**: Container memory consumption
- **CPU Usage**: Container CPU utilization

## Configuration Options

### Monitoring Configuration

```yaml
monitoring:
  enabled: false
  
  # OpenTelemetry Collector
  otel:
    collector:
      enabled: true
      replicaCount: 1
      image:
        repository: otel/opentelemetry-collector
        tag: "0.96.0"
      resources:
        requests:
          memory: "256Mi"
          cpu: "100m"
        limits:
          memory: "512Mi"
          cpu: "200m"
  
  # Prometheus
  prometheus:
    enabled: true
    server:
      persistentVolume:
        enabled: true
        size: 8Gi
      resources:
        requests:
          memory: "256Mi"
          cpu: "100m"
        limits:
          memory: "512Mi"
          cpu: "200m"
  
  # Grafana
  grafana:
    enabled: true
    adminPassword: "admin123"
    persistence:
      enabled: true
      size: 5Gi
    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"
```

## Troubleshooting

### Check Service Status

```bash
# Check if monitoring components are running
kubectl get pods -l app.kubernetes.io/component=monitoring

# Check OpenTelemetry Collector logs
kubectl logs -l app.kubernetes.io/component=otel-collector

# Check Prometheus targets
kubectl port-forward svc/<release-name>-prometheus-server 9090:9090
# Then visit http://localhost:9090/targets
```

### Verify Metrics Collection

```bash
# Check if metrics are being collected
kubectl port-forward svc/<release-name>-prometheus-server 9090:9090
# Then query: up{job=~".*composio.*"}
```

### Access Grafana

```bash
# Port forward Grafana
kubectl port-forward svc/<release-name>-grafana 3000:80
# Then visit http://localhost:3000
```

## Security Considerations

1. **Network Policies**: Consider implementing network policies to restrict access to monitoring endpoints
2. **Authentication**: Grafana authentication should be configured for production use
3. **TLS**: Enable TLS for all monitoring endpoints in production
4. **RBAC**: Ensure proper RBAC permissions for ServiceMonitor resources

## Scaling

### Horizontal Scaling

- **OpenTelemetry Collector**: Can be scaled horizontally by increasing `replicaCount`
- **Prometheus**: Consider using Prometheus Operator for high availability
- **Grafana**: Can be scaled horizontally for high availability

### Resource Scaling

Adjust resource limits based on your workload:

```yaml
monitoring:
  otel:
    collector:
      resources:
        requests:
          memory: "512Mi"
          cpu: "200m"
        limits:
          memory: "1Gi"
          cpu: "500m"
```

## Integration with External Monitoring

The OpenTelemetry Collector can be configured to export to external systems:

- **Jaeger**: For distributed tracing
- **Elasticsearch**: For log aggregation
- **External Prometheus**: For centralized metrics
- **Cloud providers**: AWS CloudWatch, Google Cloud Monitoring, Azure Monitor

## Best Practices

1. **Enable monitoring in all environments**: Development, staging, and production
2. **Set up alerting**: Configure alerts for critical metrics
3. **Regular maintenance**: Monitor storage usage and retention policies
4. **Documentation**: Keep dashboards and alerts documented
5. **Testing**: Regularly test monitoring setup and alerting
