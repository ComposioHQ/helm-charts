{{/* Secret holding eGateway credentials. Defaults to the core secret. */}}
{{- define "egateway.secretName" -}}
{{- .Values.egateway.secretRef | default (include "composio.coreSecretName" .) -}}
{{- end -}}

{{- define "egateway.adminHost" -}}
{{- .Values.egateway.hosts.admin | default (printf "egateway.%s" .Values.global.domain) -}}
{{- end -}}

{{- define "egateway.proxyHost" -}}
{{- .Values.egateway.hosts.proxy | default (printf "mcp.%s" .Values.global.domain) -}}
{{- end -}}

{{- define "egateway.authHost" -}}
{{- .Values.egateway.hosts.auth | default (printf "auth.%s" .Values.global.domain) -}}
{{- end -}}

{{- define "egateway.adminServiceName" -}}
{{- printf "%s-egateway-admin" (include "composio.fullname" .) -}}
{{- end -}}

{{- define "egateway.proxyServiceName" -}}
{{- printf "%s-egateway-proxy" (include "composio.fullname" .) -}}
{{- end -}}

{{- define "egateway.fusionauthServiceName" -}}
{{- printf "%s-egateway-fusionauth" (include "composio.fullname" .) -}}
{{- end -}}

{{- define "egateway.jwksServiceName" -}}
{{- printf "%s-egateway-jwks" (include "composio.fullname" .) -}}
{{- end -}}

{{/* "true" when the gateway signs Composio project JWTs (composioAuth.mode=jwt). */}}
{{- define "egateway.composioJwtEnabled" -}}
{{- if and .Values.egateway.enabled (eq (.Values.egateway.composioAuth.mode | default "api_key") "jwt") -}}
true
{{- end -}}
{{- end -}}

{{- define "egateway.composioJwtIssuer" -}}
{{- .Values.egateway.composioAuth.jwt.issuer | default (printf "https://%s" (include "egateway.adminHost" .)) -}}
{{- end -}}

{{/*
In-cluster JWKS URL for Apollo's AUTH_JWT_JWKS_URL. Apollo fetches it with a
plain fetch (no private-address filtering), so the Service URL works and the
keys never need a public route.
*/}}
{{- define "egateway.composioJwksUrl" -}}
{{- printf "http://%s:3002/.well-known/composio-jwks.json" (include "egateway.jwksServiceName" .) -}}
{{- end -}}

{{- define "egateway.composioBaseUrl" -}}
{{- .Values.egateway.composioBaseUrl | default (printf "http://%s-apollo:9900" .Release.Name) -}}
{{- end -}}

{{/* imagePullSecrets block, matching the other Composio services. */}}
{{- define "egateway.imagePullSecrets" -}}
{{- if .Values.replicated.enabled }}
{{- include "replicated.imagePullSecrets" . }}
{{- else if .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml .Values.global.imagePullSecrets | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Secret-backed env shared by admin and proxy. */}}
{{- define "egateway.secretEnv" -}}
{{- $secret := include "egateway.secretName" . -}}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: EGATEWAY_POSTGRES_URL
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: EGATEWAY_REDIS_URL
{{- range $key := list "COMPOSIO_API_KEY_ENCRYPTION_SECRET" "FUSIONAUTH_API_KEY" }}
- name: {{ $key }}
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: {{ $key }}
{{- end }}
{{- if include "egateway.composioJwtEnabled" . }}
- name: COMPOSIO_JWT_PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: COMPOSIO_JWT_PRIVATE_KEY
{{- end }}
{{- end -}}

{{/* Pod and container security contexts shared by admin, proxy and migrate. */}}
{{- define "egateway.podSecurityContext" -}}
{{- with .Values.egateway.podSecurityContext -}}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{- define "egateway.containerSecurityContext" -}}
{{- with .Values.egateway.containerSecurityContext -}}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
