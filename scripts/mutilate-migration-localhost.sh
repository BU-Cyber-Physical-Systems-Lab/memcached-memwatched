#!/usr/bin/env bash
# $1: name of experiment
# $2: subfolder of the experiment (optional)
#
declare dir
declare server_ip
declare mutilate_runtime
declare mutilate_warmup_time
declare mutilate_init_time
declare memcached_args
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
declare src_signal_id
declare dst_signal_id
declare migration_delay
declare migration_period
declare -i migration_pid
declare -i memcached_pid
declare experiment
declare ramdisk_path
declare ramdisk_file
declare script_dir

script_dir="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"
ramdisk_path=/tmp/memcached_ramdisk
experiment=$1
dir="$script_dir"/data/$2/$experiment
server_ip=127.0.0.1
mutilate_runtime=5
mutilate_warmup_time=2
mutilate_init_time=0
source_location=${experiment%%2*}
rest=${experiment#*2}
destination=${rest%%-*}
rest=${rest#*-}
engine=${rest%%-*}
mode=${rest#*-}

touch "$ramdisk_path"
truncate -s 41M "$ramdisk_path"

echo "src:$source_location dst:$destination engine:$engine mode:$mode"
case "$source_location" in
    baseline_nomw)
		memcached_args=""
        src_id=0
		;;
    baseline)
		memcached_args="--memory-file=$ramdisk_file -m 40"
        src_id=0
		;;
	DRAM)
		memcached_args="--memory-file=$ramdisk_file -m 40"
        src_id=0
		;;
	pDRAM)
		memcached_args="--memory-file=$ramdisk_file:0x60000000 -m 40"
        src_id=1
		;;
	BRAM)
		memcached_args="--memory-file=$ramdisk_file:0xa0000000 -m 40"
        src_id=2
		;;
	*)
		memcached_args="--memory-file=$ramdisk_file -m 40"
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
migration_delay=$(echo "$mutilate_init_time + $mutilate_warmup_time + $migration_period" | bc)
mkdir -p "$dir"
echo "Chosen migration signal dst:$dst_signal_id src:$src_signal_id"
/usr/bin/time -v ./memcached -v -t 1 -u root -c 32768 $memcached_args &
memcached_pid=$(pidof memcached)
../busybox-armv8l taskset -p 0x8 $memcached_pid
sleep 1
#load mutilate DB
"$script_dir"/mutilate -v --loadonly --server=$server_ip
# start issuing requests using background agents
"$script_dir"/mutilate -v --server=$server_ip --noload \
    -B -T 16 \
    -c 4 \
    --save="${dir}/${experiment}.log" \
    -w $mutilate_warmup_time -t $mutilate_runtime > "${dir}/${experiment}_stats.txt" &
mutilate_pid=$!

if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
    "$script_dir"/periodic_migration -s "$dst_signal_id,$src_signal_id" -d "$migration_delay" -t $memcached_pid -p "$migration_period" &
    migration_pid=$(pidof periodic_migration)
    ../busybox-armv8l taskset -p 0x7 $migration_pid
    wait -f "$mutilate_pid"
    killall mutilate
    kill -INT "$migration_pid"
    wait -f "$migration_pid"
else
    wait -f $mutilate_pid
fi
sleep 1
kill -INT "$memcached_pid"
mv mutilate_start.log "$dir"
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
   mv interrupts.log "$dir"/migration_timestamp.log
fi
if [[ "$engine" == "warmup" ]]; then
    rm -r "$dir"
fi
rm -r "$ramdisk_path"
