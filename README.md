[![Helm Chart](https://img.shields.io/badge/Helm-Chart-0f1689?logo=helm)](https://helm.sh/)
[![Documentation](https://img.shields.io/badge/Docs-Online-blue)](https://composiohq.github.io/helm-charts/index.html)

# Composio Helm Charts

Visit the Composio Enterprise portal to get your Helm chart:  

[Enterprise Installation](https://enterprise.composio.io/composio-rodent)
[Replicated migration guide](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/migrate-to-replicated/README.md)


## Architecture 

![Architecture](./docs/architecture/composio_architecture.png)


# Configuration Guide

1. **OpenTelemetry (OTEL) Configuration** - Configure OpenTelemetry for observability and monitoring. [View Guide](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/post-installation/index.md#opentelemetry-otel-configuration)

2. **Datadog Alerts Setup** - Set up alerts and monitoring using Datadog. [View Guide](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/monitoring/alerts/datadog.md)

3. **Object Store Configuration**
   - **Azure Blob Storage** - Configure Azure Blob Storage for Apollo. [View Guide](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/azure-blob-storage.md)
   - **S3 Storage** - Configure S3-compatible storage (AWS S3, GCP GCS) for Apollo. [View Guide](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/gcs-s3-storage.md#configuring-s3-and-gcs-for-file-storage)

4. **Frontend Configuration**
   - **Composio Frontend** - Configure the Composio frontend. [View Guide](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/frontend-setup.md)
   - **SMTP Setup** - Configure SMTP for email functionality. [View Guide](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/smtp-setup.md)
