# Rolling Kubernetes node upgrades (drain / uncordon)

**Architecture / Rollout**

**Rolling Node Upgrade Pipeline**

<img width="1168" height="784" alt="image" src="https://github.com/user-attachments/assets/46ce6da1-b6e0-4854-b63b-48344088ad32" />

**Rolling Workder Upgrade Architecture**

<img width="1168" height="784" alt="image" src="https://github.com/user-attachments/assets/3f8c5a1f-2406-405e-a727-cd740464e305" />

**Layout**
```
k8s-rolling-node-upgrade/
├── README.md
├── Makefile
├── .gitignore
├── config/
│   └── upgrade.env.example
├── lib/
│   └── common.sh
├── manifests/
│   └── pdb/
│       ├── frontend-pdb.yaml
│       ├── api-pdb.yaml
│       └── database-pdb.yaml
├── scripts/
│   ├── preflight.sh
│   ├── drain-node.sh
│   ├── upgrade-node-remote.sh
│   ├── healthcheck.sh
│   └── rolling-upgrade.sh
└── examples/
    └── run-local.sh
```

**Automation around the kubeadm worker flow:**

1. preflight (skew, capacity, PDBs)
2. cordon + drain (no --force)
3. SSH upgrade of kubeadm → `kubeadm upgrade node` → kubelet/kubectl
4. wait Ready + kubelet version gate
5. uncordon + soak
6. next worker

Control plane must already be on the target minor (or newer). This tool only rolls workers.

## Usage

```bash
cp config/upgrade.env.example config/upgrade.env
# edit TARGET_VERSION, SSH_USER, PACKAGE_FAMILY

make preflight
make dry-run
make upgrade

Single Node:

bash scripts/drain-node.sh worker-01
bash scripts/upgrade-node-remote.sh worker-01
bash scripts/healthcheck.sh worker-01
kubectl uncordon worker-01
```

**Failure policy**

If drain, remote upgrade, or health check fails, the node stays cordoned.

That is intentional: do not put a half-upgraded kubelet back into rotation.

Fix the node, then rerun — already-correct versions are skipped.


**StatefulSets**

Scale to >1 replica, confirm the PVC can attach on another node, drain followers first,
and use a longer DRAIN_TIMEOUT / GRACE_PERIOD.

```bash
---

## How to run

git init k8s-rolling-node-upgrade && cd k8s-rolling-node-upgrade
# drop the files above in place
chmod +x scripts/*.sh examples/run-local.sh
cp config/upgrade.env.example config/upgrade.env

# PDBs before any drain
kubectl apply -f manifests/pdb/

# inspect, then execute
make preflight
make dry-run
make upgrade
# or: bash scripts/rolling-upgrade.sh --target 1.36.1 --yes
```


