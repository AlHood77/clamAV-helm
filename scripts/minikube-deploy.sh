#!/usr/bin/env bash
set -euo pipefail

RELEASE="clamav"
NAMESPACE="clamav-system"
CHART="./charts/clamav"

# ── Prerequisites ────────────────────────────────────────────────────────────

for cmd in minikube helm kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' not found — please install it before running this script."
    exit 1
  fi
done

# ── Minikube ─────────────────────────────────────────────────────────────────

# ClamAV only publishes linux/amd64 images. On Apple Silicon (arm64) minikube
# must use the docker driver so Docker Desktop handles AMD64 emulation via Rosetta 2.
MINIKUBE_ARGS=""
if [[ "$(uname -m)" == "arm64" ]]; then
  echo "► Apple Silicon detected — using docker driver for AMD64 emulation"
  MINIKUBE_ARGS="--driver=docker"
fi

if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "► Starting minikube..."
  # shellcheck disable=SC2086
  minikube start $MINIKUBE_ARGS
else
  echo "✓ Minikube already running"
fi

# ── Deploy ───────────────────────────────────────────────────────────────────

echo "► Deploying ClamAV (Deployment, 1 replica, emptyDir storage)..."

helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$CHART/values-minikube.yaml" \
  --set workload.type=deployment \
  --set replicaCount=1 \
  --set persistence.definitions.type=emptyDir \
  --wait --timeout 10m

# ── Status ───────────────────────────────────────────────────────────────────

echo ""
echo "✓ ClamAV deployed"
echo ""
kubectl get pods -n "$NAMESPACE"
echo ""
echo "To watch startup logs (definitions download takes a few minutes):"
echo "  kubectl logs -n $NAMESPACE deploy/$RELEASE -c freshclam-init -f"
echo ""
echo "To test a scan once the pod is ready:"
echo "  kubectl exec -n $NAMESPACE deploy/$RELEASE -c clamd -- clamdscan --no-summary /etc/hostname"
echo ""
echo "To port-forward clamd locally:"
echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE 3310:3310"
