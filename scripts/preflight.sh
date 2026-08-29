#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
load_config
LOG_FILE="${LOG_DIR}/preflight.log"

require_cmd kubectl
require_cmd ssh
require_cmd python3

log "Preflight for target kubelet/kubeadm ${TARGET_VERSION}"

kubectl cluster-info >/dev/null || die "kubectl cannot reach the cluster"

CP_VER="$(normalize_ver "$(control_plane_version)")"
TGT_VER="$(normalize_ver "${TARGET_VERSION}")"
log "API server version: ${CP_VER}"

# kubelet must not be newer than the control plane (skew policy)
if [[ "$(printf '%s\n%s\n' "${CP_VER}" "${TGT_VER}" | sort -V | tail -n1)" != "${CP_VER}" \
     && "${CP_VER}" != "${TGT_VER}" ]]; then
  die "Target ${TGT_VER} is newer than control plane ${CP_VER}. Upgrade control plane first."
fi

log "PodDisruptionBudgets:"
kubectl get pdb -A || true

BLOCKING="$(kubectl get pdb -A -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
bad=[]
for i in d.get("items",[]):
    st=i.get("status",{})
    # allowedDisruptions == 0 and desiredHealthy > 0 can stall drains
    allowed=st.get("disruptionsAllowed")
    desired=st.get("desiredHealthy") or 0
    ns=i["metadata"]["namespace"]
    name=i["metadata"]["name"]
    if allowed == 0 and desired > 0:
        bad.append(f"{ns}/{name} allowed=0 desired={desired}")
if bad:
    print("\n".join(bad))
')"
if [[ -n "${BLOCKING}" ]]; then
  log "WARNING: PDBs currently allow 0 disruptions:"
  log "${BLOCKING}"
  log "Drains that hit these PDBs will wait until timeout."
fi

WORKERS=0
for NODE in $(list_worker_nodes); do
  is_excluded "${NODE}" && continue
  WORKERS=$((WORKERS + 1))
  READY="$(kubectl get node "${NODE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  VER="$(kubelet_version "${NODE}")"
  log "worker ${NODE} ready=${READY} kubelet=${VER}"
  [[ "${READY}" == "True" ]] || log "WARNING: ${NODE} is not Ready"
done

[[ "${WORKERS}" -ge 1 ]] || die "No worker nodes matched selector ${NODE_LABEL_SELECTOR}"
[[ "$(ready_schedulable_workers)" -gt "${MIN_READY_WORKERS}" ]] \
  || die "Need more than ${MIN_READY_WORKERS} Ready workers so one node can be drained"

log "Allocated resources (capacity sanity):"
kubectl describe nodes | grep -A 6 "Allocated resources" || true

log "Preflight complete."
