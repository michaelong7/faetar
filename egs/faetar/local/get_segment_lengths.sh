#!/usr/bin/env bash

. ./path.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 diarized_w_text_dir"
  exit 1
fi

set -eo pipefail

if [ ! -d "$1" ]; then
  echo "$0: '$1' is not a directory"
  exit 1
fi

function get_segments () {
    file="$1"
    awk '{printf "%s\t", $2 - $1}' "$file"
}

dir="$1"
out="$dir/total_segment_lengths"

export -f get_segments

echo -n "" > "$out"

find "$dir" -name "*_text_utt" |
    sort |
    tr '\n' '\0' |
    xargs -I{} -0 bash -c 'get_segments "$1" | tee "'$dir'/$(basename "$1" _text_utt)_segment_lengths" >> "'$out'"; echo "" >> "'$out'"' -- {}