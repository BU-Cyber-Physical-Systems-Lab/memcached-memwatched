#!/usr/bin/env bash
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
mutilate_agents_ip=("127.0.0.1" "10.210.1.170" "10.210.1.205" "10.210.1.162" "10.210.1.213")
mutilate_agent_users=("mattia" "root" "root" "mnico" "mnico")
mutilate_num_agents=${#mutilate_agents_ip[@]}
mutilate_agent_port=5556
if [[ $mutilate_num_agents -gt 0 ]]; then
    mutilate_master_threads=16
    mutilate_args="-B -R -D 64 -C 4"
else
    mutilate_master_threads=$(nproc)
    mutilate_args=""
fi
ramdisk_path=/tmp/memcached_ramdisk
experiment=$1
nfs_data_dir=/data/$2/$experiment
nfs_exec_dir=/Locusta/memcached
mem_file_size=64
dir=/nfsroot/fciraolo/data/$3/$2/$experiment
mutilate_runtime=5
mutilate_warmup_time=2
mutilate_init_time=0
source_location=${experiment%%2*}
rest=${experiment#*2}
destination=${rest%%-*}
rest=${rest#*-}
engine=${rest%%-*}
mode=${rest#*-}
mutilate_pwd="$script_dir/../test/mutilate-eric/mutilate"
mutilate_output_file="$dir/$experiment.log"
mutilate_stats_file="$dir/${experiment}_stats.txt"
mutilate_exec_params="-d 64 -c 4 -q 200000 -i fb_ia -K fb_key -V fb_value -u 0.2 -r 100000"

ssh "$ssh_target" "touch $ramdisk_path && truncate -s ${mem_file_size}M $ramdisk_path"

echo "src:$source_location dst:$destination engine:$engine mode:$mode"
memcached_args_common="-m $mem_file_size"
#memcached_buffer_args="-w ${mem_file_size}M"
memcached_buffer_args="--memory-file=$ramdisk_path"
case "$source_location" in
baseline_nomw)
    memcached_args="$memcached_args_common"
    src_id=0
    ;;
baseline)
    memcached_args="$memcached_args_common"
    src_id=0
    ;;
DRAM)
    memcached_args="$memcached_buffer_args $memcached_args_common"
    src_id=0
    ;;
pDRAM)
    memcached_args="$memcached_buffer_args:0x60000000 $memcached_args_common"
    src_id=1
    ;;
BRAM)
    memcached_args="$memcached_buffer_args:0xa0000000 $memcached_args_common"
    src_id=2
    ;;
*)
    memcached_args="$memcached_buffer_args $memcached_args_common"
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
migration_period=$(echo "$mutilate_runtime/5" | bc)
migration_delay=$(echo "$mutilate_init_time + $mutilate_warmup_time + $migration_period+1" | bc)
mkdir -p "$dir"
set -x
ssh "$ssh_target" mkdir -p "$nfs_data_dir"
echo "Chosen migration signal dst:$dst_signal_id src:$src_signal_id"
#shellcheck disable=SC2086
ssh "$ssh_target" /usr/bin/time -v "$nfs_exec_dir"/memcached -c 32768 -u root -t 3 $memcached_args 2>"$dir/memcached_util.log" &
#ssh "$ssh_target" "$nfs_exec_dir"/start_memcached.sh -t 2 -c 32768 $memcached_args 2> "$dir/memcached_util.log" &
set +x
sleep 1
#server_memcached_pid=$(ssh "$ssh_target" pidof "/Locusta/memcached/lib/ld-linux-aarch64.so.1")
server_memcached_pid=$(ssh "$ssh_target" pidof "memcached")
echo "memcached pid: $server_memcached_pid"
ssh "$ssh_target" "$nfs_exec_dir"/busybox-armv8l taskset -p 0xe "$server_memcached_pid"
# start mutilate agents
if [[ $mutilate_num_agents -gt 0 ]]; then
    echo "Starting agents"
    for ((i = 0; i < mutilate_num_agents; i++)); do
        set -x
        if ! ssh "${mutilate_agent_users[i]}@${mutilate_agents_ip[i]}" test -f ./mutilate ; then
        scp $mutilate_pwd "${mutilate_agent_users[i]}@${mutilate_agents_ip[i]}:"
        fi
        if ! ssh "${mutilate_agent_users[i]}@${mutilate_agents_ip[i]}" pgrep mutilate; then
        ssh "${mutilate_agent_users[i]}@${mutilate_agents_ip[i]}" ./mutilate  \
            -T '$(nproc)' -p $mutilate_agent_port -A &
        fi
        set +x
        mutilate_args="$mutilate_args -a ${mutilate_agents_ip[i]}"
    done
    echo "agents started, loading DB"
else
    echo "loading DB"
fi
# load db
set -x
$mutilate_pwd $mutilate_exec_params --loadonly --server="$server_ip"
set +x
# start mutilate master, connect to agents and start issuing requests
echo "DB loaded, starting experiment"
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
set -x
    ssh "$ssh_target" "$nfs_exec_dir"/periodic_migration \
        -s "$dst_signal_id,$src_signal_id" -d "$migration_delay" \
        -t "$server_memcached_pid" -p "$migration_period" -f "$nfs_data_dir/migration_timestamp.log" &
    server_migration_pid=$(ssh "$ssh_target" pidof "periodic_migration")
    ssh "$ssh_target" "$nfs_exec_dir"/busybox-armv8l taskset -p 0x1 "$server_migration_pid"
    migration_job=$!
set -x
fi
# NOTE: These arguments have to be fine-tuned depending on the server
mutilate_args="$mutilate_args --noload --server=$server_ip -p $mutilate_agent_port -T $mutilate_master_threads $mutilate_exec_params -w $mutilate_warmup_time  -t $mutilate_runtime"
if [[ "$engine" == "warmup" ]]; then
    set -x
    #shellcheck disable=SC2086
    $mutilate_pwd $mutilate_args >"/dev/null"
    set +x
else
    ssh "$ssh_target" "$nfs_exec_dir"/dump_time "$nfs_data_dir/mutilate_start.log"
    set -x
    #shellcheck disable=SC2086
    $mutilate_pwd --save="$mutilate_output_file" $mutilate_args >"$mutilate_stats_file"
    set +x
fi
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
    ssh "$ssh_target" killall -INT periodic_migration
    wait -f "$migration_job"
fi
if [[ $mutilate_num_agents -gt 0 ]]; then
    for ((i = 0; i < mutilate_num_agents; i++)); do
    ssh "${mutilate_agent_users[i]}@${mutilate_agents_ip[i]}" pkill mutilate
    ssh "${mutilate_agent_users[i]}@${mutilate_agents_ip[i]}" rm mutilate
    done
fi
sleep 1
ssh "$ssh_target" kill -INT "$server_memcached_pid"
ssh "$ssh_target" sync
ssh "$ssh_target" rm "$ramdisk_path"
if [[ "$engine" == "warmup" ]]; then
    rm -r "$dir"
fi
