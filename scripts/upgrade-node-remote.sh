#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
load_config

NODE="${1:-}"
[[ -n "${NODE}" ]] || die "usage: upgrade-node-remote.sh <node>"

log "Remote package upgrade on ${NODE} -> ${TARGET_VERSION} (${PACKAGE_FAMILY})"

if is_dry_run; then
  log "DRY-RUN: would ssh ${SSH_USER}@${NODE} and upgrade kubeadm/kubelet/kubectl"
  return 0 2>/dev/null || exit 0
fi

# Remote script is passed on stdin so we do not require a copy on the node.
remote_debian() {
  ssh ${SSH_OPTS} "${SSH_USER}@${NODE}" "sudo bash -s" <<EOF
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
TARGET="${TARGET_VERSION}"
apt-mark unhold kubeadm || true
apt-get update -qq
apt-get install -y kubeadm="\${TARGET}-*"
apt-mark hold kubeadm
kubeadm upgrade node
apt-mark unhold kubelet kubectl || true
apt-get install -y kubelet="\${TARGET}-*" kubectl="\${TARGET}-*"
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
systemctl is-active --quiet kubelet
kubelet --version
EOF
}

remote_rhel() {
  ssh ${SSH_OPTS} "${SSH_USER}@${NODE}" "sudo bash -s" <<EOF
set -euo pipefail
TARGET="${TARGET_VERSION}"
yum install -y kubeadm-\${TARGET}-* || dnf install -y kubeadm-\${TARGET}-*
kubeadm upgrade node
yum install -y kubelet-\${TARGET}-* kubectl-\${TARGET}-* || dnf install -y kubelet-\${TARGET}-* kubectl-\${TARGET}-*
systemctl daemon-reload
systemctl restart kubelet
systemctl is-active --quiet kubelet
kubelet --version
EOF
}

case "${PACKAGE_FAMILY}" in
  debian) remote_debian ;;
  rhel)   remote_rhel ;;
  *)      die "Unknown PACKAGE_FAMILY=${PACKAGE_FAMILY}" ;;
esac
