#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
load_config

NODE="${1:-}"
[[ -n "${NODE}" ]] || die "usage: healthcheck.sh <node>"

log "Waiting for Ready on ${NODE} (${READY_TIMEOUT})"
if ! is_dry_run; then
  kubectl wait --for=condition=Ready "node/${NODE}" --timeout="${READY_TIMEOUT}"
fi

ACTUAL="$(normalize_ver "$(kubelet_version "${NODE}")")"
EXPECT="$(normalize_ver "${TARGET_VERSION}")"
log "${NODE} kubelet=${ACTUAL} expected=${EXPECT}"

if ! is_dry_run && [[ "${ACTUAL}" != "${EXPECT}" ]]; then
  die "${NODE} kubelet is ${ACTUAL}, not ${EXPECT}"
fi

# Fail if any non-DaemonSet pod is still stuck Terminating cluster-wide after this node.
STUCK="$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4=="Terminating"{print $1"/"$2}' | head -n 20 || true)"
if [[ -n "${STUCK}" ]]; then
  log "WARNING: pods still Terminating:"
  log "${STUCK}"
fi
