#!/usr/bin/env bash

out_dir="tws_from_grid_files"

. utils/parse_options.sh
. ./path.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 textgrids_dir speaker_mapping_file"
  exit 1
fi

set -eo pipefail

if [ ! -d "$1" ]; then
  echo "$0: '$1' is not a directory"
  exit 1
fi

if [ ! -f "$2" ]; then
  echo "$0: '$2' is not a file"
  exit 1
fi

dir="$1"
map_file="$2"

mkdir -p "$out_dir"

for file in "$dir"/*.TextGrid; do
    filename="$(basename "$file" .TextGrid)"
    out="$out_dir/${filename}_text_with_speaker"

    # leaves only speaker names, utterance start + end, and text
    awk '/name = / || /xmin = / || /xmax = / || /text = /' "$file" |
    awk 'NR >= 3' |
    awk '/name = / {print; n = NR + 2} NR > n' |
    # turns the file into [start] [end] [utt] format
    awk \
    'BEGIN {
        FS = "=";
        count = 0
    }

    !/name = / {
    # removes leading spaces
    sub(/^ +/, "", $NF);

        if (count != 2) {
            printf "%.2f\t", $NF;
            count++
        }
        else {
            print $NF;
            count = 0
        }
    }
    
    /name = / {
        sub(/^ +/, "", $NF);
        print "SPEAKER\t"$NF
    }' |
    # removes all blank utterances
    awk '$NF != "\"\""' |
    # adds speakers to each line
    awk \
    'BEGIN {
        FS = "\t";
        OFS = "\t";
        speaker = ""
    }

    /^SPEAKER/ {
        speaker = $NF;
        next
    }
    
    !/^SPEAKER/ {
        print $1, $2, speaker, $3;
    }' |
    # keeps only utt tiers
    awk 'BEGIN {FS = "\t"} $3 !~ /phones/' |
    # removes quotation marks and utts from speaker names
    awk \
    'BEGIN {
        FS = "\t";
        OFS = "\t"
    } 
    
    {
        sub(/^"/, "", $3);
        sub(/"$/, "", $3);
        sub(/utts$/, "", $3);
        sub(/ +$/, "", $3);
        $3 = tolower($3);
        sub(/ /, "_", $3);
        print $0
    }' |
    sort -k 1,1 -n > "$out"

    # converts speaker codes (anything labelled speaker_0, speaker_1, speaker_00, ...)
    awk -v filename=$filename \
    'BEGIN {
        FS = "\t";
        OFS = "\t";
    }
    
    NR == FNR {
        if ($1 == filename) {
            $2 = tolower($2);
            sub(/ /, "_", $2);
            speakers[$2] = $3
        }
        next;
    }
    
    NR != FNR {
        for (speaker in speakers) {
            if ($3 == speaker) {
                print $1, $2, speakers[$3], $4;
                next;
            }
        }
        print $0;
    }' "$map_file" "$out" > "$out"_

    mv "$out"_ "$out"

done