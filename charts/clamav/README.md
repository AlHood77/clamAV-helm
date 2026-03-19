# ClamAV Helm Chart

A Helm chart for deploying [ClamAV](https://www.clamav.net/) as a StatefulSet on Kubernetes, with a `clamd` main container, a `freshclam` sidecar for live definition updates, and a `freshclam-init` init container for pre-seeding definitions on first boot.

---

## Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Values](#values)
- [Storage Modes](#storage-modes)
- [Security](#security)
- [Health Probes](#health-probes)
- [ClamAV Configuration Reference](#clamav-configuration-reference)
  - [clamd.conf](#clamdconf-settings)
  - [freshclam.conf](#freshclamconf-settings)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  StatefulSet: clamav  (namespace: clamav-system)        │
│                                                         │
│  ┌─────────────────────┐  ┌──────────────────────────┐  │
│  │  container: clamd   │  │  container: freshclam    │  │
│  │                     │  │                          │  │
│  │  Listens on :3310   │  │  Polls ClamAV CDN        │  │
│  │  Scans files        │  │  Downloads new virus     │  │
│  │  Loads definitions  │  │  definitions             │  │
│  │  from storage       │  │  Notifies clamd to       │  │
│  │                     │  │  reload via Unix socket  │  │
│  └─────────┬───────────┘  └────────────┬─────────────┘  │
│            │                           │                 │
│            └──────────┬────────────────┘                 │
│                       │ /run/clamav/clamd.sock           │
│                  emptyDir volume (shared)                │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  definitions volume (PVC, existingClaim, or      │   │
│  │  emptyDir depending on persistence config)       │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
         ▲ ClusterIP service: clamav:3310
         │ (load balances across ready pods)
         │
  validation-service (and other consumers)
```

### Why a StatefulSet?

A StatefulSet gives each pod a stable identity and its own PersistentVolumeClaim. Each pod retains its virus definition database across restarts — without this, every restart would re-download ~300MB from the ClamAV CDN.

---

## Quick Start

```bash
# Install with defaults (provisions a PVC using storageClass standard-rwo)
helm install clamav ./charts/clamav

# Install into an existing namespace
helm install clamav ./charts/clamav --set namespace.create=false --set namespace.name=my-namespace

# Use an existing PVC for definitions
helm install clamav ./charts/clamav --set persistence.definitions.existingClaim=my-pvc

# Ephemeral storage (re-downloads on every restart — useful for testing)
helm install clamav ./charts/clamav --set persistence.definitions.enabled=false

# Override resources for a smaller environment
helm install clamav ./charts/clamav \
  --set clamd.resources.requests.memory=2Gi \
  --set clamd.resources.limits.memory=3Gi
```

---

## Values

### Global

| Key | Default | Description |
|-----|---------|-------------|
| `replicaCount` | `1` | Number of ClamAV pods |

### Image

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `clamav/clamav` | Container image repository |
| `image.tag` | `1.4_base` | Image tag |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy |

### Namespace

| Key | Default | Description |
|-----|---------|-------------|
| `namespace.create` | `true` | Whether to create the namespace |
| `namespace.name` | `clamav-system` | Namespace to deploy into |

### Pod Security

| Key | Default | Description |
|-----|---------|-------------|
| `podSecurityContext.fsGroup` | `101` | Makes the definitions volume writable by the `clamav` group (GID 101) |

### Services

| Key | Default | Description |
|-----|---------|-------------|
| `service.main.enabled` | `true` | Create the ClusterIP service for consumers |
| `service.main.type` | `ClusterIP` | Service type |
| `service.main.port` | `3310` | Port exposed by the service |
| `service.headless.enabled` | `true` | Create the headless service required by the StatefulSet |

### Storage

See [Storage Modes](#storage-modes) for full details.

| Key | Default | Description |
|-----|---------|-------------|
| `persistence.definitions.enabled` | `true` | `false` uses an emptyDir (ephemeral) |
| `persistence.definitions.existingClaim` | `""` | Use a pre-existing PVC instead of provisioning one |
| `persistence.definitions.storageClassName` | `standard-rwo` | Storage class for the provisioned PVC. Set to `""` for the cluster default |
| `persistence.definitions.accessMode` | `ReadWriteOnce` | PVC access mode |
| `persistence.definitions.size` | `1Gi` | PVC size (definitions are ~300–400 MB on disk) |

### clamd Container

| Key | Default | Description |
|-----|---------|-------------|
| `clamd.resources.requests.memory` | `3Gi` | Memory request |
| `clamd.resources.requests.cpu` | `500m` | CPU request |
| `clamd.resources.limits.memory` | `4Gi` | Memory limit |
| `clamd.resources.limits.cpu` | `2` | CPU limit |
| `clamd.env.CLAMAV_NO_FRESHCLAMD` | `"true"` | Disables the built-in freshclamd — the sidecar handles updates |
| `clamd.probes.startup.failureThreshold` | `30` | Startup probe failure threshold (30 × 10s = 5 min max wait) |
| `clamd.probes.startup.periodSeconds` | `10` | Startup probe interval |
| `clamd.probes.readiness.periodSeconds` | `10` | Readiness probe interval |
| `clamd.probes.liveness.periodSeconds` | `30` | Liveness probe interval |
| `clamd.probes.liveness.failureThreshold` | `3` | Liveness probe failure threshold before pod restart |

### freshclam Sidecar

| Key | Default | Description |
|-----|---------|-------------|
| `freshclam.resources.requests.memory` | `256Mi` | Memory request |
| `freshclam.resources.requests.cpu` | `100m` | CPU request |
| `freshclam.resources.limits.memory` | `1Gi` | Memory limit |
| `freshclam.resources.limits.cpu` | `300m` | CPU limit |
| `freshclam.env.CLAMAV_NO_CLAMD` | `"true"` | Prevents the sidecar from starting its own clamd |
| `freshclam.env.FRESHCLAM_CHECKS` | `"24"` | Definition update checks per day |

### freshclam-init Init Container

| Key | Default | Description |
|-----|---------|-------------|
| `freshclamInit.resources.requests.memory` | `512Mi` | Memory request |
| `freshclamInit.resources.requests.cpu` | `200m` | CPU request |
| `freshclamInit.resources.limits.memory` | `1Gi` | Memory limit |
| `freshclamInit.resources.limits.cpu` | `500m` | CPU limit |

### ClamAV Configuration

The full contents of `clamd.conf` and `freshclam.conf` are exposed as values and rendered into a ConfigMap. Override individual settings by replacing the relevant lines in your `values.yaml` or via `--set-file`.

| Key | Description |
|-----|-------------|
| `config.clamd` | Full `clamd.conf` content (multiline string) |
| `config.freshclam` | Full `freshclam.conf` content (multiline string) |

See [ClamAV Configuration Reference](#clamav-configuration-reference) for all available directives.

---

## Storage Modes

The `definitions` volume is shared between `clamd`, `freshclam`, and the `freshclam-init` init container. Three modes are supported:

### 1. Dynamic PVC (default)

The chart provisions a PVC via `volumeClaimTemplates`. Each StatefulSet pod gets its own PVC.

```yaml
persistence:
  definitions:
    enabled: true
    storageClassName: standard-rwo   # or "" for cluster default
    accessMode: ReadWriteOnce
    size: 1Gi
```

### 2. Existing PVC

Bring your own pre-provisioned PVC — NFS, cloud-managed disk, CSI volume, etc. The `storageClassName`, `accessMode`, and `size` fields are ignored when this is set.

```yaml
persistence:
  definitions:
    existingClaim: my-nfs-definitions-pvc
```

### 3. Ephemeral (emptyDir)

No persistence. Definitions are re-downloaded from the ClamAV CDN on every pod restart. Suitable for testing or environments with unrestricted outbound internet access and tolerance for slow startups.

```yaml
persistence:
  definitions:
    enabled: false
```

---

## Security

### Pod Security Context

`fsGroup: 101` is set at the pod level so the `definitions` volume is writable by the `clamav` group (GID 101) without requiring root.

### Running as Non-Root

The official `clamav/clamav` image runs as root by default. Its entrypoint script (`/init`) performs root-only operations at startup (`chown`, `ln`). An alternative entrypoint `/init-unprivileged` is documented by ClamAV for non-root use.

To run non-root, override the command on `clamd` and `freshclam` containers and add a security context:

```yaml
# In a custom values override — not yet wired as a first-class value
command: ["/init-unprivileged"]
securityContext:
  runAsNonRoot: true
  runAsUser: 100
  runAsGroup: 101
  allowPrivilegeEscalation: false
```

The `freshclam-init` init container already overrides the entrypoint directly so only the security context needs adding.

> **Note:** `/init-unprivileged` is the documented workaround but the upstream PR to make non-root the default was reverted. The pod-level `fsGroup: 101` already handles volume permissions. Verify `CLAMAV_NO_FRESHCLAMD` / `CLAMAV_NO_CLAMD` env vars work correctly with the unprivileged entrypoint before using in production.

---

## Health Probes

ClamAV must load the full definition database (~300 MB) into memory before it can scan. The three probes work together to handle this safely.

### Startup Probe

```yaml
exec:
  command: [clamdscan, --no-summary, /etc/hostname]
failureThreshold: 30
periodSeconds: 10
```

Runs `clamdscan` against `/etc/hostname` (small, always present, always clean) every 10 seconds for up to 5 minutes. Confirms clamd is **functionally able to scan**, not just listening on the port. Readiness and liveness probes do not start until this passes.

### Readiness Probe

```yaml
tcpSocket:
  port: 3310
periodSeconds: 10
```

Lightweight TCP check every 10 seconds. If it fails, the pod is removed from the ClusterIP service and stops receiving scan requests.

### Liveness Probe

```yaml
tcpSocket:
  port: 3310
periodSeconds: 30
failureThreshold: 3
```

If clamd stops responding for 90 seconds (3 × 30s), Kubernetes restarts the container.

---

## ClamAV Configuration Reference

Settings marked **✓** are set in the default `values.yaml`. All others are available by editing `config.clamd` or `config.freshclam` in your values override.

### clamd.conf Settings

#### Logging

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `LogFile` | disabled | | Write logs to a file |
| `LogFileMaxSize` | 1M | | Max log file size before rotation. `0` disables |
| `LogTime` | no | ✓ | Prefix each log line with a timestamp |
| `LogClean` | no | ✓ | Log clean (non-infected) files too |
| `LogVerbose` | no | ✓ | Enable verbose logging (set to `no`) |
| `LogSyslog` | no | | Send logs to syslog |
| `LogFacility` | LOG_LOCAL6 | | Syslog facility |
| `LogRotate` | no | | Rotate logs (auto-enabled with `LogFileMaxSize`) |
| `ExtendedDetectionInfo` | no | | Include file size and hash in detection output |

#### Process & System

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `PidFile` | disabled | | Write daemon PID to file |
| `TemporaryDirectory` | /tmp | | Override temp directory for scan files |
| `Foreground` | no | ✓ | Don't fork to background — required in containers |
| `User` | — | | Drop privileges to this user after startup |
| `ExitOnOOM` | no | | Terminate clamd on out-of-memory condition |
| `Debug` | no | | Enable debug messages from libclamav |
| `LeaveTemporaryFiles` | no | | Keep temp files after scanning (debug only) |
| `GenerateMetadataJson` | no | | Write scan metadata JSON (requires `LeaveTemporaryFiles`) |

#### Database

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `DatabaseDirectory` | hardcoded | ✓ | Path to definitions. Set to `/var/lib/clamav` |
| `OfficialDatabaseOnly` | no | | Reject third-party signatures |
| `FailIfCvdOlderThan` | -1 | | Exit if database is older than N days. `-1` disables |
| `SelfCheck` | 600 | ✓ | Seconds between on-disk definition checks. Set to `3600` |
| `ConcurrentDatabaseReload` | yes | ✓ | Reload definitions without blocking scans. Uses ~2× RAM briefly |

#### Network & Sockets

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `TCPSocket` | disabled | ✓ | TCP port to listen on. Set to `3310` |
| `TCPAddr` | INADDR_ANY | ✓ | IP to bind to. Set to `0.0.0.0` |
| `LocalSocket` | disabled | ✓ | Unix socket path. Set to `/run/clamav/clamd.sock` |
| `LocalSocketGroup` | primary group | | Group ownership on the Unix socket |
| `LocalSocketMode` | world accessible | | Permissions on the Unix socket (e.g. `660`) |
| `FixStaleSocket` | yes | | Remove stale socket from unclean shutdown |
| `StreamMaxLength` | 100M | | Max data size for stream-based scans |
| `StreamMinPort` | 1024 | | Lower bound of stream port range |
| `StreamMaxPort` | 2048 | | Upper bound of stream port range |

#### Connection & Threading

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `MaxConnectionQueueLength` | 200 | ✓ | Max pending connections |
| `MaxThreads` | 10 | ✓ | Max concurrent scan threads |
| `ReadTimeout` | 120 | ✓ | Seconds before dropping an idle connection. Set to `180` |
| `CommandReadTimeout` | 30 | | Seconds to wait for initial command after connect |
| `SendBufTimeout` | 500 | | Milliseconds to wait when send buffer is full |
| `MaxQueue` | 100 | | Max items queued for scanning |
| `IdleTimeout` | 30 | | Seconds before an idle thread exits |

#### Scanning Behaviour

| Setting | Default | Description |
|---------|---------|-------------|
| `ExcludePath` | scan all | Regex pattern for paths to skip (repeatable) |
| `MaxDirectoryRecursion` | 15 | Max depth to recurse into directories |
| `FollowDirectorySymlinks` | no | Follow symlinks to directories |
| `FollowFileSymlinks` | no | Follow symlinks to files |
| `CrossFilesystems` | yes | Scan files on other mounted filesystems |
| `VirusEvent` | disabled | Shell command to run on detection |
| `AllowAllMatchScan` | yes | Allow `ALLMATCHSCAN` command (continue after first hit) |
| `ForceToDisk` | no | Write in-memory scan content to disk |
| `DisableCache` | no | Disable the MD5 scan cache |
| `CacheSize` | 65536 | Scan cache entries (must be a square number) |
| `HeuristicAlerts` | yes | Alert on heuristically suspicious patterns |
| `HeuristicScanPrecedence` | no | Stop on first heuristic match (saves CPU) |
| `DetectPUA` | no | Detect Potentially Unwanted Applications |

#### File Types

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `ScanPE` | yes | | Deep analysis of Windows PE executables |
| `ScanELF` | yes | ✓ | Scan Linux ELF executables |
| `ScanOLE2` | yes | | Scan OLE2 containers (Word, Excel, `.msi`) |
| `ScanPDF` | yes | ✓ | Scan within PDF files |
| `ScanSWF` | yes | | Scan Flash `.swf` files |
| `ScanXMLDOCS` | yes | ✓ | Scan XML-based document formats |
| `ScanHWP3` | yes | | Scan Hangul Word Processor files |
| `ScanOneNote` | yes | | Scan Microsoft OneNote files |
| `ScanImage` | yes | | Scan image/graphics files |
| `ScanHTML` | yes | | Normalise and scan HTML content |
| `ScanArchive` | yes | ✓ | Scan inside archives (zip, tar, rar, etc.) |
| `ScanMail` | yes | ✓ | Parse and scan email messages and attachments |
| `ScanPartialMessages` | no | | Scan RFC1341 messages split across emails (DoS risk on busy servers) |
| `PhishingSignatures` | yes | | Detect phishing via HTML/Email NDB signatures |
| `PhishingScanURLs` | yes | | Detect phishing by analysing URLs in emails |

#### Heuristic Alerts

| Setting | Default | Description |
|---------|---------|-------------|
| `AlertBrokenExecutables` | no | Alert on malformed PE or ELF files |
| `AlertBrokenMedia` | no | Alert on malformed JPEG, TIFF, PNG, or GIF files |
| `AlertEncrypted` | no | Alert on encrypted archives and documents |
| `AlertEncryptedArchive` | no | Alert on encrypted archives only |
| `AlertEncryptedDoc` | no | Alert on encrypted PDFs only |
| `AlertOLE2Macros` | no | Flag OLE2 files containing VBA macros |
| `AlertPhishingSSLMismatch` | no | Alert on SSL mismatches in URLs |
| `AlertPhishingCloak` | no | Alert on cloaked URLs |
| `AlertExceedsMax` | no | Flag files exceeding size/recursion limits with `Heuristics.Limits.Exceeded` |

#### Data Loss Prevention (DLP)

| Setting | Default | Description |
|---------|---------|-------------|
| `StructuredDataDetection` | no | Enable DLP scanning for credit card numbers and SSNs |
| `StructuredMinCreditCardCount` | 3 | Minimum credit card numbers to trigger an alert |
| `StructuredMinSSNCount` | 3 | Minimum SSNs to trigger an alert |
| `StructuredSSNFormatNormal` | yes | Match SSNs in `xxx-yy-zzzz` format |
| `StructuredSSNFormatStripped` | no | Match SSNs in `xxxyyzzzz` format |

#### Limits

Protects against archive bombs and DoS. Set to `0` to disable (not recommended).

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `MaxScanSize` | 400M | ✓ | Max total data scanned from a container. Set to `900M` |
| `MaxFileSize` | 100M | ✓ | Max individual file size to scan. Set to `500M` |
| `MaxScanTime` | 120000ms | | Max time a scan may take |
| `MaxRecursion` | 17 | | Max depth for nested archive extraction |
| `MaxFiles` | 10000 | | Max files scanned within a single container |
| `MaxEmbeddedPE` | 40M | | Max file size to check for embedded PE executables |
| `MaxHTMLNormalize` | 40M | | Max HTML file size to normalise |
| `MaxHTMLNoTags` | 8M | | Max size of normalised HTML to scan |
| `MaxScriptNormalize` | 20M | | Max script size to normalise |
| `MaxZipTypeRcg` | 1M | | Max ZIP size to re-analyse for type recognition |
| `MaxPartitions` | 50 | | Max partitions to scan in a raw disk image |
| `MaxIconsPE` | 100 | | Max icons to scan in a PE file |
| `PCREMatchLimit` | 100000 | | Max PCRE match function calls per regex |
| `PCRERecMatchLimit` | 2000 | | Max recursive PCRE match calls per regex |
| `PCREMaxFileSize` | 100M | | Max file size for PCRE signature evaluation |

#### Bytecode

| Setting | Default | Description |
|---------|---------|-------------|
| `Bytecode` | yes | Load bytecode signatures. Strongly recommended — disabling misses many detections |
| `BytecodeSecurity` | TrustSigned | `TrustSigned` (recommended), `Paranoid` (all sandboxed), `None` (debug only) |
| `BytecodeUnsigned` | no | Allow unsigned bytecode sources — **never enable**, arbitrary code execution risk |
| `BytecodeTimeout` | 10000ms | Max execution time for a bytecode signature |

---

### freshclam.conf Settings

#### Logging

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `UpdateLogFile` | disabled | | Write update logs to a file |
| `LogFileMaxSize` | 1M | | Max log file size. `0` disables |
| `LogTime` | no | ✓ | Prefix each log line with a timestamp |
| `LogVerbose` | no | | Enable verbose logging |
| `LogSyslog` | no | | Send logs to syslog |
| `LogFacility` | LOG_LOCAL6 | | Syslog facility |
| `LogRotate` | no | | Rotate logs |

#### Process & System

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `PidFile` | disabled | | Write freshclam PID to file |
| `DatabaseOwner` | clamav | | User that owns database files |
| `Foreground` | no | ✓ | Don't fork to background — required in containers |
| `Debug` | no | | Enable debug messages from libclamav |

#### Database & Mirrors

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `DatabaseDirectory` | hardcoded | ✓ | Where to write definitions. Set to `/var/lib/clamav` |
| `DNSDatabaseInfo` | current.cvd.clamav.net | | DNS domain for database version checks |
| `DatabaseMirror` | — | ✓ | Mirror to download from. Set to `database.clamav.net` |
| `PrivateMirror` | disabled | | Private mirror URL — overrides `DatabaseMirror` and `DNSDatabaseInfo` (repeatable) |
| `DatabaseCustomURL` | disabled | | Additional signature sources (`http://`, `https://`, `ftp://`, `file://`) (repeatable) |
| `ExtraDatabase` | — | | Opt in to an additional signature database by name |
| `ExcludeDatabase` | — | | Opt out of a standard signature database by name |
| `ScriptedUpdates` | yes | | Download incremental updates rather than full databases |
| `CompressLocalDatabase` | no | | Store `.cld` files compressed (saves disk, slightly slower loads) |
| `Bytecode` | yes | | Download `bytecode.cvd` alongside definitions |

#### Update Frequency & Connection

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `Checks` | 12 | ✓ | Update checks per day. Set to `24` (~hourly) |
| `MaxAttempts` | 3 | | Download attempts per mirror before giving up |
| `ConnectTimeout` | 30 | | Seconds to wait when connecting to the server |
| `ReceiveTimeout` | 60 | | Seconds to wait when receiving data. `0` disables |

#### Proxy

| Setting | Default | Description |
|---------|---------|-------------|
| `HTTPProxyServer` | disabled | Proxy server URL (`http://`, `https://`, `socks4://`, `socks5://`) |
| `HTTPProxyPort` | — | Proxy port |
| `HTTPProxyUsername` | — | Proxy authentication username |
| `HTTPProxyPassword` | — | Proxy authentication password |
| `HTTPUserAgent` | clamav/version | Override User-Agent (only works with private mirrors) |
| `LocalIPAddress` | OS default | Source IP for outbound connections (useful on multi-homed hosts) |

#### Notifications & Events

| Setting | Default | Used | Description |
|---------|---------|------|-------------|
| `NotifyClamd` | disabled | ✓ | Path to `clamd.conf` — sends `RELOAD` to clamd via Unix socket after update |
| `TestDatabases` | yes | ✓ | Validate downloaded definitions before replacing the live database |
| `OnUpdateExecute` | disabled | | Command to run after a successful update |
| `OnErrorExecute` | disabled | | Command to run when an update fails |
| `OnOutdatedExecute` | disabled | | Command to run when freshclam detects the installed ClamAV is outdated (`%v` = new version) |
