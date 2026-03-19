#!/usr/bin/env bash
set -euo pipefail

RELEASE="clamav"
NAMESPACE="clamav-system"

echo "Running ClamAV tests against deploy/$RELEASE in namespace $NAMESPACE"
echo ""

# ── 1. Clean file scan ────────────────────────────────────────────────────────

echo "▸ Test 1: Clean file scan (/etc/os-release)"
result=$(kubectl exec -n "$NAMESPACE" deploy/"$RELEASE" -c clamd -- \
  clamdscan --no-summary /etc/os-release 2>&1)
echo "  $result"
if echo "$result" | grep -q "OK"; then
  echo "  ✓ PASS"
else
  echo "  ✗ FAIL"
  exit 1
fi
echo ""

# ── 2. EICAR virus detection ──────────────────────────────────────────────────

echo "▸ Test 2: EICAR test virus detection"
result=$(kubectl exec -n "$NAMESPACE" deploy/"$RELEASE" -c clamd -- /bin/sh -c \
  'echo "X5O!P%@AP[4\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*" > /tmp/eicar.txt && clamdscan --no-summary /tmp/eicar.txt; true' 2>&1)
echo "  $result"
if echo "$result" | grep -q "FOUND"; then
  echo "  ✓ PASS"
else
  echo "  ✗ FAIL — virus not detected"
  exit 1
fi
echo ""

# ── 3. TCP socket (PING/PONG) ─────────────────────────────────────────────────

echo "▸ Test 3: TCP socket PING/PONG"
pong=$(kubectl exec -n "$NAMESPACE" deploy/"$RELEASE" -c clamd -- \
  /bin/sh -c 'echo "PING" | nc -q1 localhost 3310' 2>&1 || true)
echo "  $pong"
if echo "$pong" | grep -q "PONG"; then
  echo "  ✓ PASS"
else
  echo "  ✗ FAIL — no PONG response"
  exit 1
fi
echo ""

# ── 4. Definition version ─────────────────────────────────────────────────────

echo "▸ Test 4: Definition database info"
kubectl exec -n "$NAMESPACE" deploy/"$RELEASE" -c clamd -- \
  sigtool --info /var/lib/clamav/daily.cvd 2>/dev/null \
  | grep -E "^(Version|Signatures|Build time)" \
  | sed 's/^/  /'
echo "  ✓ PASS"
echo ""

echo "All tests passed."
