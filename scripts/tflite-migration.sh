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
experiment=$1
nfs_data_dir=/data/$2/$experiment
nfs_exec_dir=/Locusta/tflite
dir=/nfsroot/fciraolo/data/$3/$2/$experiment
source_location=${experiment%%2*}
rest=${experiment#*2}
destination=${rest%%-*}
rest=${rest#*-}
engine=${rest%%-*}
mode=${rest#*-}
exec_time=8
jobs=5
args=("--graph=$nfs_exec_dir/mobilenet_quant_v1_224.tflite" "--num_runs=$jobs")
#args+=("--enable_op_profiling=true" "--op_profiling_output_mode=csv" "--op_profiling_output_file=$nfs_data_dir/op_profile.csv")
echo "src:$source_location dst:$destination engine:$engine mode:$mode"
case "$source_location" in
baseline_nomw)
	src_id=0
	;;
baseline)
	args+=("--fixed_arena_size=30")
	src_id=0
	;;
DRAM)
	args+=("--fixed_arena_size=30")
	src_id=0
	;;
pDRAM)
	args+=("--fixed_arena_size=30" "--fixed_arena_start=0x60000000")
	src_id=1
	;;
BRAM)
	args+=("--fixed_arena_size=30" "--fixed_arena_start=0xa0000000")
	src_id=2
	;;
*)
	args+=("--fixed_arena_size=30")
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
migration_delay=$(echo "scale=6; 1+($exec_time /$jobs)" | bc)
mkdir -p "$dir"
ssh "$ssh_target" mkdir -p "$nfs_data_dir"
echo "Chosen migration signal dst:$dst_signal_id src:$src_signal_id"
if [[ ! "$engine" =~ ^baseline ]] && [[ "$engine" != "warmup" ]]; then
	for ((migrations_per_job = 1; migrations_per_job <= 10; migrations_per_job++)); do
		output_file="$nfs_data_dir/benchmark_model_migrations-${migrations_per_job}.log"
		host_output_file="$dir/benchmark_model_migrations-${migrations_per_job}.log"
		if [[ -r $host_output_file ]] && [[ $(wc -l <"$host_output_file") -ge "$jobs" ]]; then
			continue
		fi
		migration_period=$(echo "scale=6; $exec_time /$jobs / $migrations_per_job" | bc)
		echo "migation stats: period:${migration_period}s"
		echo "starting periodic migration"
		ssh "$ssh_target" "$nfs_exec_dir"/periodic_migration \
			-s "$dst_signal_id,$src_signal_id" \
			-w -p "$migration_period" -f "$nfs_data_dir/migration_timestamp_migrations-${migrations_per_job}.log" &
        echo "Periodic migration pid $(ssh "$ssh_target" pidof periodic_migration)"
        sleep 1
        #shellcheck disable=2068
		ssh "$ssh_target" "$nfs_exec_dir/benchmark_model ${args[*]} >$output_file"
        echo "ensuring periodic_migration is dead"
        set +e
        killall -q periodic_migration
        set -e
        sleep 1
	done
else
	if [[ ! -r $dir/benchmark_model.log ]] || [[ $(wc -l <"$dir/benchmark_model.log") -lt "$jobs" ]]; then
		#shellcheck disable=2068
		ssh "$ssh_target" "$nfs_exec_dir/benchmark_model ${args[*]} >$nfs_data_dir/benchmark_model.log"
	fi
fi
ssh "$ssh_target" sync
if [[ "$engine" == "warmup" ]]; then
	rm -r "$dir"
fi
