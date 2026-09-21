#!/usr/bin/env bash
#$1: subfolder of each experiment
#$2: ssh target (i.e. "root@10.210.1.187" or "daniele")
set -euo pipefail
declare -a experiments
declare script_dir

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"

case "$2" in
    *10.210.1.187 | daniele)
        ssh_target="root@10.210.1.187"
        board_name="daniele"
        ;;
    *)
        echo "Invalid ssh target!"
        exit 1
        ;;
esac


experiments=("baseline_nomw" "baseline" "overheads" "DRAM2DRAM-sw-sync" "DRAM2pDRAM-sw-sync" "pDRAM2DRAM-sw-sync" "pDRAM2pDRAM-sw-sync")

bash "$script_dir/mutilate-migration.sh" "warmup" "$1" "$board_name" "$ssh_target"
for experiment in "${experiments[@]}"; do
    sleep 1
    bash "$script_dir/mutilate-migration.sh" "$experiment" "$1" "$board_name" "$ssh_target"
    sleep 1
done
if [[ -f $script_dir/plots.py ]]; then
    python3 "$script_dir/plots.py" "/nfsroot/fciraolo/data/$2/$1"
fi
