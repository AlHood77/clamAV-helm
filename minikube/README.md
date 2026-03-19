# ClamAV — Minikube Local Dev

Quick-start for running ClamAV locally on minikube.

## Prerequisites

- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- [helm](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) — required on Apple Silicon for AMD64 image emulation

## Deploy

```bash
./minikube/deploy.sh
```

The script will:
1. Start minikube if not already running
2. Pull and cache the ClamAV image (Apple Silicon only — AMD64 emulation via Docker Desktop)
3. Install the Helm chart with dev-sized resources and ephemeral storage
4. Wait until clamd is ready (definitions download takes a few minutes)

## Test

```bash
./minikube/test.sh
```

Runs four checks:
| Test | What it verifies |
|---|---|
| Clean file scan | clamd scans and returns OK for a clean file |
| EICAR detection | clamd detects the standard AV test virus |
| TCP PING/PONG | clamd is reachable on port 3310 |
| Definition info | Prints the current signature database version |

## Teardown

```bash
helm uninstall clamav -n clamav-system
```

## Notes

- **Storage**: uses `emptyDir` — definitions are re-downloaded on every pod restart
- **Resources**: sized for a default 2GB minikube VM (see [values.yaml](values.yaml))
- **Apple Silicon**: ClamAV has no ARM64 image — the deploy script pre-loads the AMD64 image into minikube via Docker Desktop
- **TestDatabases**: disabled locally (see [values.yaml](values.yaml)) to avoid OOM on the constrained VM — re-enabled in production by default
