#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

log()  { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE:-${LOG_DIR}/upgrade.log}"; }
err()  { log "ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

load_config() {
  local cfg="${ROOT_DIR}/config/upgrade.env"
  if [[ -f "${cfg}" ]]; then
    # shellcheck disable=SC1090
    source "${cfg}"
  fi

  TARGET_VERSION="${TARGET_VERSION:-1.36.1}"
  NODE_LABEL_SELECTOR="${NODE_LABEL_SELECTOR:-!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master}"
  EXCLUDE_NODES="${EXCLUDE_NODES:-}"
  GRACE_PERIOD="${GRACE_PERIOD:-60}"
  DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-10m}"
  READY_TIMEOUT="${READY_TIMEOUT:-5m}"
  SOAK_SECONDS="${SOAK_SECONDS:-30}"
  MIN_READY_WORKERS="${MIN_READY_WORKERS:-1}"
  SSH_USER="${SSH_USER:-ubuntu}"
  SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=accept-new -o ConnectTimeout=10}"
  PACKAGE_FAMILY="${PACKAGE_FAMILY:-debian}"
  REQUIRE_CONFIRMATION="${REQUIRE_CONFIRMATION:-true}"
  CONTINUE_ON_NODE_FAILURE="${CONTINUE_ON_NODE_FAILURE:-false}"
  DRY_RUN="${DRY_RUN:-false}"
}

is_dry_run() { [[ "${DRY_RUN}" == "true" ]]; }

run() {
  if is_dry_run; then
    log "DRY-RUN: $*"
    return 0
  fi
  log "+ $*"
  eval "$@"
}

normalize_ver() {
  # v1.36.1 / 1.36.1+something -> 1.36.1
  echo "$1" | sed -E 's/^v//; s/\+.*//; s/-.*//'
}

kubelet_version() {
  kubectl get node "$1" -o jsonpath='{.status.nodeInfo.kubeletVersion}'
}

control_plane_version() {
  kubectl version -o json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("serverVersion",{}).get("gitVersion",""))' \
    || kubectl version --short 2>/dev/null | awk '/Server/{print $3}'
}

node_ready() {
  [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == "True" ]]
}

is_excluded() {
  local n="$1"
  for x in ${EXCLUDE_NODES}; do
    [[ "${n}" == "${x}" ]] && return 0
  done
  return 1
}

list_worker_nodes() {
  kubectl get nodes -l "${NODE_LABEL_SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

ready_schedulable_workers() {
  kubectl get nodes -l "${NODE_LABEL_SELECTOR}" \
    --no-headers \
    | awk '$2=="Ready" {print $1}' \
    | wc -l \
    | tr -d ' '
}
