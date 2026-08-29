#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
load_config
LOG_FILE="${LOG_DIR}/rolling-upgrade.log"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  --target VERSION     kubeadm/kubelet stream (default: ${TARGET_VERSION})
  --dry-run            print actions only
  --yes                skip confirmation
  --continue           keep going after a node failure
  --help

Config file: config/upgrade.env
EOF
}

YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_VERSION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) YES=true; shift ;;
    --continue) CONTINUE_ON_NODE_FAILURE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

require_cmd kubectl
bash "${SCRIPT_DIR}/preflight.sh"

mapfile -t ALL_NODES < <(list_worker_nodes)
PLAN=()
SKIP=()
for NODE in "${ALL_NODES[@]}"; do
  is_excluded "${NODE}" && { SKIP+=("${NODE} (excluded)"); continue; }
  CUR="$(normalize_ver "$(kubelet_version "${NODE}")")"
  TGT="$(normalize_ver "${TARGET_VERSION}")"
  if [[ "${CUR}" == "${TGT}" ]]; then
    SKIP+=("${NODE} (already ${CUR})")
    continue
  fi
  PLAN+=("${NODE}")
done

log "=== Rolling node upgrade to ${TARGET_VERSION} ==="
log "Will upgrade: ${PLAN[*]:-(none)}"
log "Will skip:    ${SKIP[*]:-(none)}"

if [[ ${#PLAN[@]} -eq 0 ]]; then
  log "Nothing to do."
  exit 0
fi

if [[ "${REQUIRE_CONFIRMATION}" == "true" && "${YES}" != "true" && "${DRY_RUN}" != "true" ]]; then
  read -r -p "Proceed with ${#PLAN[@]} node(s)? [y/N] " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]] || die "aborted"
fi

FAILED=0
for NODE in "${PLAN[@]}"; do
  log "==============================================="
  log "Upgrading ${NODE}"
  log "==============================================="

  if ! bash "${SCRIPT_DIR}/drain-node.sh" "${NODE}"; then
    err "Drain failed for ${NODE}. Node is likely cordoned. Fix PDBs/stuck pods, then rerun."
    FAILED=$((FAILED + 1))
    [[ "${CONTINUE_ON_NODE_FAILURE}" == "true" ]] || die "Stopping after drain failure on ${NODE}"
    continue
  fi

  if ! bash "${SCRIPT_DIR}/upgrade-node-remote.sh" "${NODE}"; then
    err "Remote upgrade failed for ${NODE}. Leaving it CORDONED."
    FAILED=$((FAILED + 1))
    [[ "${CONTINUE_ON_NODE_FAILURE}" == "true" ]] || die "Stopping after upgrade failure on ${NODE}"
    continue
  fi

  if ! bash "${SCRIPT_DIR}/healthcheck.sh" "${NODE}"; then
    err "Health check failed for ${NODE}. Leaving it CORDONED."
    FAILED=$((FAILED + 1))
    [[ "${CONTINUE_ON_NODE_FAILURE}" == "true" ]] || die "Stopping after health failure on ${NODE}"
    continue
  fi

  log "Uncordoning ${NODE}"
  run "kubectl uncordon '${NODE}'"

  if ! is_dry_run && [[ "${SOAK_SECONDS}" -gt 0 ]]; then
    log "Soak ${SOAK_SECONDS}s before next node"
    sleep "${SOAK_SECONDS}"
  fi
done

log "==============================================="
log "Finished. failures=${FAILED}"
kubectl get nodes -o wide
[[ "${FAILED}" -eq 0 ]]
