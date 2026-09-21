#!/usr/bin/env bash
#shellcheck disable=SC2029
# $1: name of experiment
# $2: subfolder of the experiment (optional)
# $3: board name for the experiment (optional)
# $4: ssh target platform (i.e. root@10.210.1.187)
set -euo pipefail

declare script_dir
declare dir
declare server_ip
declare mutilate_runtime
declare mutilate_warmup_time
declare mutilate_init_time
declare memcached_args
declare mutilate_args
declare source_location
declare destination
declare rest
declare engine
declare mode
declare -i dst_id
declare -i src_id
declare -i dst_modes
declare -i mode_id
declare -i engine_id
declare -i src_signal_id
declare -i dst_signal_id
declare migration_delay
declare migration_period
declare experiment
declare ramdisk_path
declare dir
declare server_ip
declare -i mutilate_runtime
declare -i mutilate_warmup_time
declare -i mutilate_init_time
declare memcached_args
declare source_location
declare destination
declare rest
declare engine
declare nfs_data_dir
declare nfs_exec_dir
declare mode
declare -i dst_id
declare -i dst_modes
declare -i mode_id
declare -i engine_id
declare -i migration_delay
declare -ia mutilate_agents_pids
declare mutilate_agents_ip
declare -i mutilate_agents_start_port
declare -i mutilate_num_agents
declare ssh_target

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"

ssh_target=$4
server_ip=${ssh_target##*@}
mutilate_agents_pids=()
mutilate_num_agents=0
if [[ $mutilate_num_agents -gt 0 ]]; then
    mutilate_master_threads=16
    mutilate_agent_threads=$( echo "($(nproc) - $mutilate_master_threads) / $mutilate_num_agents" | bc)
    mutilate_args="-B -R -D 4 -C 4"
else
    mutilate_master_threads=$(nproc)
    mutilate_agent_threads=0
    mutilate_args=""
fi
mutilate_agents_start_port=5556
mutilate_agents_ip="127.0.0.1"
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
mutilate_pwd="$script_dir/../test/mutilate/mutilate"
mutilate_output_file="$dir/$experiment.log"
mutilate_stats_file="$dir/${experiment}_stats.txt"

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
	baseline*|warmup)
		dst_id="0"
		;;
	*)
		echo "$destination is not a valid destination"
		exit 1
		;;
esac
case "$mode" in
	baseline*|warmup)
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
	baseline*|warmup)
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
migration_period=$(echo  "$mutilate_runtime/5" | bc)
migration_delay=$(echo "$mutilate_init_time + $mutilate_warmup_time + $migration_period+1" | bc)
if [[ "$engine" != "warmup" ]]; then
mkdir -p "$dir"
fi
echo "Chosen migration signal dst:$dst_signal_id src:$src_signal_id"
#shellcheck disable=SC2086
ssh "$ssh_target" "$nfs_exec_dir"/memcached -t 3 -u root $memcached_args &
memcached_job=$!
sleep 1
server_memcached_pid=$(ssh "$ssh_target" pidof memcached)
#ssh "$ssh_target" "$nfs_exec_dir"/busybox-armv8l taskset -p 0xe "$server_memcached_pid"
# start mutilate agents
if [[ $mutilate_num_agents -gt 0 ]]; then
echo "Starting agents"
for (( i=0 ; i < mutilate_num_agents ; i++ )); do
    $mutilate_pwd \
    -q 200000 -i fb_ia -K 30 -V 200 -r 10000 -u 0.0 \
    -T "$mutilate_agent_threads" -d 4 -c 4 -A -p "$(( mutilate_agents_start_port + i ))" &
    mutilate_agents_pids+=($!)
    mutilate_args="$mutilate_args -a $mutilate_agents_ip:$(( mutilate_agents_start_port + i ))"
done
echo "agents started, loading DB"
else
echo "loading DB"
fi
# load db
$mutilate_pwd --loadonly --server="$server_ip"
# start mutilate master, connect to agents and start issuing requests
echo "DB loaded, starting experiment"
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
    ssh "$ssh_target" "$nfs_exec_dir"/periodic_migration \
        -s "$dst_signal_id,$src_signal_id" -d "$migration_delay" \
        -t "$server_memcached_pid" -p "$migration_period" -f "$nfs_data_dir/migration_timestamp.log" &
    migration_job=$!
    #server_migration_pid=$(ssh "$ssh_target" pidof periodic_migration)
    #ssh "$ssh_target" "$nfs_exec_dir"/busybox-armv8l taskset -p 0x1 "$server_migration_pid"
fi
# NOTE: These arguments have to be fine-tuned depending on the server
mutilate_args="$mutilate_args --noload -w $mutilate_warmup_time --server=$server_ip -t $mutilate_runtime -T $mutilate_master_threads -d 4 -c 4 -q 200000 -i fb_ia  -K fb_key -V fb_value -r 10000 -u 0"
if [[ "$engine" == "warmup" ]]; then
#shellcheck disable=SC2086
$mutilate_pwd $mutilate_args > "/dev/null" &
else
ssh "$ssh_target" "$nfs_exec_dir"/dump_time "$nfs_data_dir/mutilate_start.log"
#shellcheck disable=SC2086
$mutilate_pwd --save="$mutilate_output_file" $mutilate_args > "$mutilate_stats_file" &
fi
mutilate_job=$!
wait -f $mutilate_job
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
    ssh "$ssh_target" killall -INT periodic_migration
    if [[ $mutilate_num_agents -gt 0 ]]; then
        killall mutilate
    fi
    wait -f "$migration_job"
fi
sleep 1
ssh "$ssh_target" kill -INT "$server_memcached_pid"
wait -f "$memcached_job"
ssh "$ssh_target" sync
ssh "$ssh_target" rm "$ramdisk_path"
