# Overwrite Documentation 

## Database Configuration Documentation

Review the [overwrite-values.yaml](https://github.com/ComposioHQ/helm-charts/blob/release-stable/overwrite-values.yaml) file for configuration options.

If your database has TLS enabled, follow the documentation below and update your `overwrite-values.yaml` file accordingly.

---

## TLS Configuration for Temporal

### Important Notes

**If TLS is enabled on your database:**
- You must complete the steps below to configure Temporal with TLS
- Skipping these steps will cause the Helm installation to fail

**If TLS is disabled on your database:**
- Skip this section and proceed directly to the Helm chart installation

---

### Configure TLS for Temporal

Follow these steps to enable TLS for Temporal when connecting to a database with TLS enabled.

#### Step 1: Download CA Certificate

Download the CA bundle to establish a trusted connection.

Example for AWS RDS:


```bash
curl -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

#### Step 2: Create Kubernetes Secret

Create a Kubernetes secret containing the downloaded CA certificate:

```bash
kubectl create secret generic temporal-db-tls-secret \
  --from-file=rds-ca.crt=./global-bundle.pem \
  -n composio
```

#### Step 3: Update Temporal Configuration

Add the following configuration to your `overwrite-values.yaml` file:

```yaml
temporal:
  server:
    config:
      persistence:
        default:
          driver: "sql"
          sql:
            driver: "postgres12"
            host: "<DATABASE HOST>"
            port: 5432
            database: "temporal"
            user: "composio"
            existingSecret: "composio-composio-secrets"
            maxConns: 20
            maxIdleConns: 20
            maxConnLifetime: "1h"
            tls:
              enabled: true
              disableHostVerification: true
              caFile: /etc/certs/rds-ca.crt
        visibility:
          driver: "sql"
          sql:
            driver: "postgres12"
            host: "<DATABASE HOST>"
            port: 5432
            database: "temporal_visibility"
            user: "composio"
            existingSecret: "composio-composio-secrets"
            maxConns: 20
            maxIdleConns: 20
            maxConnLifetime: "1h"
            tls:
              enabled: true
              disableHostVerification: true
              caFile: /etc/certs/rds-ca.crt
    admintools:
      additionalVolumes:
        - name: temporal-db-tls
          secret:
            secretName: temporal-db-tls-secret
      additionalVolumeMounts:
        - name: temporal-db-tls
          mountPath: /etc/certs
          readOnly: true
```

---

## Next Steps

After completing the appropriate configuration steps above, proceed with the Helm chart installation.
