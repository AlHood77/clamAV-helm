#!/usr/bin/env bash
set -euo pipefail

RELEASE="clamav"
NAMESPACE="clamav-system"
CHART="./charts/clamav"
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
