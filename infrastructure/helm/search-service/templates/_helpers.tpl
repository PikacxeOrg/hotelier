{{- define "search-service.name" -}}
search-service
{{- end -}}

{{- define "search-service.fullname" -}}
{{- printf "%s" (include "search-service.name" .) -}}
{{- end -}}
