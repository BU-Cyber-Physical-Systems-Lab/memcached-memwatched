#!/bin/bash
pid=$(ps -a | grep ./memcached | awk 'NR==1{print $1}')
period=2
./periodic_migration -t $pid $1
echo $pid
sleep $2
kill $pid
