# Installation Prerequisites

Please ensure you have the following before installation:

1. Sufficient compute resources for the Composio Helm chart deployment. Check compute requirement docs [docs](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/prerequisites/compute.md).

2. A self-hosted PostgreSQL database instance (Recommended version 17+)

3. Kubernetes Namespace to install Composio Helm chart

# Kubernetes Secrets Configuration

## Create Composio Application Secrets

Replace the placeholder values:

Based on your database configured change `sslmode=require` for **POSTGRES_URL** **THERMOS_DATABASE_URL**

```bash
kubectl create secret generic composio-composio-secrets \
  --from-literal=COMPOSIO_ADMIN_TOKEN=<CREATE_RANDOM_TOKEN-A> \
  --from-literal=ENCRYPTION_KEY=<ENCRYPTION_KEY_FOR_DATABASE> \
  --from-literal=TEMPORAL_TRIGGER_ENCRYPTION_KEY=<ENCRYPTION_KEY_FOR_DATABASE_TEMPORAL> \
  --from-literal=JWT_SECRET=<CREATE_RANDOM_TOKEN-C> \
  --from-literal=POSTGRES_URL="postgresql://<DATABASE_USER>:<DATABASE_PASSWORD>@<DATABASE_HOST>:5432/composiodb?sslmode=require" \
  --from-literal=THERMOS_DATABASE_URL="postgresql://<DATABASE_USER>:<DATABASE_PASSWORD>@<DATABASE_HOST>:5432/thermosdb?sslmode=require" \
  --from-literal=password="<DATABASE_PASSWORD>" \
  -n <RELEASE_NAMESPACE>
```

**NOTE**: These secrets are required. The recommended secret name is `composio-composio-secret`. If you want to use another secret name, please reference it in your override values file as `secret.name: <your-custom-secret-name>`.

**CRITICAL**: Please store the following keys securely. If they are lost, **all data will be permanently inaccessible**.

## Sensitive Keys and Secrets

1. **ENCRYPTION_KEY**
   Used by the Composio application for database encryption.
2. **TEMPORAL_TRIGGER_ENCRYPTION_KEY**
   Used by Temporal for database encryption. Only required if auth refresh and/or triggers are enabled.
3. **COMPOSIO_ADMIN_TOKEN**
   API token for the Composio Apollo application.
4. **JWT_SECRET**
   Secret key used for signing and verifying JWT tokens.
5. **POSTGRES_URL**
   Database connection URI for the Composio Apollo database.
6. **THERMOS_DATABASE_URL**
   Database connection URI for the Composio Thermos database.
7. **OPENAI_API_KEY**
   OpenAI API key.
8. **password**
   Database password used by the Composio application (and Temporal, if auth refresh and/or triggers are enabled).

## Deploying with ArgoCD

If you are deploying the Composio chart using ArgoCD, create the OCI Helm repository secret before creating the Application resource. ArgoCD must authenticate to the Replicated OCI registry before it can pull the chart.

1. Create the OCI Helm repository secret

   Apply the following Secret in the argocd namespace:

      ```yaml
      apiVersion: v1
      kind: Secret
      metadata:
      name: composio-helm-repo
      namespace: argocd
      labels:
         argocd.argoproj.io/secret-type: repository
      type: Opaque
      stringData:
      type: helm
      name: composio
      url: registry.composio.io/composio-rodent/unstable
      username: <your email address as provided in Replicated>
      password: password
      enableOCI: "true"
      ```

   Replace the username with the email associated with your Replicated account.

2. Create the ArgoCD Application resource

   After the repository secret is created, apply the following Application manifest:

      ```yaml
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
      name: composio
      namespace: argocd
      spec:
      project: default
      source:
         repoURL: registry.composio.io/composio-rodent/unstable
         chart: composio
         targetRevision: 0.1.57
      destination:
         server: <https://kubernetes.default.svc>
         namespace: composio
      syncPolicy:
         automated:
            prune: true
            selfHeal: true
         syncOptions:
            - CreateNamespace=true
      ```

This configuration enables automated sync, namespace creation, pruning of removed resources, and drift correction.

For CI-based deployments, see [Quick Deployment with GitHub Actions and Jenkins](./quick-deployment-ci.md).
