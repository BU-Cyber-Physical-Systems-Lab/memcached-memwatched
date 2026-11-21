#!/usr/bin/env bash
#$1: subfolder of each experiment
#$2: ssh target (i.e. "root@10.210.1.187" or "daniele")
#$3 board name
#$4 list of benchmarks to use
set -euo pipefail
declare -a experiments
declare script_dir

script_dir="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd -P
)"

case "$2" in
daniele)
    ssh_target="root@10.210.1.187"
    board_name="daniele"
    ;;
*)
    if (( $# < 4 )); then
        echo "missing board name for target $2"
        exit 1
    fi
    ssh_target="$2"
    board_name=$4
    ;;
esac

experiments=("baseline_nomw" "baseline" "overheads" "DRAM2DRAM-sw-sync" "DRAM2pDRAM-sw-sync" "pDRAM2DRAM-sw-sync" "pDRAM2pDRAM-sw-sync")

for benchmark in $3; do
    if [[ "$benchmark" == "mutilate" ]]; then
        bash "$script_dir/mutilate-migration-multihost.sh" "warmup" "$1/$benchmark" "$board_name" "$ssh_target"
        bmark_script="$benchmark-migration-multihost.sh"
    else
        bmark_script="$benchmark-migration.sh"
    fi
    for experiment in "${experiments[@]}"; do
        bash "$script_dir/$bmark_script" "$experiment" "$1/$benchmark" "$board_name" "$ssh_target"
    done
    #if [[ -f $script_dir/plots.py ]]; then
    #    python3 "$script_dir/plots.py" "/nfsroot/fciraolo/data/$2/$1"
    #fi

done
