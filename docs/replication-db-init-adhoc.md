# Running Replication DB Init Jobs Ad-Hoc via kubectl

This guide covers running apollo-db-init and thermos-db-init against a replication database without deploying helm chart changes.

## Prerequisites

- `kubectl` configured with access to your cluster
- The replication database is accessible from the cluster
- You know the namespace where Composio is deployed (examples use `composio`)

## 1. Create the Replication Database Secret

Create a secret with the replication database credentials. Use a different secret name from the primary to avoid conflicts.

```bash
kubectl create secret generic replication-db-secrets \
  -n composio \
  --from-literal=POSTGRES_URL="postgresql://<user>:<password>@<replication-host>:<port>/composiodb" \
  --from-literal=THERMOS_DATABASE_URL="postgresql://<user>:<password>@<replication-host>:<port>/thermosdb" \
  --from-literal=ENCRYPTION_KEY="<your-encryption-key>"
```

Replace the placeholders:
- `<user>` / `<password>` — replication DB credentials
- `<replication-host>` / `<port>` — replication DB host and port
- `<your-encryption-key>` — same encryption key used by the primary (required for apollo)

## 2. Run Apollo DB Init on Replication

```bash
kubectl create job apollo-db-init-replication -n composio --image="008971668139.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/apollo-db-init:r20260318_04" \
  --dry-run=client -o yaml | kubectl patch --type merge --local -o yaml -p '
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 2400
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: apollo-db-init-replication
        image: "008971668139.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/apollo-db-init:r20260318_04"
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: replication-db-secrets
              key: POSTGRES_URL
        - name: ENCRYPTION_KEY
          valueFrom:
            secretKeyRef:
              name: replication-db-secrets
              key: ENCRYPTION_KEY
        - name: ORG_API_KEY_ENCRYPTION_KEY
          valueFrom:
            secretKeyRef:
              name: replication-db-secrets
              key: ENCRYPTION_KEY
        - name: ADMIN_EMAIL
          value: "hello@composio.dev"
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi' -f - | kubectl apply -n composio -f -
```

Or apply the YAML directly:

```bash
cat <<'EOF' | kubectl apply -n composio -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: apollo-db-init-replication
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 2400
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: OnFailure
      imagePullSecrets:
        - name: ecr-secret
      containers:
        - name: apollo-db-init-replication
          image: "008971668139.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/apollo-db-init:r20260318_04"
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: replication-db-secrets
                  key: POSTGRES_URL
            - name: ENCRYPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: replication-db-secrets
                  key: ENCRYPTION_KEY
            - name: ORG_API_KEY_ENCRYPTION_KEY
              valueFrom:
                secretKeyRef:
                  name: replication-db-secrets
                  key: ENCRYPTION_KEY
            - name: ADMIN_EMAIL
              value: "hello@composio.dev"
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
EOF
```

## 3. Run Thermos DB Init on Replication

```bash
cat <<'EOF' | kubectl apply -n composio -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: thermos-db-init-replication
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 2400
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: OnFailure
      imagePullSecrets:
        - name: ecr-secret
      containers:
        - name: thermos-db-init-replication
          image: "008971668139.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/thermos-db-init:r20260318_04"
          env:
            - name: POSTGRES_URL
              valueFrom:
                secretKeyRef:
                  name: replication-db-secrets
                  key: THERMOS_DATABASE_URL
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: replication-db-secrets
                  key: THERMOS_DATABASE_URL
            - name: ADMIN_EMAIL
              value: "hello@composio.dev"
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
EOF
```

## 4. Monitor the Jobs

```bash
# Watch job status
kubectl get jobs -n composio -l 'app in (apollo-db-init-replication, thermos-db-init-replication)' -w

# Check logs
kubectl logs -n composio job/apollo-db-init-replication -f
kubectl logs -n composio job/thermos-db-init-replication -f
```

## 5. Cleanup

Jobs auto-delete after 24 hours (`ttlSecondsAfterFinished: 86400`). To remove manually:

```bash
kubectl delete job apollo-db-init-replication thermos-db-init-replication -n composio
```

To remove the secret (if no longer needed):

```bash
kubectl delete secret replication-db-secrets -n composio
```

## Notes

- These jobs run independently of helm install/upgrade — they do not block application deployment.
- If you need to re-run a job, delete the existing one first (`kubectl delete job <name> -n composio`) and re-apply.
- Update the image tag to match your current release when running against newer versions.
- The `imagePullSecrets` reference (`ecr-secret`) must already exist in the namespace. Adjust if your cluster uses a different pull secret name.
