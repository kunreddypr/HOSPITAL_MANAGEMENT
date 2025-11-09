{{- define "notification.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end -}}

{{- define "notification.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "notification.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
