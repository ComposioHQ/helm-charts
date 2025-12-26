# Helm Chart Configuration

This document provides a detailed guide on configuring the Composio Helm chart.

## Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `namespace.name` | The namespace to deploy all resources into. | `composio` |

## Component-Specific Configuration

### Frontend

| Parameter | Description | Default |
|-----------|-------------|---------|
| `frontend.replicaCount` | Number of frontend pods. | `1` |
| `frontend.image.repository` | Frontend container image. | `public.ecr.aws/composio/frontend` |
| `frontend.image.tag` | Frontend container image tag. | `latest` |

### Apollo

| Parameter | Description | Default |
|-----------|-------------|---------|
| `apollo.replicaCount` | Number of Apollo pods. | `1` |
| `apollo.image.repository` | Apollo container image. | `public.ecr.aws/composio/apollo` |
| `apollo.image.tag` | Apollo container image tag. | `latest` |

... and so on for other components.
