{{- define "availability-service.name" -}}
availability-service
{{- end -}}

{{- define "availability-service.fullname" -}}
{{- printf "%s" (include "availability-service.name" .) -}}
{{- end -}}
