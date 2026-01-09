{{/*
Expand the name of the chart.
*/}}
{{- define "composio.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hash" -}}
{{- $data := mustToJson .data | toString }}
{{- $salt := "adskj" }}
{{- $base := (printf "%s%s" $data $salt) | quote | sha1sum | trunc 5 }}
{{- $rand := randAlphaNum 3 | lower }}
{{- printf "%s-%s" $base $rand }}
{{- end -}}

{{/* Core secret name shared by chart-managed secrets */}}
{{- define "composio.coreSecretName" -}}
{{- printf "%s-composio-secrets" .Release.Name -}}
{{- end -}}


{{- define "apollo-admin-token" -}}
{{- $coreName := include "composio.coreSecretName" . -}}
{{- $core := lookup "v1" "Secret" .Release.Namespace $coreName -}}
{{- if and $core (hasKey $core.data "APOLLO_ADMIN_TOKEN") -}}
  {{- index $core.data "APOLLO_ADMIN_TOKEN" | b64dec -}}
{{- else -}}
  {{- $legacy := lookup "v1" "Secret" .Release.Namespace (printf "%s-apollo-admin-token" .Release.Name) -}}
  {{- if and $legacy (hasKey $legacy.data "APOLLO_ADMIN_TOKEN") -}}
    {{- index $legacy.data "APOLLO_ADMIN_TOKEN" | b64dec -}}
  {{- else -}}
    {{- randAlphaNum 32 -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "composio-api-key" -}}
{{- $coreName := include "composio.coreSecretName" . -}}
{{- $core := lookup "v1" "Secret" .Release.Namespace $coreName -}}
{{- if and $core (hasKey $core.data "COMPOSIO_API_KEY") -}}
  {{- index $core.data "COMPOSIO_API_KEY" | b64dec -}}
{{- else -}}
  {{- $legacy := lookup "v1" "Secret" .Release.Namespace (printf "%s-composio-api-key" .Release.Name) -}}
  {{- if and $legacy (hasKey $legacy.data "COMPOSIO_API_KEY") -}}
    {{- index $legacy.data "COMPOSIO_API_KEY" | b64dec -}}
  {{- else -}}
    {{- randAlphaNum 32 -}}
  {{- end -}}
{{- end -}}
{{- end -}}


{{- define "encryption-key" -}}
{{- $coreName := include "composio.coreSecretName" . -}}
{{- $core := lookup "v1" "Secret" .Release.Namespace $coreName -}}
{{- if and $core (hasKey $core.data "ENCRYPTION_KEY") -}}
  {{- index $core.data "ENCRYPTION_KEY" | b64dec -}}
{{- else -}}
  {{- $legacy := lookup "v1" "Secret" .Release.Namespace (printf "%s-encryption-key" .Release.Name) -}}
  {{- if and $legacy (hasKey $legacy.data "ENCRYPTION_KEY") -}}
    {{- index $legacy.data "ENCRYPTION_KEY" | b64dec -}}
  {{- else -}}
    {{- randAlphaNum 32 -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "jwt-secret" -}}
{{- $coreName := include "composio.coreSecretName" . -}}
{{- $core := lookup "v1" "Secret" .Release.Namespace $coreName -}}
{{- if and $core (hasKey $core.data "JWT_SECRET") -}}
  {{- index $core.data "JWT_SECRET" | b64dec -}}
{{- else -}}
  {{- $legacy := lookup "v1" "Secret" .Release.Namespace (printf "%s-jwt-secret" .Release.Name) -}}
  {{- if and $legacy (hasKey $legacy.data "JWT_SECRET") -}}
    {{- index $legacy.data "JWT_SECRET" | b64dec -}}
  {{- else -}}
    {{- randAlphaNum 32 -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "temporal-encryption-key" -}}
{{- $coreName := include "composio.coreSecretName" . -}}
{{- $core := lookup "v1" "Secret" .Release.Namespace $coreName -}}
{{- if and $core (hasKey $core.data "TEMPORAL_TRIGGER_ENCRYPTION_KEY") -}}
  {{- index $core.data "TEMPORAL_TRIGGER_ENCRYPTION_KEY" | b64dec -}}
{{- else -}}
  {{- $legacy := lookup "v1" "Secret" .Release.Namespace (printf "%s-temporal-encryption-key" .Release.Name) -}}
  {{- if and $legacy (hasKey $legacy.data "TEMPORAL_TRIGGER_ENCRYPTION_KEY") -}}
    {{- index $legacy.data "TEMPORAL_TRIGGER_ENCRYPTION_KEY" | b64dec -}}
  {{- else -}}
    {{- randAlphaNum 32 -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Get a decoded value from an existing Kubernetes Secret
Usage:
{{ include "mychart.getSecretValue" (dict
  "name" "db-secret"
  "namespace" .Release.Namespace
  "key" "password"
) }}
*/}}
{{- define "getSecretCred" -}}
{{- $secret := lookup "v1" "Secret" .namespace .name -}}
{{- if and $secret (hasKey $secret.data .key) -}}
{{- index $secret.data .key | b64dec -}}
{{- else -}}
this secret was not found
{{- end -}}
{{- end -}}



{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "composio.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "composio.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "composio.labels" -}}
helm.sh/chart: {{ include "composio.chart" . }}
{{ include "composio.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "composio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "composio.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Apollo labels
*/}}
{{- define "composio.apollo.labels" -}}
{{ include "composio.labels" . }}
app.kubernetes.io/component: apollo
{{- end }}

{{/*
Apollo selector labels
*/}}
{{- define "composio.apollo.selectorLabels" -}}
{{ include "composio.selectorLabels" . }}
app.kubernetes.io/component: apollo
{{- end }}



{{/*
Thermos labels
*/}}
{{- define "composio.thermos.labels" -}}
{{ include "composio.labels" . }}
app.kubernetes.io/component: thermos
{{- end }}

{{/*
Thermos selector labels
*/}}
{{- define "composio.thermos.selectorLabels" -}}
{{ include "composio.selectorLabels" . }}
app.kubernetes.io/component: thermos
{{- end }}

{{/*
DB Init labels
*/}}
{{- define "composio.dbInit.labels" -}}
{{ include "composio.labels" . }}
app.kubernetes.io/component: db-init
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "composio.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "composio.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the namespace to use for Composio services
*/}}
{{- define "composio.namespace" -}}
{{- default "composio" .Values.namespace.name }}
{{- end }}

{{/*
Create a default fully qualified postgresql name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "composio.postgresql.fullname" -}}
{{- $name := default "postgresql" .Values.postgresql.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create a default fully qualified redis name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "composio.redis.fullname" -}}
{{- $name := default "redis" .Values.redis.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create a default fully qualified temporal name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "composio.temporal.fullname" -}}
{{- $name := default "temporal" .Values.temporal.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "composio.image" -}}
{{- $registryName := .imageRoot.registry -}}
{{- $repositoryName := .imageRoot.repository -}}
{{- $tag := .imageRoot.tag | toString -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "composio.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- else if .Values.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Compile all warnings into a single message, and call fail.
*/}}
{{- define "composio.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "composio.validateValues.database" .) -}}
{{- $messages := append $messages (include "composio.validateValues.redis" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/*
Validate database configuration
*/}}
{{- define "composio.validateValues.database" -}}
{{- if and (not .Values.postgresql.enabled) (not .Values.apollo.secrets.databaseUrl) -}}
composio: database
    You must provide database URL when PostgreSQL is disabled.
    Please set apollo.secrets.databaseUrl
{{- end -}}
{{- end -}}

{{/*
Validate Redis configuration
*/}}
{{- define "composio.validateValues.redis" -}}
{{- if and .Values.externalRedis.enabled .Values.redis.enabled -}}
composio: redis
    You cannot enable both external Redis and built-in Redis.
    Please set redis.enabled to false when externalRedis.enabled is true
{{- end -}}
{{- end -}} 


{{/*
Replicated configuration
*/}}
{{- define "chart.registry" -}}
{{- if .Values.replicated.enabled -}}
{{- printf "%s/proxy/%s/%s" .Values.replicated.registry .Values.replicated.app  .Values.global.registry.name -}}
{{- else -}}
{{- .Values.global.registry.name -}}
{{- end -}}
{{- end -}}
