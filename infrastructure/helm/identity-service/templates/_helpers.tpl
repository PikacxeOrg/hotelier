{{- define "identity-service.name" -}}
identity-service
{{- end -}}

{{- define "identity-service.fullname" -}}
{{- printf "%s" (include "identity-service.name" .) -}}
{{- end -}}
