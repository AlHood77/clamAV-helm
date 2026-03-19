#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RELEASE="clamav"
NAMESPACE="clamav-system"
CHART="$REPO_ROOT/charts/clamav"
VALUES="$SCRIPT_DIR/values.yaml"
IMAGE="clamav/clamav:1.4_base"

# ── Prerequisites ────────────────────────────────────────────────────────────

for cmd in minikube helm kubectl docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' not found — please install it before running this script."
    exit 1
  fi
done

# ── Minikube ─────────────────────────────────────────────────────────────────

if ! minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  echo "► Starting minikube..."
  minikube start
else
  echo "✓ Minikube already running"
fi

# ── Image ────────────────────────────────────────────────────────────────────

# ClamAV only publishes linux/amd64 images. On Apple Silicon the node is arm64
# so Kubernetes will fail to pull the image from the registry. Instead we pull
# it locally with an explicit platform flag and load it into minikube's cache.
# imagePullPolicy: IfNotPresent (the chart default) then uses the cached image.
if [[ "$(uname -m)" == "arm64" ]]; then
  echo "► Apple Silicon detected — pulling amd64 image and loading into minikube..."
  docker pull --platform linux/amd64 "$IMAGE"
  minikube image load "$IMAGE"
fi

# ── Deploy ───────────────────────────────────────────────────────────────────

echo "► Deploying ClamAV (Deployment, 1 replica, emptyDir storage)..."

helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES" \
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
echo "To run tests:"
echo "  ./minikube/test.sh"
echo ""
echo "To watch startup logs:"
echo "  kubectl logs -n $NAMESPACE deploy/$RELEASE -c freshclam-init -f"
echo ""
echo "To port-forward clamd locally:"
echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE 3310:3310"
