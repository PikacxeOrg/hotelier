{{- define "reservation-service.name" -}}
reservation-service
{{- end -}}

{{- define "reservation-service.fullname" -}}
{{- printf "%s" (include "reservation-service.name" .) -}}
{{- end -}}
