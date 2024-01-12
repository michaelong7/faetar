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

# find all unique files of various types and creates bn2 files
# (we add a guard to avoid regenerating if we've already completed it once)
function find_files () {
  search_dir="$1"
  suffix="$2"

  for x in txt wav; do
    if [ ! -f "${x}list_${suffix}" ]; then
      find "$search_dir" -name "*.$x" |
      sort |
      tee "${x}list_${suffix}" |
      tr '\n' '\0' |
      xargs -I{} -0 bash -c 'filename="$(basename "$1" '".$x"')"; echo ""$filename":"$1""' -- {} > "bn2${x}_${suffix}"
    fi
  done
}

# construct kaldi files for given partition
function construct_kaldi_files () {
  partition_label="$1"

  join -1 2 -2 1 <(cut -d ' ' -f 1,2 < segments_unlab) <(tr ':' ' ' < "bn2txt_${partition_label}") |
  tr '\n' '\0' |
  xargs -I{} -0 bash -c 'read -ra v <<< "$1"; text="$(cat ${v[2]})" ; printf "%s %s\n" "${v[1]}" "$text"' -- {} > "text_${partition_label}"
  cut -d ' ' -f 1 "text_${partition_label}" > "${partition_label}.uttlist"
  join utt2spk_unlab "${partition_label}.uttlist" > "utt2spk_${partition_label}"
  join "${partition_label}.uttlist" segments_unlab > "segments_${partition_label}"
  cut -d ' ' -f 2 "segments_${partition_label}" | sort -u > "${partition_label}.recolist"
  join "${partition_label}.recolist" wav_unlab.scp > "wav_${partition_label}.scp"
  join "${partition_label}.recolist" reco2dur_unlab > "reco2dur_${partition_label}"

}

test_dir="$1"
train_dir="$2"
dir="$(pwd -P)/data/local/data"
mkdir -p "$dir"
local="$(pwd -P)/local"
utils="$(pwd -P)/utils"

cd "$dir"

find_files "$test_dir" "test"
find_files "$train_dir" "train"

# merges bn2wav_train and bn2wav_test, and wavlist_traind and wavlist_test
cat "bn2wav_test" "bn2wav_train" | sort -t ':' -k 1,1 > "bn2wav"
cat "wavlist_test" "wavlist_train" | sort -t ':' -k 1,1 > "wavlist"

# make symbolic links to wav files in links/ directory
mkdir -p links/
rm -f links/*
tr '\n' '\0' < wavlist |
  xargs -0 -I{} bash -c 'v="$(basename "$1" .wav)"; ln -sf "$1" "links/${v}.wav"' -- "{}"

# now we can use Kaldi's table format
cat bn2wav | cut -d ':' -f 1 |
  awk -v d="$(cd links; pwd -P)" '{print $1, "sox "d"/"$1".wav -t wav -b 16 - rate 16k remix 1 |"}' > wav_unlab.scp

# get those durations (lots of warnings - don't worry about those)
if [ ! -f "reco2dur_unlab" ]; then
  wav-to-duration "scp,s,o:wav_unlab.scp" "ark,t:reco2dur_unlab"
fi

# these mappings will be used to build collapsed partitions as well as a global 
# unlabelled partition (unlab)
cat reco2dur_unlab | \
  xargs -I{} bash -c 'read -ra v <<< "$1"; speaker=$(cut -d "_" -f 2 <<< "${v[0]}") ms=$(echo "${v[1]} * 100" | bc -l); printf "%s-%s-0000000-%06.0f %s 0.00 %.2f\n" "${v[0]}" "$speaker" "$ms" "${v[0]}" "${v[1]}"' -- {} \
  > segments_unlab
cut -d ' ' -f 1 segments_unlab > unlab.uttlist
cut -d ' ' -f 1 reco2dur_unlab > unlab.recolist
paste -d ' ' unlab.uttlist <(cut -d '-' -f 1,2 unlab.uttlist) > utt2spk_unlab

construct_kaldi_files "train"
construct_kaldi_files "test"

# build LM
cut -d ' ' -f 2- text_train | \
 "$local/ngram_lm.py" -o 1 --word-delim-expr " " | \
 gzip -c > "lm.tri-noprune.gz"
