# ClamAV Helm Chart

## Contents

- [What is ClamAV?](#what-is-clamav)
- [Workload Types](#workload-types)
- [Quick Start](#quick-start)
- [Containers](#containers)
- [Volumes and Storage](#volumes-and-storage)
- [Configuration](#configuration)
- [Services](#services)
- [Health Probes](#health-probes)
- [Resource Considerations](#resource-considerations)
- [Security](#security)
- [Available clamd.conf Settings](#available-clamdconf-settings)
  - [Logging](#logging)
  - [Process & System](#process--system)
  - [Database](#database)
  - [Network & Sockets](#network--sockets)
  - [Connection & Threading](#connection--threading)
  - [Scanning Behaviour](#scanning-behaviour)
  - [File Types](#file-types)
  - [Heuristic Alerts](#heuristic-alerts)
  - [Data Loss Prevention (DLP)](#data-loss-prevention-dlp)
  - [Limits](#limits)
  - [On-access Scanning](#on-access-scanning)
  - [Bytecode](#bytecode)
- [Available freshclam.conf Settings](#available-freshclamconf-settings)
  - [Logging](#logging-1)
  - [Process & System](#process--system-1)
  - [Database & Mirrors](#database--mirrors)
  - [Update Frequency & Connection](#update-frequency--connection)
  - [Proxy](#proxy)
  - [Notifications & Events](#notifications--events)
- [References](#references)
- [Local Development (Minikube)](#local-development-minikube)

---

## What is ClamAV?

[ClamAV](https://github.com/Cisco-Talos/clamav) is an open-source antivirus engine maintained by Cisco Talos. It runs as a daemon (`clamd`) that listens for scan requests over a TCP socket. Consumer services connect to it and submit files to be scanned for malware before they are processed or stored.

Rather than each application bundling its own antivirus library, ClamAV runs as a centralised, shared service in the cluster. Consumers send files to it over the network and receive a clean/infected verdict.

This chart uses the **official `clamav/clamav` image** published by the ClamAV project on Docker Hub.

---

## Workload Types

The chart supports three deployment models, selected via `workload.type`.

### `statefulset` (default)

Each pod has a stable identity and its own PersistentVolumeClaim via `volumeClaimTemplates`. Definitions persist across pod restarts — no re-download on restart. A headless service gives each pod a stable DNS name.

**Best for:** a central scanning service with stable storage and no extra operational overhead.

```
┌──────────────────────────────────────────────────────────┐
│  StatefulSet: clamav   (namespace: clamav-system)        │
│                                                          │
│  ┌────────────────────┐   ┌──────────────────────────┐   │
│  │  container: clamd  │   │  container: freshclam    │   │
│  │  Listens on :3310  │   │  Polls ClamAV CDN        │   │
│  │  Loads definitions │   │  Downloads new virus     │   │
│  │  from PVC          │   │  definitions             │   │
│  │                    │   │  Notifies clamd to       │   │
│  │                    │   │  reload via Unix socket  │   │
│  └────────┬───────────┘   └──────────┬───────────────┘   │
│           │                          │                    │
│           └──────────┬───────────────┘                    │
│                      │ /run/clamav/clamd.sock             │
│                 emptyDir volume (shared)                  │
│                                                          │
│  ┌───────────────────────────────────────────────────┐   │
│  │  PersistentVolumeClaim: definitions-clamav-0      │   │
│  │  One PVC per pod — persists across restarts       │   │
│  └───────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘

        ▲ ClusterIP service: clamav:3310
        │ (load-balanced across ready pods)
        │
  consumer services
```

### `deployment`

Stateless replicas with a single shared PVC. Simpler than a StatefulSet — no stable pod identity, no per-pod PVC. With `replicaCount > 1` the PVC must have `accessMode: ReadWriteMany`.

**Best for:** horizontal scaling when stable pod identity isn't needed and shared storage (e.g. NFS, cloud RWX volumes) is available.

```
┌──────────────────────────────────────────────────────────┐
│  Deployment: clamav    (namespace: clamav-system)        │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  Pod (replica 1)  clamd + freshclam             │     │
│  └─────────────────────────────────────────────────┘     │
│  ┌─────────────────────────────────────────────────┐     │
│  │  Pod (replica N)  ...                           │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
│  ┌───────────────────────────────────────────────────┐   │
│  │  PersistentVolumeClaim: clamav-definitions        │   │
│  │  Single shared PVC (RWX for multi-replica)        │   │
│  └───────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘

        ▲ ClusterIP service: clamav:3310
```

### `daemonset`

One pod per node. Each pod scans files on that node and keeps its own definition copy. The optional `hostScanning` feature mounts the node's root filesystem read-only into the pod, enabling node-level AV scanning.

**Best for:** security scanning at the infrastructure layer — scanning files on every node, including container images and host binaries.

```
┌──────────────────────────────────────────────────────────┐
│  DaemonSet: clamav     (namespace: clamav-system)        │
│                                                          │
│  ┌──────────────────┐   ┌──────────────────┐            │
│  │  Pod on Node A   │   │  Pod on Node B   │  ...       │
│  │  clamd + fresh   │   │  clamd + fresh   │            │
│  └────────┬─────────┘   └────────┬─────────┘            │
│           │                      │                       │
│  hostPath: /var/lib/clamav    hostPath: /var/lib/clamav  │
│  (definitions per node)       (definitions per node)     │
│                                                          │
│  With hostScanning.enabled: true                         │
│  mounts node / → /host (read-only) in each pod           │
└──────────────────────────────────────────────────────────┘

        ▲ ClusterIP service: clamav:3310
        │ (one endpoint per node)
```

---

## Local Development (Minikube)

See [minikube/](minikube/) for a self-contained local dev setup:

```bash
./minikube/deploy.sh   # start minikube and install the chart
./minikube/test.sh     # run smoke tests against the running instance
```

Handles Apple Silicon (AMD64 image emulation via Docker Desktop), low-memory resource sizing, and `TestDatabases` disabled to avoid OOM on the constrained VM. See [minikube/README.md](minikube/README.md) for details.

---

## Quick Start

```bash
# Default: StatefulSet with dynamic PVC (cluster default storage class)
helm install clamav ./charts/clamav

# Deployment with shared PVC
helm install clamav ./charts/clamav \
  --set workload.type=deployment

# DaemonSet with per-node hostPath storage and host scanning
helm install clamav ./charts/clamav \
  --set workload.type=daemonset \
  --set persistence.definitions.type=hostPath \
  --set daemonset.hostScanning.enabled=true

# Use an existing PVC (any workload type)
helm install clamav ./charts/clamav \
  --set persistence.definitions.type=existingClaim \
  --set persistence.definitions.existingClaim=my-clamav-pvc

# Ephemeral storage — re-downloads definitions on restart (~300MB, slow cold start)
helm install clamav ./charts/clamav \
  --set persistence.definitions.type=emptyDir
```

---

## Containers

All workload types run the same three containers from the official `clamav/clamav` image.

### `clamd` (main container)

The ClamAV daemon. It:
- Loads virus definitions from the configured storage on startup
- Listens on TCP port `3310` for scan requests
- Accepts connections from consumers via the ClusterIP service
- Reloads definitions automatically when freshclam updates them (via `SelfCheck` and Unix socket notification)

### `freshclam` (sidecar)

Runs alongside `clamd` in the same pod. It:
- Polls `database.clamav.net` for updated virus definitions (configurable frequency)
- Downloads updates into the definitions volume
- Notifies `clamd` to reload definitions via the Unix socket at `/run/clamav/clamd.sock`
- Does **not** run `clamd` itself (`CLAMAV_NO_CLAMD=true`)

### `freshclam-init` (init container)

Runs once before the pod starts. Performs an initial definition download so that `clamd` has definitions available immediately on first startup, rather than waiting for the freshclam sidecar's first scheduled check.

---

## Volumes and Storage

### Fixed volumes (all workload types)

| Volume | Type | Purpose |
|---|---|---|
| `config` | ConfigMap | Mounts `clamd.conf` and `freshclam.conf` into containers. |
| `run` | emptyDir | Ephemeral shared directory for the Unix socket (`clamd.sock`) used by freshclam to notify clamd of definition updates. Exists only for the lifetime of the pod. |

### Definitions volume (`persistence.definitions.type`)

The definitions volume stores the ~300MB virus database shared between `clamd` and the `freshclam` sidecar.

| `type` | StatefulSet | Deployment | DaemonSet | Description |
|---|---|---|---|---|
| `pvc` | volumeClaimTemplate (one PVC per pod) | Shared PVC (chart-managed) | Chart-managed PVC (not recommended) | Dynamic PVC. Best option for StatefulSet and single-replica Deployment. |
| `existingClaim` | ✓ | ✓ | ✓ | Pre-existing PVC — any storage backend (NFS, cloud disk, CSI). You manage the PVC lifecycle. |
| `emptyDir` | ✓ | ✓ | ✓ | Ephemeral. Re-downloads definitions on every pod restart. Zero infra overhead but slow cold starts. |
| `hostPath` | Unusual | Unusual | **Recommended** | Stores definitions at a path on the node filesystem. Survives pod restarts without a PVC. Natural fit for DaemonSet. |

**DaemonSet storage note:** `hostPath` is strongly preferred over `pvc` for DaemonSet. A chart-managed PVC is `ReadWriteOnce`, meaning only one pod can mount it — which defeats the purpose of a DaemonSet running on multiple nodes.

**Deployment multi-replica note:** With `replicaCount > 1` and `type: pvc`, the PVC must use `accessMode: ReadWriteMany`. Not all storage classes support RWX — check your cluster's available storage classes.

```yaml
# Example: Deployment with NFS-backed RWX PVC
workload:
  type: deployment
replicaCount: 3
persistence:
  definitions:
    type: pvc
    storageClassName: nfs-client
    accessMode: ReadWriteMany
    size: 2Gi
```

---

## Configuration

Both `clamd.conf` and `freshclam.conf` are rendered from `values.yaml` via ConfigMap. Override any directive under `config.clamd` or `config.freshclam`:

```yaml
config:
  clamd: |
    TCPSocket 3310
    TCPAddr 0.0.0.0
    LocalSocket /run/clamav/clamd.sock
    DatabaseDirectory /var/lib/clamav
    MaxFileSize 100M
    MaxScanSize 200M
    # add or override any clamd.conf directive here

  freshclam: |
    DatabaseDirectory /var/lib/clamav
    DatabaseMirror database.clamav.net
    Checks 24
    # add or override any freshclam.conf directive here
```

### Default `clamd.conf` values

| Setting | Default | Description |
|---|---|---|
| `TCPSocket` | `3310` | Port clamd listens on |
| `TCPAddr` | `0.0.0.0` | Accept connections from any address within the cluster |
| `LocalSocket` | `/run/clamav/clamd.sock` | Unix socket for freshclam sidecar communication |
| `DatabaseDirectory` | `/var/lib/clamav` | Definitions mount point |
| `SelfCheck` | `3600` | clamd re-checks definitions on disk every hour |
| `ConcurrentDatabaseReload` | `yes` | Background reload — no scan blocking. Uses ~2x RAM briefly during reload. |
| `MaxFileSize` | `500M` | Files larger than this are not scanned |
| `MaxScanSize` | `900M` | Maximum data scanned within an archive |
| `MaxThreads` | `10` | Maximum concurrent scans |
| `MaxConnectionQueueLength` | `200` | Maximum queued scan requests |
| `ReadTimeout` | `180` | Seconds before an idle connection is dropped |

### Default `freshclam.conf` values

| Setting | Default | Description |
|---|---|---|
| `DatabaseDirectory` | `/var/lib/clamav` | Where to write downloaded definitions |
| `DatabaseMirror` | `database.clamav.net` | Official ClamAV CDN |
| `Checks` | `24` | Check for updates 24 times per day (~hourly) |
| `TestDatabases` | `yes` | Validates downloaded definitions before making them live |
| `NotifyClamd` | `/etc/clamav/clamd.conf` | Notifies clamd to reload after a successful update |

---

## Services

### ClusterIP service (`service.main`)

Exposes clamd to consumers on port `3310`. Load-balances across all ready pods for all workload types.

```
clamav.clamav-system.svc.cluster.local:3310
```

### Headless service (`service.headless`)

Only rendered when `workload.type: statefulset`. Required by Kubernetes StatefulSets to give each pod a stable DNS identity:

```
clamav-0.clamav-headless.clamav-system.svc.cluster.local:3310
clamav-1.clamav-headless.clamav-system.svc.cluster.local:3310
```

Not created for Deployment or DaemonSet workloads.

---

## Health Probes

ClamAV takes significant time to start — it must load the full virus definition database (~300MB) into memory before it can scan. The three probes work together to handle this safely.

### Startup Probe

```yaml
exec:
  command: [clamdscan, --no-summary, /etc/hostname]
failureThreshold: 30
periodSeconds: 10
```

Runs `clamdscan` against `/etc/hostname` (a small, always-present, always-clean file) every 10 seconds, up to 5 minutes. Confirms `clamd` is not just listening but **functionally able to scan**. Readiness and liveness probes do not start until this passes.

### Readiness Probe

```yaml
tcpSocket:
  port: 3310
periodSeconds: 10
```

Lightweight TCP check every 10 seconds. If this fails, the pod is removed from the ClusterIP service's endpoints and stops receiving scan requests. No `initialDelaySeconds` needed — the startup probe already handles the wait.

### Liveness Probe

```yaml
tcpSocket:
  port: 3310
periodSeconds: 30
failureThreshold: 3
```

If it fails 3 consecutive times (90 seconds), Kubernetes restarts the container.

---

## Resource Considerations

ClamAV is memory-intensive. The virus definition database is loaded entirely into RAM on startup and kept there for fast scanning. As of 2024, the database is approximately 300MB on disk but expands to ~1GB+ in memory.

| Container | Request | Limit | Notes |
|---|---|---|---|
| `clamd` | 3Gi / 500m | 4Gi / 2 | `ConcurrentDatabaseReload yes` briefly doubles memory usage during a reload |
| `freshclam` | 256Mi / 100m | 1Gi / 300m | Only downloads and writes files |
| `freshclam-init` | 512Mi / 200m | 1Gi / 500m | Runs once at pod start |

Override per-environment in your values file:

```yaml
clamd:
  resources:
    requests:
      memory: "2Gi"
      cpu: "250m"
    limits:
      memory: "3Gi"
      cpu: "1"
```

---

## Security

### Default configuration

| Setting | Value | Scope | Notes |
|---|---|---|---|
| `fsGroup` | `101` | Pod | Makes the definitions volume writable by the `clamav` group (GID 101) |
| `runAsUser` | root (default) | All containers | See known issue below |
| `runAsNonRoot` | not set | All containers | See known issue below |

No `seccompProfile`, `allowPrivilegeEscalation`, or `runAsNonRoot` are configured by default. All containers run as root.

### Known Issue: Root Execution

The official `clamav/clamav` image runs as root by default. The entrypoint script (`/init`) performs several root-only operations at startup:

- `chown -R clamav:clamav /var/lib/clamav` — takes ownership of the definitions directory
- `ln -f -s "/run/lock" "/var/lock"` — creates a symlink in a root-owned path

These prevent straightforward use of `runAsNonRoot: true` or `--user 100:101`.

Upstream tracking:
- [#478](https://github.com/Cisco-Talos/clamav/issues/478) — original non-root request (open)
- [#520](https://github.com/Cisco-Talos/clamav/issues/520) — rootless in Kubernetes, closed as "not planned" / duplicate
- [#668](https://github.com/Cisco-Talos/clamav/issues/668) — unprivileged image request, closed as completed Nov 2022

PR [#666](https://github.com/Cisco-Talos/clamav/pull/666) was merged in September 2022 to move the socket/PID to `/tmp` and set `USER 100`, but was **reverted the same day** due to undisclosed issues.

### Workaround: `/init-unprivileged`

The official ClamAV docs document an alternative entrypoint that avoids the root-only operations. To use it, override the entrypoint and set a security context on each container:

```yaml
# clamd and freshclam containers
command: ["/init-unprivileged"]
securityContext:
  runAsNonRoot: true
  runAsUser: 100
  runAsGroup: 101
  allowPrivilegeEscalation: false
```

```yaml
# freshclam-init (already overrides the entrypoint directly — no command change needed)
securityContext:
  runAsNonRoot: true
  runAsUser: 100
  runAsGroup: 101
  allowPrivilegeEscalation: false
```

The pod-level `fsGroup: 101` already ensures the definitions volume is writable by GID 101.

**Caveats:**
- `/init-unprivileged` is the documented workaround but not as widely validated as the standard entrypoint
- `CLAMAV_NO_FRESHCLAMD` and `CLAMAV_NO_CLAMD` env vars are expected to work but should be verified on first deploy
- If `clamd` fails to create `/run/clamav` on startup, an init container may be needed to pre-create the directory with correct ownership
- No official timeline exists for non-root becoming the default — upstream issue [#478](https://github.com/Cisco-Talos/clamav/issues/478) remains open

---

## Available clamd.conf Settings

Full reference for all supported `clamd.conf` directives. Override any of these in `values.yaml` under `config.clamd`.

### Logging

| Setting | Default | Description |
|---|---|---|
| `LogFile` | disabled | Write logs to a file. Must be writable by the clamav user. |
| `LogFileUnlock` | no | Disable log file locking (needed if running multiple clamd instances). |
| `LogFileMaxSize` | 1M | Max log file size before rotation. `0` disables the limit. |
| `LogTime` | no | Prefix each log line with a timestamp. |
| `LogClean` | no | Also log clean (non-infected) files. Increases log volume significantly. |
| `LogSyslog` | no | Send logs to the system logger alongside (or instead of) `LogFile`. |
| `LogFacility` | LOG_LOCAL6 | Syslog facility to use. |
| `LogVerbose` | no | Enable verbose logging. |
| `LogRotate` | no | Rotate logs. Automatically enabled when `LogFileMaxSize` is set. |
| `ExtendedDetectionInfo` | no | Include file size and hash alongside the virus name in detections. |

### Process & System

| Setting | Default | Description |
|---|---|---|
| `PidFile` | disabled | Write the daemon PID to this file. |
| `TemporaryDirectory` | /tmp | Override the directory used for temporary files during scans. |
| `Foreground` | no | Don't fork to background. Required in containers. |
| `User` | — | Drop privileges to this user after startup (requires root to start). |
| `ExitOnOOM` | no | Terminate clamd if libclamav reports an out-of-memory condition. |
| `Debug` | no | Enable debug messages from libclamav. |
| `LeaveTemporaryFiles` | no | Keep temp files on disk after scanning (debug only). |
| `GenerateMetadataJson` | no | Write scan metadata JSON to the temp directory (requires `LeaveTemporaryFiles`). |

### Database

| Setting | Default | Description |
|---|---|---|
| `DatabaseDirectory` | hardcoded | Path to the virus definition database. |
| `OfficialDatabaseOnly` | no | Reject third-party signatures — only load official ClamAV `.cvd` files. |
| `FailIfCvdOlderThan` | -1 | Exit with an error if the database is older than N days. `-1` disables the check. |
| `SelfCheck` | 600 | Interval (seconds) at which clamd checks for updated definitions on disk. |
| `ConcurrentDatabaseReload` | yes | Reload definitions in the background without blocking scans. Uses ~2x RAM briefly. |

### Network & Sockets

| Setting | Default | Description |
|---|---|---|
| `TCPSocket` | disabled | TCP port to listen on. |
| `TCPAddr` | INADDR_ANY | IP address to bind to. |
| `LocalSocket` | disabled | Unix socket path. |
| `LocalSocketGroup` | primary group | Set group ownership on the Unix socket. |
| `LocalSocketMode` | world accessible | Set permissions on the Unix socket (e.g. `660`). |
| `FixStaleSocket` | yes | Remove stale socket file left over from an unclean shutdown. |
| `StreamMaxLength` | 100M | Max data size for stream-based scans (e.g. INSTREAM command). |
| `StreamMinPort` | 1024 | Lower bound of port range for stream transfers. |
| `StreamMaxPort` | 2048 | Upper bound of port range for stream transfers. |

### Connection & Threading

| Setting | Default | Description |
|---|---|---|
| `MaxConnectionQueueLength` | 200 | Max number of pending connections waiting to be accepted. |
| `MaxThreads` | 10 | Max number of concurrent scan threads. |
| `ReadTimeout` | 120 | Seconds to wait for data from a connected client before dropping. |
| `CommandReadTimeout` | 30 | Seconds to wait for an initial command from a client after connecting. |
| `SendBufTimeout` | 500 | Milliseconds to wait when the send buffer is full. Keep low to prevent hangs. |
| `MaxQueue` | 100 | Max items queued for scanning (including those actively being processed). |
| `IdleTimeout` | 30 | Seconds to wait for a new job before a thread exits. |

### Scanning Behaviour

| Setting | Default | Description |
|---|---|---|
| `ExcludePath` | scan all | Regex pattern for paths to skip. Can be specified multiple times. |
| `MaxDirectoryRecursion` | 15 | Max depth to recurse into directories. |
| `FollowDirectorySymlinks` | no | Follow symlinks to directories. |
| `FollowFileSymlinks` | no | Follow symlinks to files. |
| `CrossFilesystems` | yes | Scan files on other mounted filesystems. |
| `VirusEvent` | disabled | Shell command to run when a virus is detected. Use env vars `CLAM_VIRUSEVENT_FILENAME` / `CLAM_VIRUSEVENT_VIRUSNAME`. |
| `AllowAllMatchScan` | yes | Allow clients to use the `ALLMATCHSCAN` command (continue scanning after first hit). |
| `ForceToDisk` | no | Write memory/nested map scan content to disk. Useful with `LeaveTemporaryFiles`. |
| `DisableCache` | no | Disable the MD5 scan cache. Reduces performance. |
| `CacheSize` | 65536 | Number of entries in the scan cache. Must be a square number. |
| `HeuristicAlerts` | yes | Alert on files with heuristically detected suspicious patterns. |
| `HeuristicScanPrecedence` | no | Stop scanning immediately when a heuristic match is found. Saves CPU. |
| `DetectPUA` | no | Detect Potentially Unwanted Applications. |
| `ExcludePUA` | all | Exclude a PUA category (e.g. `NetTool`). Requires `DetectPUA yes`. |
| `IncludePUA` | all | Only alert on specific PUA categories. Requires `DetectPUA yes`. |

### File Types

| Setting | Default | Description |
|---|---|---|
| `ScanPE` | yes | Deep analysis of Windows PE executables. Required for unpacking UPX, FSG, Petite. |
| `DisableCertCheck` | no | Skip authenticode certificate verification on PE files. |
| `ScanELF` | yes | Scan Linux ELF executables. |
| `ScanOLE2` | yes | Scan OLE2 containers (Word, Excel, `.msi` files). |
| `ScanPDF` | yes | Scan within PDF files. |
| `ScanSWF` | yes | Scan Flash `.swf` files. |
| `ScanXMLDOCS` | yes | Scan XML-based document formats. |
| `ScanHWP3` | yes | Scan Hangul Word Processor files. |
| `ScanOneNote` | yes | Scan Microsoft OneNote files. |
| `ScanImage` | yes | Scan image/graphics files. |
| `ScanImageFuzzyHash` | yes | Detect images using fuzzy hashing (used to match embedded images). |
| `ScanHTML` | yes | Normalise and scan HTML, including MS Script Encoder content. |
| `ScanArchive` | yes | Scan inside archives (zip, tar, rar, etc.). |
| `ScanMail` | yes | Parse and scan email messages and attachments. |
| `ScanPartialMessages` | no | Scan RFC1341 messages split across multiple emails. Has DoS risk — do not enable on busy servers. |
| `PhishingSignatures` | yes | Detect phishing using HTML/Email NDB signatures. |
| `PhishingScanURLs` | yes | Detect phishing by analysing URLs in emails. |

### Heuristic Alerts

| Setting | Default | Description |
|---|---|---|
| `AlertBrokenExecutables` | no | Alert on malformed PE or ELF files. |
| `AlertBrokenMedia` | no | Alert on malformed JPEG, TIFF, PNG, or GIF files. |
| `AlertEncrypted` | no | Alert on encrypted archives and documents. |
| `AlertEncryptedArchive` | no | Alert on encrypted archives (zip, 7zip, rar) only. |
| `AlertEncryptedDoc` | no | Alert on encrypted PDFs only. |
| `AlertOLE2Macros` | no | Flag OLE2 files containing VBA macros not matched by signatures. |
| `AlertPhishingSSLMismatch` | no | Alert on SSL mismatches in URLs. May produce false positives. |
| `AlertPhishingCloak` | no | Alert on cloaked URLs. May produce false positives. |
| `AlertPartitionIntersection` | no | Alert on raw DMG images with partition intersections. |
| `AlertExceedsMax` | no | Flag files exceeding `MaxFileSize`, `MaxScanSize`, or `MaxRecursion` with a `Heuristics.Limits.Exceeded` name rather than silently skipping. |

### Data Loss Prevention (DLP)

| Setting | Default | Description |
|---|---|---|
| `StructuredDataDetection` | no | Enable DLP scanning for credit card numbers and SSNs. |
| `StructuredMinCreditCardCount` | 3 | Minimum number of credit card numbers in a file to trigger an alert. |
| `StructuredCCOnly` | no | Only search for credit card numbers (skip debit/private label). |
| `StructuredMinSSNCount` | 3 | Minimum number of SSNs in a file to trigger an alert. |
| `StructuredSSNFormatNormal` | yes | Match SSNs in `xxx-yy-zzzz` format. |
| `StructuredSSNFormatStripped` | no | Match SSNs in `xxxyyzzzz` format (no dashes). |

### Limits

These protect against archive bomb / DoS attacks. All limits can be set to `0` to disable, but this is not recommended.

| Setting | Default | Description |
|---|---|---|
| `MaxScanTime` | 120000ms | Max time (ms) a scan may take. Currently only affects ZIP scanning. |
| `MaxScanSize` | 400M | Max total data extracted and scanned from a container (e.g. archive). |
| `MaxFileSize` | 100M | Max individual file size to scan. Files larger than this are skipped. |
| `MaxRecursion` | 17 | Max depth for nested archive extraction. |
| `MaxFiles` | 10000 | Max number of files scanned within a single container. |
| `MaxEmbeddedPE` | 40M | Max file size to check for embedded PE executables. |
| `MaxHTMLNormalize` | 40M | Max HTML file size to normalise before scanning. |
| `MaxHTMLNoTags` | 8M | Max size of normalised HTML to scan. |
| `MaxScriptNormalize` | 20M | Max script size to normalise before scanning. |
| `MaxZipTypeRcg` | 1M | Max ZIP size to re-analyse for type recognition. |
| `MaxPartitions` | 50 | Max number of partitions to scan in a raw disk image. |
| `MaxIconsPE` | 100 | Max number of icons to scan in a PE file. |
| `MaxRecHWP3` | 16 | Max recursive calls when parsing HWP3 files. |
| `PCREMatchLimit` | 100000 | Max PCRE match function calls per regex match. |
| `PCRERecMatchLimit` | 2000 | Max recursive PCRE match calls per regex match. |
| `PCREMaxFileSize` | 100M | Max file size for PCRE signature evaluation. |

### On-access Scanning

> Not used in this chart. On-access scanning (`clamonacc`) monitors filesystem events in real time using Linux `fanotify`. It requires privileged access and is separate from the network-scanning daemon model this chart uses. The DaemonSet `hostScanning` feature is a simpler alternative for node-level scanning that does not require `fanotify`.

| Setting | Default | Description |
|---|---|---|
| `OnAccessMaxFileSize` | 5M | Max file size to scan on access. |
| `OnAccessMaxThreads` | 5 | Thread pool size for on-access scanning. |
| `OnAccessIncludePath` | disabled | Paths to watch. |
| `OnAccessExcludePath` | disabled | Paths to exclude from watching. |
| `OnAccessPrevention` | no | Block access to files while scanning (requires fanotify). |
| `OnAccessDenyOnError` | no | Deny access if a scan error occurs. |

### Bytecode

| Setting | Default | Description |
|---|---|---|
| `Bytecode` | yes | Load bytecode signatures from the database. Strongly recommended — disabling will miss many detections. |
| `BytecodeSecurity` | TrustSigned | `TrustSigned` (recommended), `Paranoid` (all bytecode sandboxed), `None` (debug only — never use in production). |
| `BytecodeUnsigned` | no | Allow loading bytecode from unsigned sources. **Never enable** — arbitrary code execution risk. |
| `BytecodeTimeout` | 10000ms | Max execution time for a bytecode signature. |

---

## Available freshclam.conf Settings

Full reference for all supported `freshclam.conf` directives. Override any of these in `values.yaml` under `config.freshclam`.

### Logging

| Setting | Default | Description |
|---|---|---|
| `UpdateLogFile` | disabled | Write update logs to a file. |
| `LogFileMaxSize` | 1M | Max log file size. `0` disables the limit. |
| `LogTime` | no | Prefix each log line with a timestamp. |
| `LogVerbose` | no | Enable verbose logging. |
| `LogSyslog` | no | Send logs to the system logger. |
| `LogFacility` | LOG_LOCAL6 | Syslog facility to use. |
| `LogRotate` | no | Rotate logs. Automatically enabled when `LogFileMaxSize` is set. |

### Process & System

| Setting | Default | Description |
|---|---|---|
| `PidFile` | disabled | Write the freshclam PID to this file (daemon mode only). |
| `DatabaseOwner` | clamav | User that owns the database files. freshclam drops to this user on startup. |
| `Foreground` | no | Don't fork to background. Required in containers. |
| `Debug` | no | Enable debug messages from libclamav. |

### Database & Mirrors

| Setting | Default | Description |
|---|---|---|
| `DatabaseDirectory` | hardcoded | Where to write downloaded definitions. Must match `clamd.conf`. |
| `DNSDatabaseInfo` | current.cvd.clamav.net | DNS domain used to check for database version. |
| `DatabaseMirror` | — | Mirror to download definitions from. |
| `PrivateMirror` | disabled | Point freshclam at a private mirror. Overrides `DatabaseMirror`, `DNSDatabaseInfo`, and `ScriptedUpdates`. Can be specified multiple times for fallback. |
| `DatabaseCustomURL` | disabled | Additional custom signature sources (`http://`, `https://`, `ftp://`, `file://`). Can be specified multiple times. |
| `ExtraDatabase` | — | Opt in to an additional signature database by name. |
| `ExcludeDatabase` | — | Opt out of a standard signature database by name. |
| `ScriptedUpdates` | yes | Download incremental (scripted) updates rather than full databases. Recommended. |
| `CompressLocalDatabase` | no | Store local `.cld` files compressed. Saves disk space at the cost of slightly slower loads. |
| `Bytecode` | yes | Download `bytecode.cvd` alongside virus definitions. |

### Update Frequency & Connection

| Setting | Default | Description |
|---|---|---|
| `Checks` | 12 | Number of update checks per day. |
| `MaxAttempts` | 3 | Number of download attempts per mirror before giving up. |
| `ConnectTimeout` | 30 | Seconds to wait when connecting to the database server. |
| `ReceiveTimeout` | 60 | Seconds to wait when receiving data. `0` disables the timeout. |

### Proxy

| Setting | Default | Description |
|---|---|---|
| `HTTPProxyServer` | disabled | Proxy server URL. Supports `http://`, `https://`, `socks4://`, `socks5://` schemes. |
| `HTTPProxyPort` | — | Proxy port. |
| `HTTPProxyUsername` | — | Proxy authentication username. |
| `HTTPProxyPassword` | — | Proxy authentication password. |
| `HTTPUserAgent` | clamav/version | Override the User-Agent header. Only works with private mirrors — ignored when connecting to the ClamAV CDN. |
| `LocalIPAddress` | OS default | Source IP address to use for outbound connections. Useful on multi-homed hosts. |

### Notifications & Events

| Setting | Default | Description |
|---|---|---|
| `NotifyClamd` | disabled | Path to `clamd.conf`. After a successful update, sends a `RELOAD` command to clamd via its Unix socket. |
| `TestDatabases` | yes | Load downloaded definitions into memory to validate them before replacing the live database. Uses extra RAM during the check. |
| `OnUpdateExecute` | disabled | Command to run after a successful update. |
| `OnErrorExecute` | disabled | Command to run when an update fails. |
| `OnOutdatedExecute` | disabled | Command to run when freshclam detects the installed ClamAV version is outdated. `%v` is replaced with the new version number. |

---

## References

| Resource | URL |
|---|---|
| ClamAV GitHub | https://github.com/Cisco-Talos/clamav |
| ClamAV Documentation | https://docs.clamav.net/ |
| Official Docker Image (`clamav/clamav`) | https://hub.docker.com/r/clamav/clamav |
| clamd.conf reference | https://docs.clamav.net/manual/Usage/Configuration.html#clamdconf |
| freshclam.conf reference | https://docs.clamav.net/manual/Usage/Configuration.html#freshclamconf |
