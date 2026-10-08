#!/bin/bash
/usr/bin/time -v /Locusta/memcached/lib/ld-linux-aarch64.so.1 --library-path "/Locusta/memcached/lib" /Locusta/memcached/memcached -u root $@
