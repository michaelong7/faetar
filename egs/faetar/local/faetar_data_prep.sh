#! /usr/bin/env bash

. ./path.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 test-dir train-dir"
  exit 1
fi

set -eo pipefail

if [ ! -d "$1" ]; then
  echo "$0: '$1' is not a directory"
  exit 1
fi

if [ ! -d "$2" ]; then
  echo "$0: '$2' is not a directory"
  exit 1
fi

# construct kaldi files for given partition
function construct_kaldi_files () {
    search_dir="$1"
    suffix="$2"

    # make wav.scp files
    find "$search_dir" -name "*.wav" |
    sort |
    tr '\n' '\0' |
    xargs -I{} -0 bash -c 'filename="$(basename "$1" '".wav"')"; echo -e ""$filename" "$1""' -- {} > "wav_${suffix}.scp"

    # make text files
    while read -r line; do
        name="$(cut -d ' ' -f 1 <<< "$line")"
        path="$(cut -d ' ' -f 2 <<< "$line")"
        dur="$(soxi -D "$path")"
        textfile="${path%%.wav}.txt"
        text="$(< "$textfile")"

        # only utterances with durations longer or equal to than 500 ms are retained
        if (( $(bc -l <<< "$dur >= 0.5") )); then
            printf "%s-0000000-%06.0f %s\n" "$name" "$(bc -l <<< "$dur * 100")" "$text"
        fi
        
    done < "wav_${suffix}.scp" > "text_${suffix}"

    # make utt2spk files
    awk 'BEGIN {FS = "_"} {print $0, $1}' <<< "$(cut -d ' ' -f 1 < "text_${suffix}")" > "utt2spk_${suffix}"

}

test_dir="$1"
train_dir="$2"
dir="$(pwd -P)/data/local/data"
mkdir -p "$dir"
local="$(pwd -P)/local"
utils="$(pwd -P)/utils"

cd "$dir"

construct_kaldi_files "$test_dir" "test"
construct_kaldi_files "$train_dir" "train"

# build LM
cut -d ' ' -f 2- text_train | \
 "$local/ngram_lm.py" -o 1 --word-delim-expr " " | \
 gzip -c > "lm.tri-noprune.gz"