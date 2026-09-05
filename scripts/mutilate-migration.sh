#!/bin/bash
declare dir
declare server_ip
declare -i mutilate_runtime
declare -i mutilate_warmup_time
declare -i mutilate_init_time
declare migration_args
declare memcached_args
declare source_location
declare destination
declare rest
declare engine 
declare mode
declare -i dst_id
declare -i dst_modes
declare -i mode_id
declare -i engine_id
declare -i signal_id
declare -i migration_delay
declare -i kill_delay
dir=$1
server_ip=10.210.1.187
mutilate_runtime=5
mutilate_warmup_time=1
mutilate_init_time=3
source_location=${dir%%2*}
rest=${dir#*2}
destination=${rest%%-*}
rest=${rest#*-}
engine=${rest%%-*}
mode=${rest#*-}
echo "src:$source_location dst:$destination engine:$engine mode:$mode"
case "$source_location" in
	DRAM)
		memcached_args="-w 6M"
		;;
	pDRAM)
		memcached_args="-w 6M:0x60000000"
		;;
	BRAM)
		memcached_args="-w 6M:0xa0000000"
		;;
	*)
		memcached_args="-w 6M"
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
	baseline|warmup)
		dst_id="0"
		;;
	*)
		echo "$destination is not a valid destination"
		exit 1
		;;
esac
case "$mode" in
	baseline|warmup)
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
	baseline|warmup)
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
signal_id=$((engine_id + (dst_id * dst_modes) + mode_id))
migration_delay=$((mutilate_init_time + mutilate_warmup_time + (mutilate_runtime/2)))
kill_delay=$((1+(mutilate_runtime/2)))
migration_args="\"-s $signal_id -d $migration_delay\" $kill_delay"
mkdir -p $dir
#ssh root@$server_ip "cd memcached; ./start_memcached.sh $memcached_args"
set -x
ssh root@$server_ip "./memcached-docker -u root $memcached_args &"
sleep 1
../test/mutilate/mutilate -v --save=${dir}/${dir}.log -T 16 -w $mutilate_warmup_time --server=$server_ip -t $mutilate_runtime -K fixed:30 -V fixed:200 -i normal:0:1  > ${dir}/${dir}_stats.txt &
if [[ "$engine" != "baseline" ]] && [[ "$engine" != "warmup" ]]; then
    ssh root@$server_ip "cd memcached; ./trigger_migration.sh $migration_args"
    echo "$migration_delay" > "${dir}"/migration_timestamp.log
else
    sleep $((mutilate_runtime + mutilate_init_time + mutilate_warmup_time))
fi
mv mutilate_start.log $dir/
#if [[ "$engine" != "baseline" ]] && [[ "$engine" != "warmup" ]]; then
#    scp root@$server_ip:memcached/interrupts.log $dir/migration_interrupts.log
#fi
if [[ "$engine" == "warmup" ]]; then
    rm -r warmup
fi
