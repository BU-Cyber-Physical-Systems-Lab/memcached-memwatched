#!/usr/bin/env bash
set -euo pipefail
declare -a experiments

experiments=("baseline_nomw" "baseline" "overheads" "DRAM2DRAM-sw-sync" "DRAM2pDRAM-sw-sync" "pDRAM2DRAM-sw-sync" "pDRAM2pDRAM-sw-sync")

bash ./mutilate-migration.sh "warmup"
for experiment in "${experiments[@]}"; do
    sleep 1
    bash ./mutilate-migration.sh "$experiment"
    sleep 1
done
if [[ -f plots.py ]]; then
    python3 plots.py .
fi
