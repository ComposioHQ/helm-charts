{{- define "composio.auditOwnerJob" -}}
{{- $phase := .phase }}
{{- $weight := .weight }}
{{- $script := .script }}
{{- $root := .root }}
{{- with .root }}
{{- $setup := .Values.apollo.dbInit.auditOwnerSetup }}
{{- if and $setup.databaseUrlSecret.name (not $setup.migrationRole) }}
{{- fail "apollo.dbInit.auditOwnerSetup.migrationRole is required when using a separate database URL Secret" }}
{{- end }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-apollo-audit-owner-{{ $phase }}
  labels:
    app: apollo-audit-owner-{{ $phase }}
    release: {{ .Release.Name }}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": {{ $weight | quote }}
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  ttlSecondsAfterFinished: 86400
  backoffLimit: {{ .Values.dbInit.job.backoffLimit | default 3 }}
  activeDeadlineSeconds: {{ .Values.dbInit.job.activeDeadlineSeconds | default 300 }}
  template:
    metadata:
      name: {{ .Release.Name }}-apollo-audit-owner-{{ $phase }}
      labels:
        app: apollo-audit-owner-{{ $phase }}
        release: {{ .Release.Name }}
    spec:
      {{- if .Values.apollo.serviceAccount.enabled }}
      serviceAccountName: {{ .Values.apollo.serviceAccount.name }}
      {{- end }}
      {{- if .Values.replicated.enabled }}
      {{- include "replicated.imagePullSecrets" . | nindent 6 }}
      {{- else if .Values.global.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml .Values.global.imagePullSecrets | nindent 8 }}
      {{- end }}
      {{- with .Values.apollo.dbInit.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      restartPolicy: {{ .Values.dbInit.job.restartPolicy | default "OnFailure" }}
      {{- with .Values.apollo.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.apollo.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.apollo.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if not $setup.databaseUrlSecret.name }}
      {{- with .Values.apollo.dbInit.additionalInitContainers }}
      initContainers:
{{ tpl (toYaml .) $root | nindent 8 }}
      {{- end }}
      {{- end }}
      containers:
        - name: audit-owner-{{ $phase }}
          image: {{ $setup.image | quote }}
          imagePullPolicy: IfNotPresent
          {{- with .Values.apollo.dbInit.containerSecurityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          command: ["/bin/sh", "-ec"]
          args:
            - |
{{ .Files.Get $script | indent 14 }}
          env:
            {{- if not $setup.databaseUrlSecret.name }}
            - name: APOLLO_SECRET_DIR
              value: {{ .Values.apollo.secretsDir | quote }}
            {{- end }}
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: {{ default (include "composio.coreSecretName" .) $setup.databaseUrlSecret.name }}
                  key: {{ $setup.databaseUrlSecret.key }}
                  {{- if not $setup.databaseUrlSecret.name }}
                  optional: true
                  {{- end }}
            - name: MIGRATION_ROLE
              value: {{ $setup.migrationRole | quote }}
          volumeMounts:
            - name: apollo-secrets
              mountPath: {{ .Values.apollo.secretsDir | quote }}
              readOnly: true
            {{- with .Values.apollo.dbInit.volumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
      volumes:
        - name: apollo-secrets
          emptyDir: {}
        {{- with .Values.apollo.dbInit.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
{{- end }}
{{- end }}
