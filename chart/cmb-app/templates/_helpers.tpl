{{- define "cmb-app.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "cmb-app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "cmb-app.labels" -}}
{{ include "cmb-app.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | trunc 12 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* repository:tag, plus @digest when CI has pinned one. */}}
{{- define "cmb-app.image" -}}
{{- $tag := required "image.tag must be set per environment" .Values.image.tag -}}
{{- if .Values.image.digest -}}
{{- printf "%s:%s@%s" .Values.image.repository $tag .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
Env vars read from the app Secret. DATABASE_READ_URL is optional: without it reads use the primary.
Usage: include "cmb-app.secretEnv" (dict "root" $ "keys" $w.secretEnv)
*/}}
{{- define "cmb-app.secretEnv" -}}
{{- range .keys }}
- name: {{ . }}
  valueFrom:
    secretKeyRef:
      name: {{ $.root.Values.secret.name }}
      key: {{ . }}
      {{- if eq . "DATABASE_READ_URL" }}
      optional: true
      {{- end }}
{{- end }}
{{- end -}}

{{/*
Settings shared by every container that runs the app image. The shared ConfigMap is added
separately (cmb-app.configEnv) because hook Jobs run before the ConfigMap exists.
*/}}
{{- define "cmb-app.containerBase" -}}
image: {{ include "cmb-app.image" . }}
imagePullPolicy: {{ .Values.image.pullPolicy }}
securityContext:
  {{- toYaml .Values.securityContext | nindent 2 }}
volumeMounts:
  - name: tmp
    mountPath: /tmp
{{- end -}}

{{- define "cmb-app.configEnv" -}}
envFrom:
  - configMapRef:
      name: {{ include "cmb-app.fullname" . }}
{{- end -}}

{{- define "cmb-app.podBase" -}}
automountServiceAccountToken: false
securityContext:
  {{- toYaml .Values.podSecurityContext | nindent 2 }}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
volumes:
  - name: tmp
    emptyDir:
      sizeLimit: 64Mi
{{- end -}}
