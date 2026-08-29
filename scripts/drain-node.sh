#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
load_config

NODE="${1:-}"
[[ -n "${NODE}" ]] || die "usage: drain-node.sh <node>"

READY_NOW="$(ready_schedulable_workers)"
if [[ "${READY_NOW}" -le "${MIN_READY_WORKERS}" ]]; then
  die "Refusing to drain ${NODE}: only ${READY_NOW} Ready workers (min ${MIN_READY_WORKERS})"
fi

log "Cordoning ${NODE}"
run "kubectl cordon '${NODE}'"

log "Draining ${NODE} (grace=${GRACE_PERIOD}s timeout=${DRAIN_TIMEOUT})"
# Intentionally no --force and no --disable-eviction.
run "kubectl drain '${NODE}' \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=${GRACE_PERIOD} \
  --timeout=${DRAIN_TIMEOUT} \
  --disable-eviction=false"

log "Remaining pods on ${NODE} (DaemonSets expected):"
kubectl get pods -A --field-selector "spec.nodeName=${NODE}" -o wide || true
