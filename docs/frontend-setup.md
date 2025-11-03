## Frontend Setup Guide

This guide walks you through enabling and configuring the Composio frontend (Next.js) service in Kubernetes, exposing it via Service or Ingress, and wiring it to your backend (Apollo).

### Prerequisites
- Apollo is deployed and reachable inside the cluster (default Service name: `<release>-apollo`, port `9900`).
- DNS domain and Ingress controller (e.g., NGINX) if exposing via Ingress.
- SMTP configured if you plan to use magic link login (see `docs/smtp-setup.md`).

### Key configuration knobs
The frontend is controlled by `frontend.*` values. Important ones:

- Service and image:
  - `frontend.enabled`: enable the frontend component
  - `frontend.image.repository`, `frontend.image.tag`
  - `frontend.service.type`: `ClusterIP` (default), `NodePort`, or `LoadBalancer`
  - `frontend.service.port`: container and service port (default `3000`)

- Backend URL wiring (env):
  - `frontend.env.OVERRIDE_BACKEND_URL`: server-side URL for Apollo; defaults to in-cluster `http://<release>-apollo:9900`
  - `frontend.env.NEXT_PUBLIC_APP_URL`: public URL of the frontend itself (useful for absolute links)

- Ingress:
  - `frontend.ingress.enabled`: set `true` to expose via Ingress
  - `frontend.ingress.className`: e.g., `nginx`
  - `frontend.ingress.host`: public hostname for the app (e.g., `app.example.com`)
  - `frontend.ingress.annotations`: controller/cloud-specific annotations
  - `frontend.ingress.tls`: TLS settings (secret names, hosts)

### Example values (Ingress on NGINX)
```yaml
frontend:
  enabled: true
  replicaCount: 1

  image:
    repository: composio-self-host/frontend
    tag: "latest"
    pullPolicy: Always

  service:
    type: ClusterIP
    port: 3000

  env:
    # Server-side Apollo URL (in-cluster by default)
    # OVERRIDE_BACKEND_URL: "http://composio-apollo:9900"
    # Public Apollo URL that the browser should use
    NEXT_PUBLIC_BACKEND_URL: "https://api.example.com"
    # Public frontend URL (helps generate absolute links)
    NEXT_PUBLIC_APP_URL: "https://app.example.com"
    # Optional flags
    NEXT_PUBLIC_DISABLE_SOCIAL_LOGIN: "true"
    NEXT_PUBLIC_SELF_HOSTED: "true"

  ingress:
    enabled: true
    className: nginx
    host: app.example.com
    annotations:
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    tls:
      - hosts:
          - app.example.com
        secretName: app-tls
```

If you want a cloud load balancer without Ingress, set `frontend.service.type: LoadBalancer` and skip the `ingress` section.

### Deploy or upgrade
```bash
helm upgrade --install composio ./composio \
  -n composio \
  --create-namespace \
  -f values-override.yaml
```

### Verify
```bash
# Check Deployment and Service
kubectl get deploy,svc -n composio | grep frontend

# If using Ingress
kubectl get ingress -n composio
kubectl describe ingress composio-frontend-ingress -n composio

# Port-forward for local test (ClusterIP)
kubectl port-forward -n composio svc/composio-frontend 3000:3000
# Open http://localhost:3000
```

### Notes and tips
- Magic link login requires SMTP and correct URLs:
  - Set `apollo.overwrite_fe_url` to your public frontend URL (e.g., `https://app.example.com`) so links in emails are correct.
- Health endpoints: the frontend serves `/api/health` for readiness/liveness.
- Autoscaling: enable and tune via `frontend.autoscaling.*` if needed.

### Code references
The chart maps these values to the Deployment and Service:

```74:129:composio/templates/frontend.yaml
          env:
            - name: PORT
              value: {{ .Values.frontend.env.PORT | default "3000" | quote }}
            - name: NODE_ENV
              value: {{ .Values.frontend.env.NODE_ENV | default "production" | quote }}
            - name: OVERRIDE_BACKEND_URL
              value: {{ .Values.frontend.env.OVERRIDE_BACKEND_URL | default (printf "http://%s-apollo:9900" .Release.Name) | quote }}
            - name: NEXT_PUBLIC_APP_URL
              value: {{ .Values.frontend.env.NEXT_PUBLIC_APP_URL | quote }}
```

```22:39:composio/templates/frontend-ingress.yaml
spec:
  {{- if .Values.frontend.ingress.className }}
  ingressClassName: {{ .Values.frontend.ingress.className }}
  {{- end }}
  rules:
    - host: {{ .Values.frontend.ingress.host | default (printf "app.%s" .Values.global.domain) }}
```


