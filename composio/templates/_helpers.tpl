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
{{- printf "%s" .Values.secret.name -}}
{{- end -}}


{{- define "composio-admin-token" -}}
{{- $coreName := include "composio.coreSecretName" . -}}
{{- $core := lookup "v1" "Secret" .Release.Namespace $coreName -}}
{{- if and $core (hasKey $core.data "COMPOSIO_ADMIN_TOKEN") -}}
  {{- index $core.data "COMPOSIO_ADMIN_TOKEN" | b64dec -}}
{{- else -}}
  {{- $legacy := lookup "v1" "Secret" .Release.Namespace (printf "%s-composio-admin-token" .Release.Name) -}}
  {{- if and $legacy (hasKey $legacy.data "COMPOSIO_ADMIN_TOKEN") -}}
    {{- index $legacy.data "COMPOSIO_ADMIN_TOKEN" | b64dec -}}
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

{{/*
Check if Temporal is enabled via features.temporal flag
This flag both deploys the temporal subchart (via Chart.yaml condition) and configures thermos to use it
*/}}
{{- define "composio.temporalEnabled" -}}
{{- if and .Values.features .Values.features.temporal -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{- define "composio.uriComponent" -}}
{{- . | toString | replace "%" "%25" | replace "\n" "%0A" | replace "\r" "%0D" | replace "\t" "%09" | replace " " "%20" | replace "!" "%21" | replace "\"" "%22" | replace "#" "%23" | replace "$" "%24" | replace "&" "%26" | replace "'" "%27" | replace "(" "%28" | replace ")" "%29" | replace "*" "%2A" | replace "+" "%2B" | replace "," "%2C" | replace "/" "%2F" | replace ":" "%3A" | replace ";" "%3B" | replace "<" "%3C" | replace "=" "%3D" | replace ">" "%3E" | replace "?" "%3F" | replace "@" "%40" | replace "[" "%5B" | replace "\\" "%5C" | replace "]" "%5D" | replace "^" "%5E" | replace "`" "%60" | replace "{" "%7B" | replace "|" "%7C" | replace "}" "%7D" -}}
{{- end -}}

{{- define "composio.shellQuote" -}}
{{- printf "'%s'" (replace "'" "'\"'\"'" (. | toString)) -}}
{{- end -}}

{{- define "composio.toolkitRegistryDbUrl" -}}
{{- $user := include "composio.uriComponent" .Values.toolkitRegistry.auth.username -}}
{{- $database := include "composio.uriComponent" .Values.toolkitRegistry.database.name -}}
{{- printf "postgresql://%s@%s-toolkit-registry:%v/%s?sslmode=disable" $user .Release.Name (.Values.toolkitRegistry.service.port | int) $database -}}
{{- end -}}

{{/*
Render OTEL_RESOURCE_ATTRIBUTES with Kubernetes pod identity.
Expected keys:
- root: chart root context
- serviceName: service.name value
- serviceVersion: service.version value
*/}}
{{- define "composio.otelResourceAttributes" -}}
{{- $root := .root -}}
{{- $clusterName := $root.Values.otel.clusterName | default "" -}}
service.name={{ .serviceName }},service.namespace=$(POD_NAMESPACE),service.instance.id=$(POD_NAME),service.version={{ .serviceVersion }},deployment.environment={{ $root.Values.otel.environment | default $root.Values.global.environment | default "development" }},k8s.namespace.name=$(POD_NAMESPACE),k8s.pod.name=$(POD_NAME),k8s.node.name=$(NODE_NAME){{- if $clusterName }},k8s.cluster.name={{ $clusterName }}{{- end -}}
{{- end -}}

{{/*
Render Kubernetes downward API env vars used by composio.otelResourceAttributes.
*/}}
{{- define "composio.otelKubernetesEnv" -}}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
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
Render a PodDisruptionBudget from a common shape.
Expected keys:
- root: chart root context
- name: resource name
- labels: metadata labels map
- selectorLabels: selector labels map
- pdb: pod disruption budget values
*/}}
{{- define "composio.podDisruptionBudget" -}}
{{- $root := .root -}}
{{- $pdb := .pdb | default (dict) -}}
{{- if $pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- toYaml .labels | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- toYaml .selectorLabels | nindent 6 }}
  {{- if hasKey $pdb "minAvailable" }}
  minAvailable: {{ get $pdb "minAvailable" }}
  {{- else if hasKey $pdb "maxUnavailable" }}
  maxUnavailable: {{ get $pdb "maxUnavailable" }}
  {{- else }}
  maxUnavailable: 1
  {{- end }}
{{- end }}
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
{{- printf "%s" .Release.Namespace }}
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
{{- if .Values.temporal.fullnameOverride -}}
{{- .Values.temporal.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "temporal" .Values.temporal.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Return the Temporal frontend address used by Composio services.
*/}}
{{- define "composio.temporal.frontendAddress" -}}
{{- printf "%s-frontend:%v" (include "composio.temporal.fullname" .) (.Values.temporal.server.frontend.service.port | default 7233) -}}
{{- end }}

{{/*
Wait until Temporal frontend and configured namespaces are available.
*/}}
{{- define "composio.temporalNamespaceWaitInitContainer" -}}
- name: wait-for-temporal-namespaces
  image: "{{ .Values.temporal.admintools.image.repository }}:{{ .Values.temporal.admintools.image.tag }}"
  imagePullPolicy: {{ .Values.temporal.admintools.image.pullPolicy }}
  command:
    - /bin/sh
    - -c
    - |
      until temporal operator namespace list >/dev/null 2>&1; do
        echo "waiting for temporal frontend"
        sleep 5
      done
      {{- range $namespace := .Values.temporal.server.config.namespaces.namespace }}
      until temporal operator namespace describe -n {{ $namespace.name | quote }} >/dev/null 2>&1; do
        echo "waiting for temporal namespace {{ $namespace.name }}"
        sleep 5
      done
      {{- end }}
  env:
    - name: TEMPORAL_ADDRESS
      value: {{ include "composio.temporal.frontendAddress" . | quote }}
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

{{/*
Flexible image reference supporting both imageName and repository:tag patterns
Supports both fork pattern (pre-built imageName) and upstream pattern (composable registry/repository:tag)
Usage: {{ include "composio.imageReference" (dict "image" .Values.apollo.image "context" .) }}
Example 1 (imageName): .image.imageName = "us-central1-docker.pkg.dev/project/apollo:v1.0.0"
Example 2 (composable): .image.repository = "composio-self-host/apollo", .image.tag = "r20260302_00"
*/}}
{{- define "composio.imageReference" -}}
{{- if .image.imageName -}}
  {{- .image.imageName -}}
{{- else -}}
  {{- printf "%s/%s:%s" (include "chart.registry" .context) .image.repository .image.tag -}}
{{- end -}}
{{- end -}}

{{/*
Image pull secrets
*/}}
{{- define "replicated.imagePullSecrets" -}}
  {{- $pullSecrets := list }}

  {{- with ((.Values.global).imagePullSecrets) -}}
    {{- range . -}}
      {{- if kindIs "map" . -}}
        {{- $pullSecrets = append $pullSecrets .name -}}
      {{- else -}}
        {{- $pullSecrets = append $pullSecrets . -}}
      {{- end }}
    {{- end -}}
  {{- end -}}

  {{/* use image pull secrets provided as values */}}
  {{- with .Values.images -}}
    {{- range .pullSecrets -}}
      {{- if kindIs "map" . -}}
        {{- $pullSecrets = append $pullSecrets .name -}}
      {{- else -}}
        {{- $pullSecrets = append $pullSecrets . -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* use secret created with injected docker config */}}
  {{- if hasKey ((.Values.global).replicated) "dockerconfigjson" }}
    {{- $pullSecrets = append $pullSecrets "replicated-pull-secret" -}}
  {{- end -}}


  {{- if (not (empty $pullSecrets)) -}}
imagePullSecrets:
    {{- range $pullSecrets | uniq }}
  - name: {{ . }}
    {{- end }}
  {{- end }}
{{- end -}}


{{/*
Parse SMTP connection string from secret
Expects format: smtp://{username}:{password}@{host}:{port}
Returns a map with keys: username, password, host, port
Usage:
  {{- $smtp := include "apollo.parseSmtpUrl" (dict "secretRef" .Values.apollo.smtp.secretRef "key" .Values.apollo.smtp.key "namespace" .Release.Namespace) | fromJson }}
  {{- $smtp.host }}
  {{- $smtp.port }}
*/}}
{{- define "apollo.parseSmtpUrl" -}}
{{- $secretRef := .secretRef -}}
{{- $key := .key -}}
{{- $namespace := .namespace -}}
{{- $secret := lookup "v1" "Secret" $namespace $secretRef -}}
{{- if $secret -}}
  {{- $smtpUrl := index $secret.data $key | b64dec -}}
  {{- /* Remove smtp:// prefix */ -}}
  {{- $withoutScheme := regexReplaceAll "^smtp://" $smtpUrl "" -}}
  {{- /* Split on @ to separate credentials from host:port */ -}}
  {{- $parts := regexSplit "@" $withoutScheme -1 -}}
  {{- if eq (len $parts) 2 -}}
    {{- $credentials := index $parts 0 -}}
    {{- $hostPort := index $parts 1 -}}
    {{- /* Split credentials on : */ -}}
    {{- $credParts := regexSplit ":" $credentials 2 -}}
    {{- /* Split host:port on : */ -}}
    {{- $hostPortParts := regexSplit ":" $hostPort 2 -}}
    {{- if and (eq (len $credParts) 2) (eq (len $hostPortParts) 2) -}}
      {{- $result := dict "username" (index $credParts 0) "password" (index $credParts 1) "host" (index $hostPortParts 0) "port" (index $hostPortParts 1) -}}
      {{- $result | toJson -}}
    {{- else -}}
      {{- dict "error" "Invalid SMTP URL format" | toJson -}}
    {{- end -}}
  {{- else -}}
    {{- dict "error" "Invalid SMTP URL format - missing @" | toJson -}}
  {{- end -}}
{{- else -}}
  {{- dict "error" "Secret not found" | toJson -}}
{{- end -}}
{{- end -}}

{{/*
Get SMTP host from connection string
*/}}
{{- define "apollo.smtpHost" -}}
{{- $smtp := include "apollo.parseSmtpUrl" . | fromJson -}}
{{- $smtp.host -}}
{{- end -}}

{{/*
Get SMTP port from connection string
*/}}
{{- define "apollo.smtpPort" -}}
{{- $smtp := include "apollo.parseSmtpUrl" . | fromJson -}}
{{- $smtp.port -}}
{{- end -}}

{{/*
Get SMTP username from connection string
*/}}
{{- define "apollo.smtpUsername" -}}
{{- $smtp := include "apollo.parseSmtpUrl" . | fromJson -}}
{{- $smtp.username -}}
{{- end -}}

{{/*
Get SMTP password from connection string
*/}}
{{- define "apollo.smtpPassword" -}}
{{- $smtp := include "apollo.parseSmtpUrl" . | fromJson -}}
{{- $smtp.password -}}
{{- end -}}
