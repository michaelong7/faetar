#! /usr/bin/env bash

threshold=3
out_dir="filtered_grids"

. ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "Usage: $0 textgrids-dir italian-textfile"
  exit 1
fi

set -eo pipefail

dir="$1"
italian_text="$2"

function set_threshold() {

    input="$1"
    thresh="$2"
    out="$3"

    awk -v thresh="$thresh" \
    'NF <= thresh {
        print $0
    }

    NF > thresh {
        for (i = 1; i <= NF - (thresh - 1); i++) {
            for (j = 0; j <= (thresh - 1); j++) {
                if (j != (thresh - 1)) {
                    printf "%s ", $(i + j)
                }
                else {
                    printf "%s", $(i + j)
                }
            }
            print ""
        }
    }' "$input" > "$out"
}

# filters italian from textgrids
function filter_italian() {

    input="$1"
    out="$2"

    cp "$input" "$out"

    readarray -t v < "$phrase_list"

    # the utts tier is always the second tier after resegmentation
    utt_tier_start="$(grep -Fn '    item [2]:' "$file" | awk 'BEGIN {FS = ":"} {print $1}')"
    utt_tier_end="$(grep -Fn '    item [3]:' "$file" | awk 'BEGIN {FS = ":"} {print $1}')"

    for i in $(seq 0 $((${#v[@]} - 1))); do
        # replaces lines that contain italian phrases with null
        awk -v phrase="${v[i]}" -v start="$utt_tier_start" -v end="$(( $utt_tier_end - 1))" -e \
        'BEGIN {
            FS = " ";
        }

        start <= NR && NR <= end {
            if ($0 ~ phrase) {
                print "            text = \"\""
            }
            else {
                print $0
            }
        }
        
        NR < start || NR > end {
            print $0
        }' "$out" > "$out"_

        mv "$out"_ "$out"

    done

}

phrase_list="italian_docphrases"

set_threshold "$italian_text" "$threshold" "$phrase_list"
mkdir -p $out_dir

for file in "$dir"/*.TextGrid; do
    filter_italian "$file" ${out_dir}/$(basename "$file")
done

