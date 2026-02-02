## Configuring overwrite-values.yaml before installation

### Step 0: Copy and review `overwrite-values.yaml`

1. Copy the base [overwrite-values.yaml](https://github.com/ComposioHQ/helm-charts/blob/release-stable/overwrite-values.yaml) file into your working directory

2. Open the copied `overwrite-values.yaml` file and:

   * Review all configuration values
   * Update database host, credentials, and any environment-specific settings
   * Configure any required overrides for your setup

3. While reviewing the file, determine **whether your database has TLS enabled**.

   * You will use this information in **Step 1**.

> ⚠️ Do not skip this step. All further configuration depends on values defined here.

---

### Step 1: Check if database TLS is enabled

* **If TLS is disabled on your database:**
  Skip the TLS section below and proceed directly to **Next Steps**.
* **If TLS is enabled on your database:**
  Continue to **Step 2** to configure TLS for Temporal.

---

## TLS Configuration for Temporal

*(Only required if database TLS is enabled and Temporal is in use. Temporal is only needed if auth refresh and/or triggers are enabled.)*

### Important notes

* If your database **has TLS enabled**, you **must** complete Steps 2–4 below.
* Skipping these steps will cause the **Helm installation to fail**.

---

### Step 2: Download the CA certificate

Download the CA bundle so Temporal can establish a trusted TLS connection.

**Example (AWS RDS):**

```bash
curl -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

---

### Step 3: Create a Kubernetes secret with the CA certificate

Create a Kubernetes secret containing the downloaded CA certificate:

```bash
kubectl create secret generic temporal-db-tls-secret \
  --from-file=rds-ca.crt=./global-bundle.pem \
  -n <NAMESPACE>
```

---

### Step 4: Update `overwrite-values.yaml` with TLS settings

Add the following configuration to your `overwrite-values.yaml` file
(replace `"<DATABASE HOST>"` with your actual database host):

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

## Example CloudSQL - GCP 

Create a new file gcp-cert.crt. Download `client-key.pem` `client-cert.pem` and `server-ca.pem` from CloudSQL

server-ca.pem


Create a Kubernetes secret containing the downloaded CA certificate:

```bash
kubectl create secret generic temporal-db-tls-secret \
  --from-file=gcp-cert.crt=./gcp-cert.crt \
  -n <NAMESPACE>
```

Update `overwrite-values.yaml` with TLS settings

> NOTE: If you are using DATABASE_HOST IP please ensure `enableHostVerification` is set to false Or we recommend using CloudSQL proxy as a domain for DATABASE_HOST and in that case you can set `disableHostVerification` to true and remove enableHostVerification 

```yaml
temporal:
  server:
    config:
      persistence:
        default:
          driver: "sql"
          sql:
            host: "192.168.1.1"
            port: 5432
            database: "temporal"
            user: "postgres"
            existingSecret: "composio-composio-secrets"
            tls:
              enabled: true
              # disableHostVerification: true
              enableHostVerification: false
              caFile: /etc/certs/gcp-cert.crt
        visibility:
          sql:
            host: "192.168.1.1"
            port: 5432
            database: "temporal_visibility"
            user: "postgres"
            existingSecret: "composio-composio-secrets"
            tls:
              enabled: true
              enableHostVerification: false
              # disableHostVerification: true
              caFile: /etc/certs/gcp-cert.crt
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
