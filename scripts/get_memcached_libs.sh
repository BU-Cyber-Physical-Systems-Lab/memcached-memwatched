#!/usr/bin/env bash

#$1: executable from which libs must be copied
#$2: destination folder where lib*.so are copied

set -euo pipefail
declare -a libs

mapfile -t libs < <(readelf -d "$1" | awk -F '[][]' '/.so/ { print $2 }')
for lib in "${libs[@]}"; do
    echo $lib
done
