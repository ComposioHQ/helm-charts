## Need to create HMAC keys and store as composio-s3-credentials
```
kubectl create secret generic composio-s3-credentials \
  -n composio \
  --from-literal=S3_ACCESS_KEY_ID="" \
  --from-literal=S3_SECRET_ACCESS_KEY=""
```
## Create tls secret which has certificate created from cloudflare for both the ingress

## Add ema-image-pull-secret to the following namespaces
```
knative-serving
kourier-system
composio
```

## Export the Open API Key
```
export OPENAI_API_KEY="sk-1234567890abcdef..."
```

## Ensure both databases are created in the SQL instance and export their secrets
```
export POSTGRES_URL="postgresql://postgres:changeme@host-ip:5432/composio?sslmode=require"
export THERMOS_POSTGRES_URL="postgresql://postgres:changeme@10.69.0.66:5432/thermos?sslmode=require"
```
## Export the Redis URL, make sure auth is disabled
```
export REDIS_URL="redis://host:6379/0"
```
## Run the secret generation script
## Run the image-migration script if there is a new tag
## Update the values file with the new tag

## Add the Sendgrid API key in the format below
```
kubectl create secret generic composio-smtp-credentials \
  -n composio \
  --from-literal=SMTP_CONNECTION_STRING="smtp://apikey:<api-key>@smtp.sendgrid.net:587"
```

