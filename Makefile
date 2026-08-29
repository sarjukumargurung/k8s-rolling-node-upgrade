SHELL := /usr/bin/env bash

.PHONY: preflight dry-run upgrade pdbs

preflight:
    bash scripts/preflight.sh

dry-run:
    bash scripts/rolling-upgrade.sh --dry-run

upgrade:
    bash scripts/rolling-upgrade.sh --yes

pdbs:
    kubectl apply -f manifests/pdb/
