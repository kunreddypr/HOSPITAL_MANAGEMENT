{{- define "telemedicine.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end -}}

{{- define "telemedicine.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "telemedicine.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
