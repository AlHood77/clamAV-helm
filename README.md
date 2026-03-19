# clamAV-helm

Helm charts for deploying [ClamAV](https://www.clamav.net/) on Kubernetes.

## Charts

| Chart | Description |
|-------|-------------|
| [charts/clamav](charts/clamav) | ClamAV daemon (clamd) with freshclam sidecar for live definition updates |

## Quick Start

```bash
helm install clamav ./charts/clamav
```

See [charts/clamav/README.md](charts/clamav/README.md) for full documentation, all configurable values, and the complete clamd.conf / freshclam.conf settings reference.
