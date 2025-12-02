{{- define "cdn-service.name" -}}
cdn-service
{{- end -}}

{{- define "cdn-service.fullname" -}}
{{- printf "%s" (include "cdn-service.name" .) -}}
{{- end -}}
