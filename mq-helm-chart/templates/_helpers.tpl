{{/*
Queue manager name in UPPERCASE (used in MQSC commands).
*/}}
{{- define "ibm-mq-qmgr.qmgrName" -}}
{{- .Values.queueManager.name | upper }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "ibm-mq-qmgr.labels" -}}
app.kubernetes.io/name: ibm-mq
app.kubernetes.io/instance: {{ .Values.queueManager.name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
