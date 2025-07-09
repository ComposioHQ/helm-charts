[![Helm Chart](https://img.shields.io/badge/Helm-Chart-0f1689?logo=helm)](https://helm.sh/)
# Composio helm-charts

https://composio.dev 

`helm-charts` to deploy composio on any kubernetes cluster. Contact our team for using these helm charts, and relevant access for docker images.

# Architecture diagram


# Installation




```helm install composio-stg ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  --set externalSecrets.postgres.url="postgresql://<postgres>:<password>@<host_ip>:5432/postgres?sslmode=require"
```

