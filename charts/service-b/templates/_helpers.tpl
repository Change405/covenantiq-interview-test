{{- define "service-b.name" -}}
{{- default .Chart.Name .Values.serviceB.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service-b.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "service-b.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service-b.labels" -}}
app.kubernetes.io/name: {{ include "service-b.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "service-b.serviceAccountName" -}}
{{- if .Values.serviceB.serviceAccount.create -}}
{{- default (include "service-b.fullname" .) .Values.serviceB.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceB.serviceAccount.name -}}
{{- end -}}
{{- end -}}

