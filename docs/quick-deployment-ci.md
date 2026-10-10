# Quick Deployment with GitHub Actions and Jenkins

Use this guide when you want to deploy the Composio chart from a CI pipeline instead of ArgoCD. The deployment flow is the same in both systems:

1. Authenticate to the Replicated OCI Helm registry.
2. Pull or reference the Composio chart.
3. Run `helm upgrade --install` against your target cluster.

Before using either example, complete the prerequisites in [replicated-pre-installation.md](./replicated-pre-installation.md), especially the Kubernetes secret creation step.

## Assumptions

- `kubectl` and `helm` are installed in the CI runner or Jenkins agent.
- The pipeline already has access to the target Kubernetes cluster.
- Your Replicated email and password are stored as CI secrets.
- Your namespace and values file are already defined for the target environment.

## Deploying with GitHub Actions

Store the following values as GitHub Actions secrets:

- `COMPOSIO_REPLICATED_USERNAME`
- `COMPOSIO_REPLICATED_PASSWORD`
- `KUBECONFIG`

Create a workflow similar to the following:

```yaml
name: Deploy Composio

on:
  workflow_dispatch:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      RELEASE_NAME: composio
      RELEASE_NAMESPACE: composio
      CHART_VERSION: <chart version>
      VALUES_FILE: ./override.yaml
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Helm
        uses: azure/setup-helm@v4

      - name: Configure kubeconfig
        run: |
          mkdir -p ~/.kube
          echo "${KUBECONFIG}" > ~/.kube/config
          chmod 600 ~/.kube/config
        env:
          KUBECONFIG: ${{ secrets.KUBECONFIG }}

      - name: Login to Replicated OCI registry
        run: |
          echo "${COMPOSIO_REPLICATED_PASSWORD}" | helm registry login registry.composio.io \
            --username "${COMPOSIO_REPLICATED_USERNAME}" \
            --password-stdin
        env:
          COMPOSIO_REPLICATED_USERNAME: ${{ secrets.COMPOSIO_REPLICATED_USERNAME }}
          COMPOSIO_REPLICATED_PASSWORD: ${{ secrets.COMPOSIO_REPLICATED_PASSWORD }}

      - name: Deploy Composio chart
        run: |
          helm upgrade --install "${RELEASE_NAME}" oci://registry.composio.io/composio-rodent/unstable/composio \
            --namespace "${RELEASE_NAMESPACE}" \
            --create-namespace \
            --version "${CHART_VERSION}" \
            -f "${VALUES_FILE}"
```

Replace `CHART_VERSION`, `VALUES_FILE`, and namespace values for your environment. If you manage cluster access through a cloud-specific action instead of a raw `KUBECONFIG` secret, keep the Helm login and deployment steps the same.

## Deploying with Jenkins

Store the Replicated credentials in the Jenkins credentials store and expose them to the pipeline as environment variables. The example below uses:

- `composio-replicated-username`
- `composio-replicated-password`
- `kubeconfig`

Create a Jenkins pipeline similar to the following:

```groovy
pipeline {
  agent any

  environment {
    RELEASE_NAME = 'composio'
    RELEASE_NAMESPACE = 'composio'
    CHART_VERSION = '<chart version>'
    VALUES_FILE = './override.yaml'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Configure kubeconfig') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
          sh '''
            mkdir -p ~/.kube
            cp "$KUBECONFIG_FILE" ~/.kube/config
            chmod 600 ~/.kube/config
          '''
        }
      }
    }

    stage('Deploy Composio') {
      steps {
        withCredentials([
          string(credentialsId: 'composio-replicated-username', variable: 'COMPOSIO_REPLICATED_USERNAME'),
          string(credentialsId: 'composio-replicated-password', variable: 'COMPOSIO_REPLICATED_PASSWORD')
        ]) {
          sh '''
            echo "$COMPOSIO_REPLICATED_PASSWORD" | helm registry login registry.composio.io \
              --username "$COMPOSIO_REPLICATED_USERNAME" \
              --password-stdin

            helm upgrade --install "$RELEASE_NAME" oci://registry.composio.io/composio-rodent/unstable/composio \
              --namespace "$RELEASE_NAMESPACE" \
              --create-namespace \
              --version "$CHART_VERSION" \
              -f "$VALUES_FILE"
          '''
        }
      }
    }
  }
}
```

Replace the credential IDs, chart version, values file, and namespace values to match your Jenkins setup.

## Notes

- The Replicated username should be the email address associated with your Replicated account.
- Use a pinned chart version instead of `latest` so deployments are repeatable.
- If your pipeline manages secrets or values dynamically, keep the Helm login step unchanged and inject only the release-specific arguments.
