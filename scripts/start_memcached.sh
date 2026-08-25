#!/bin/bash
./lib/ld-linux-aarch64.so.1 --library-path "$PWD/lib" ./memcached -u root $@ &
echo PID: $!
