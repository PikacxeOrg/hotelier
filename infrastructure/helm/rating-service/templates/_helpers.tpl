{{- define "rating-service.name" -}}
rating-service
{{- end -}}

{{- define "rating-service.fullname" -}}
{{- printf "%s" (include "rating-service.name" .) -}}
{{- end -}}
