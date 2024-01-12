#!/usr/bin/env bash

. ./path.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 textgrid_dir"
  exit 1
fi

set -eo pipefail

if [ ! -d "$1" ]; then
  echo "$0: '$1' is not a directory"
  exit 1
fi

function flip_tier () {

    textgrid="$1"

    # line 7 of a TextGrid file contains the number of tiers as "size = x"
    # since each speaker has a phones, utts, and vad tier, we divide the number of tiers by 3
    speakers="$(("$(sed '7q;d' $textgrid | sed 's/[^0-9]*//g')" / 3))"
    # wipes the output files
    out="$out_dir/$(basename "$textgrid")"
    echo -n "" > "$out"_

    awk 'NR <= 8' "$textgrid" > "$out"_

    for i in $(seq 0 $(($speakers - 1))); do
        phone_tier=$(bc <<< "$i * 3 + 1")
        utt_tier=$(bc <<< "$i * 3 + 2")

        # prints the utt_tier first then the phone_tier (and excludes vad tier)
        sed -n '/[ ]*item \['"$utt_tier"'\]:/,/[ ]*item \['"$(($utt_tier + 1))"'\]:/p' "$textgrid" |
        sed '$d' >> "$out"_

        sed -n '/[ ]*item \['"$phone_tier"'\]:/,/[ ]*item \['"$(($phone_tier + 1))"'\]:/p' "$textgrid" |
        sed '$d' >> "$out"_

    done

    # corrects amount of tiers and tier number labels
    new_speakers="$(wc -l <<< $(grep -E "item \[.+\]:" "$out"_))"

    awk -v new_speakers="$new_speakers" \
    'BEGIN {
        tier_num = 1
    }

    NR == 7 {
        print "size = "new_speakers
        }

    NR != 7 {
        if ($0 ~ /item \[.\]:/) {
            print "    item ["tier_num"]:";
            tier_num++;
        }
        else {
            print $0
        }

        }
    ' "$out"_ > "$out"

    rm "$out"_


}

dir="$1"
out_dir="$(pwd -P)/flipped_grids"

mkdir -p $out_dir

export -f flip_tier
export out_dir

find "$dir" -name "he*.TextGrid" -print0 |
xargs -I{} -0 bash -c 'flip_tier "$1"' -- {}