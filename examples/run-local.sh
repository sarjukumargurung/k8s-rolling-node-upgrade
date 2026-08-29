#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cp -n config/upgrade.env.example config/upgrade.env || true
make preflight
make dry-run
# make upgrade
