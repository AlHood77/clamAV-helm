{{/*
Expand the name of the chart.
*/}}
{{- define "clamav.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "clamav.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clamav.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{ include "clamav.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clamav.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clamav.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "clamav.name" . }}
{{- end }}

{{/*
Namespace helper
*/}}
{{- define "clamav.namespace" -}}
{{- .Values.namespace.name }}
{{- end }}

{{/*
Definitions volume entry for the volumes: section.
Used by Deployment and DaemonSet, and by StatefulSet for non-pvc storage types.
For StatefulSet + pvc, volumeClaimTemplates is used instead (not this helper).
*/}}
{{- define "clamav.definitionsVolume" -}}
- name: definitions
  {{- $p := .Values.persistence.definitions }}
  {{- if eq $p.type "existingClaim" }}
  persistentVolumeClaim:
    claimName: {{ $p.existingClaim }}
  {{- else if eq $p.type "hostPath" }}
  hostPath:
    path: {{ $p.hostPath.path }}
    type: {{ $p.hostPath.type }}
  {{- else if eq $p.type "emptyDir" }}
  emptyDir: {}
  {{- else }}{{/* pvc — references standalone PVC for Deployment/DaemonSet */}}
  persistentVolumeClaim:
    claimName: {{ include "clamav.fullname" . }}-definitions
  {{- end }}
{{- end }}

{{/*
freshclam init container — downloads definitions before clamd starts
*/}}
{{- define "clamav.freshclamInitContainer" -}}
- name: freshclam-init
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command:
    - freshclam
    - --config-file=/etc/clamav/freshclam.conf
    - --checks=1
  volumeMounts:
    - name: definitions
      mountPath: /var/lib/clamav
    - name: config
      mountPath: /etc/clamav/freshclam.conf
      subPath: freshclam.conf
  resources:
    {{- toYaml .Values.freshclamInit.resources | nindent 4 }}
{{- end }}

{{/*
clamd container — main antivirus daemon
*/}}
{{- define "clamav.clamdContainer" -}}
- name: clamd
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  env:
    - name: CLAMAV_NO_FRESHCLAMD
      value: {{ .Values.clamd.env.CLAMAV_NO_FRESHCLAMD | quote }}
  ports:
    - name: clamd
      containerPort: {{ .Values.service.main.port }}
      protocol: TCP
  volumeMounts:
    - name: definitions
      mountPath: /var/lib/clamav
    - name: config
      mountPath: /etc/clamav/clamd.conf
      subPath: clamd.conf
    - name: run
      mountPath: /run/clamav
    {{- if and (eq .Values.workload.type "daemonset") .Values.daemonset.hostScanning.enabled }}
    - name: host-root
      mountPath: {{ .Values.daemonset.hostScanning.mountPath }}
      readOnly: {{ .Values.daemonset.hostScanning.readOnly }}
    {{- end }}
  resources:
    {{- toYaml .Values.clamd.resources | nindent 4 }}
  startupProbe:
    exec:
      command:
        - clamdscan
        - --no-summary
        - /etc/hostname
    failureThreshold: {{ .Values.clamd.probes.startup.failureThreshold }}
    periodSeconds: {{ .Values.clamd.probes.startup.periodSeconds }}
  readinessProbe:
    tcpSocket:
      port: {{ .Values.service.main.port }}
    periodSeconds: {{ .Values.clamd.probes.readiness.periodSeconds }}
  livenessProbe:
    tcpSocket:
      port: {{ .Values.service.main.port }}
    periodSeconds: {{ .Values.clamd.probes.liveness.periodSeconds }}
    failureThreshold: {{ .Values.clamd.probes.liveness.failureThreshold }}
{{- end }}

{{/*
freshclam sidecar container — keeps definitions up to date
*/}}
{{- define "clamav.freshclamContainer" -}}
- name: freshclam
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  env:
    - name: CLAMAV_NO_CLAMD
      value: {{ .Values.freshclam.env.CLAMAV_NO_CLAMD | quote }}
    - name: FRESHCLAM_CHECKS
      value: {{ .Values.freshclam.env.FRESHCLAM_CHECKS | quote }}
  volumeMounts:
    - name: definitions
      mountPath: /var/lib/clamav
    - name: config
      mountPath: /etc/clamav/freshclam.conf
      subPath: freshclam.conf
    - name: run
      mountPath: /run/clamav
  resources:
    {{- toYaml .Values.freshclam.resources | nindent 4 }}
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "clamav.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "clamav.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common volumes: config configmap and run socket dir
*/}}
{{- define "clamav.commonVolumes" -}}
- name: config
  configMap:
    name: {{ include "clamav.fullname" . }}-config
- name: run
  emptyDir: {}
{{- end }}
