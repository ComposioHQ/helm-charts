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
{{- end -}}
