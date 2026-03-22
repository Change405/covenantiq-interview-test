{{- define "worker.name" -}}
{{- default .Chart.Name .Values.worker.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "worker.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "worker.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "worker.labels" -}}
app.kubernetes.io/name: {{ include "worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "worker.serviceAccountName" -}}
{{- if .Values.worker.serviceAccount.create -}}
{{- default (include "worker.fullname" .) .Values.worker.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.worker.serviceAccount.name -}}
{{- end -}}
{{- end -}}

