#!/usr/bin/env bash
#shellcheck disable=SC2029
# $1: ssh target platform (i.e. root@10.210.1.187)
# $2: board name
set -euo pipefail

function on_exit() {
	echo "Killing bandwidth"
	set +e
	ssh "$ssh_target" killall bandwidth
	set -e
}

trap on_exit EXIT

function conditionally_execute() {
	#$1: lines
	#$2: output file
	#$3-@: cmdline
	if [[ ! -r "$2" ]] || [[ $(wc -l <"$2") -lt "$1" ]]; then
		shift
		shift
        #shellcheck disable=SC2068
		$@
	fi
}

interf_mode="write"
interf_size=8192
interf_threads=3
ssh_target=$1
experiment=protect
nfs_data_dir=/data/$experiment
nfs_exec_dir=/Locusta
dir=/nfsroot/fciraolo/data/$2/$experiment
jobs=5
mkdir -p "$dir"
ssh "$ssh_target" mkdir -p "$nfs_data_dir"
set -x
# start interference
echo "starting $interf_threads insteaces of bandwidth"
for ((i = 0; i < interf_threads; i++)); do
	ssh "$ssh_target" "$nfs_exec_dir"/rtbench/bandwidth -l1 -b \"-m "$interf_size" -a "$interf_mode" -i 5\" &
done
# rtbench experiments
echo "Start RT-Bench workload"
ssh "$ssh_target" mkdir -p "$nfs_data_dir"/rtbench
conditionally_execute $jobs "$dir"/rtbench/canny_baseline.csv ssh "$ssh_target" "$nfs_exec_dir/rtbench/canny/canny" -t $jobs -l2 -b \"$nfs_exec_dir/rtbench/canny/fullhd.bmp /tmp/output\" -o "$nfs_data_dir"/rtbench/canny_baseline.csv
conditionally_execute $jobs "$dir"/rtbench/canny_pDRAM.csv ssh "$ssh_target" "$nfs_exec_dir/rtbench/canny/canny" -t $jobs -l2 -b \"$nfs_exec_dir/rtbench/canny/fullhd.bmp /tmp/output\" -o "$nfs_data_dir"/rtbench/canny_pDRAM.csv -m 20M -H 0x60000000
#tflite experiments
echo "Starting TFLite workload"
ssh "$ssh_target" mkdir -p "$nfs_data_dir/tflite"
conditionally_execute $jobs "$dir"/tflite/mobilenet_baseline.log ssh "$ssh_target" "$nfs_exec_dir/tflite/benchmark_model --graph=$nfs_exec_dir/tflite/mobilenet_quant_v1_224.tflite --num_runs=$jobs --num_threads=$((4 - interf_threads)) > $nfs_data_dir/tflite/mobilenet_baseline.log"
conditionally_execute $jobs "$dir"/tflite/mobilenet_pDRAM.log ssh "$ssh_target" "$nfs_exec_dir/tflite/benchmark_model --graph=$nfs_exec_dir/tflite/mobilenet_quant_v1_224.tflite --num_runs=$jobs --num_threads=$((4 - interf_threads)) --fixed_arena_size=30 --fixed_arena_start=0x60000000 > $nfs_data_dir/tflite/mobilenet_pDRAM.log"
