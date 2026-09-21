#!/usr/bin/env bash
#$1: subfolder of each experiment

set -euo pipefail
declare -a experiments
declare script_dir

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"

experiments=("baseline_nomw" "baseline" "overheads" "DRAM2DRAM-sw-sync" "DRAM2pDRAM-sw-sync" "pDRAM2DRAM-sw-sync" "pDRAM2pDRAM-sw-sync")

bash "$script_dir/mutilate-migration.sh" "warmup" "$1"
for experiment in "${experiments[@]}"; do
    sleep 1
    bash "$script_dir/mutilate-migration.sh" "$experiment" "$1"
    sleep 1
done
if [[ -f $script_dir/plots.py ]]; then
    python3 $script_dir/plots.py "$script_dir/../data/$1"
fi
