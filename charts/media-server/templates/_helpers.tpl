{{/*
Expand the name of the chart.
*/}}
{{- define "media-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "media-server.fullname" -}}
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
{{- define "media-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "media-server.labels" -}}
helm.sh/chart: {{ include "media-server.chart" . }}
{{ include "media-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "media-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "media-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component-specific labels
*/}}
{{- define "media-server.componentLabels" -}}
{{- $component := . -}}
app.kubernetes.io/component: {{ $component }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "media-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "media-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common security context for applications
*/}}
{{- define "media-server.securityContext" -}}
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
runAsNonRoot: true
{{- end }}

{{/*
Common volume mounts for media applications
*/}}
{{- define "media-server.commonVolumeMounts" -}}
- name: media-library
  mountPath: /data/library
- name: downloads
  mountPath: /data/downloads
{{- end }}

{{/*
Common volumes for media applications
*/}}
{{- define "media-server.commonVolumes" -}}
- name: media-library
  hostPath:
    path: {{ .Values.hostPath }}/library
    type: Directory
- name: downloads
  hostPath:
    path: {{ .Values.hostPath }}/downloads
    type: Directory
{{- end }}

{{/*
Host path volume for application config
*/}}
{{- define "media-server.configVolume" -}}
{{- $root := .root -}}
{{- $component := .component -}}
- name: {{ $component }}-config
  hostPath:
    path: {{ $root.Values.hostPath }}/config/{{ $component }}
    type: DirectoryOrCreate
{{- end }}

{{/*
Config volume mount for application
*/}}
{{- define "media-server.configVolumeMount" -}}
{{- $component := . -}}
- name: {{ $component }}-config
  mountPath: /config
{{- end }}

{{/*
Database environment variables for Sonarr/Radarr
*/}}
{{- define "media-server.databaseEnv" -}}
{{- $root := .root -}}
{{- $app := .app -}}
{{- $config := .config -}}
- name: {{ upper $app }}__POSTGRES_HOST
  value: {{ include "media-server.fullname" $root }}-postgresql
- name: {{ upper $app }}__POSTGRES_PORT
  value: "5432"
- name: {{ upper $app }}__POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: postgres-credentials
      key: POSTGRES_USER
- name: {{ upper $app }}__POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-credentials
      key: POSTGRES_PASSWORD
- name: {{ upper $app }}__POSTGRES_MAIN_DB
  value: {{ $config.database.main }}
- name: {{ upper $app }}__POSTGRES_LOG_DB
  value: {{ $config.database.logs }}
{{- end }}

{{/*
Common environment variables
*/}}
{{- define "media-server.commonEnv" -}}
- name: TZ
  value: "UTC"
- name: PUID
  value: "1000"
- name: PGID
  value: "1000"
{{- end }}