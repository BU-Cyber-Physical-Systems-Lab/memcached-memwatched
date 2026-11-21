#shellcheck disable=SC2029
# $1: name of experiment
# $2: subfolder of the experiment (optional)
# $3: board name for the experiment (optional)
# $4: ssh target platform (i.e. root@10.210.1.187)
set -euo pipefail

script_dir="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd -P
)"

ssh_target=$4
server_ip=${ssh_target##*@}
experiment=$1
nfs_data_dir=/data/$2/$experiment
nfs_exec_dir=/Locusta/rtbench/
dir=/nfsroot/fciraolo/data/$3/$2/$experiment
source_location=${experiment%%2*}
rest=${experiment#*2}
destination=${rest%%-*}
rest=${rest#*-}
engine=${rest%%-*}
mode=${rest#*-}
job_time="4"
jobs=5
args=("-t $jobs -l2 -o $nfs_data_dir/canny.csv -b '$nfs_exec_dir/canny/fullhd.bmp /tmp/output'")
echo "src:$source_location dst:$destination engine:$engine mode:$mode"
case "$source_location" in
baseline_nomw)
    src_id=0
    ;;
baseline)
    args+=("-m 20M")
    src_id=0
    ;;
DRAM)
    args+=("-m 20M")
    src_id=0
    ;;
pDRAM)
    args+=("-m 20M -H 0x60000000")
    src_id=1
    ;;
BRAM)
    args+=("-m 20M -H 0xa0000000")
    src_id=2
    ;;
*)
    args+=("-m 20M")
    src_id=0
    ;;
esac
case "$destination" in
overheads)
    dst_id="0"
    ;;
DRAM)
    dst_id="0"
    ;;
pDRAM)
    dst_id="1"
    ;;
BRAM)
    dst_id="2"
    ;;
baseline* | warmup)
    dst_id="0"
    ;;
*)
    echo "$destination is not a valid destination"
    exit 1
    ;;
esac
case "$mode" in
baseline* | warmup)
    mode_id="0"
    ;;
overheads)
    mode_id="0"
    ;;
sync)
    mode_id="1"
    ;;
sync_light)
    mode_id="2"
    ;;
sync_no_copy)
    mode_id="3"
    ;;
async)
    mode_id="4"
    ;;
*)
    echo "$mode is not a valid mode"
    exit 1
    ;;
esac
case "$engine" in
baseline* | warmup)
    engine_id="0"
    dst_modes="0"
    ;;
overheads)
    engine_id="0"
    dst_modes="0"
    ;;
sw)
    engine_id="0"
    dst_modes="4" # sw has 4 modes
    ;;
locusta)
    engine_id="12"
    dst_modes="1" # locusta has only one mode per destination
    mode_id="0"
    ;;
*)
    echo "$engine is not a valid engine"
    exit 1
    ;;
esac
dst_signal_id=$(echo "$engine_id + ($dst_id * $dst_modes) + $mode_id" | bc)
src_signal_id=$(echo "$engine_id + ($src_id * $dst_modes) + $mode_id" | bc)
migration_period=$(echo "scale=3; $job_time / 2" | bc)
migration_delay="0.2"
echo "migration stats: delay: $migration_delay period:$migration_period"
mkdir -p "$dir"
ssh "$ssh_target" mkdir -p "$nfs_data_dir"
echo "Chosen migration signal dst:$dst_signal_id src:$src_signal_id"
echo "starting experiment"
#shellcheck disable=SC2068
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
    ssh "$ssh_target" "$nfs_exec_dir"/canny/canny ${args[@]} &
    rtbench_pid=$(ssh "$ssh_target" pidof "canny")
    echo "rtbench pid: $rtbench_pid"
else
    ssh "$ssh_target" "$nfs_exec_dir"/canny/canny ${args[@]}
fi
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
    echo "starting periodic migration executable"
    ssh "$ssh_target" "$nfs_exec_dir"/periodic_migration \
        -s "$dst_signal_id,$src_signal_id" -d "$migration_delay" \
        -t "$rtbench_pid" -p "$migration_period" -f "$nfs_data_dir/migration_timestamp.log"
fi
ssh "$ssh_target" sync
if [[ "$engine" == "warmup" ]]; then
    rm -r "$dir"
fi
