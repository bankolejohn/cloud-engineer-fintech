{{/*
Expand the name of the chart.
*/}}
{{- define "finflow-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "finflow-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "finflow-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "finflow-service.labels" -}}
helm.sh/chart: {{ include "finflow-service.chart" . }}
{{ include "finflow-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: finflow
{{- end }}

{{/*
Selector labels
*/}}
{{- define "finflow-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "finflow-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "finflow-service.name" . }}
version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "finflow-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "finflow-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
