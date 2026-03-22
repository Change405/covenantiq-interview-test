{{- define "service-a.name" -}}
{{- default .Chart.Name .Values.serviceA.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service-a.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "service-a.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service-a.labels" -}}
app.kubernetes.io/name: {{ include "service-a.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "service-a.serviceAccountName" -}}
{{- if .Values.serviceA.serviceAccount.create -}}
{{- default (include "service-a.fullname" .) .Values.serviceA.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceA.serviceAccount.name -}}
{{- end -}}
{{- end -}}

