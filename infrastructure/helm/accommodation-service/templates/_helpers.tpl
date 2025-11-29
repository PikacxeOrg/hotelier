{{- define "accommodation-service.name" -}}
accommodation-service
{{- end -}}

{{- define "accommodation-service.fullname" -}}
{{- printf "%s" (include "accommodation-service.name" .) -}}
{{- end -}}
