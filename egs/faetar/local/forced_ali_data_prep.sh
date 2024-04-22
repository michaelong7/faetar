#! /usr/bin/env bash

. ./path.sh

if [ $# -ne 4 ]; then
  echo "Usage: $0 cleaned-corpus-dir test-dir train-dir dev-dir"
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

if [ ! -d "$3" ]; then
  echo "$0: '$3' is not a directory"
  exit 1
fi

if [ ! -d "$4" ]; then
  echo "$0: '$4' is not a directory"
  exit 1
fi

# construct kaldi files
function construct_kaldi_files () {
  partitions=(train test dev)

  # clears files if they already exist / makes them if they don't
  for x in "${partitions[@]}"; do
    :> "wav_$x.scp"
    :> "text_$x"
    :> "segments_$x"
    :> "reco2dur_$x"
    :> "utt2spk_$x"
  done

  while read -r path; do
    name=$(sed 's/_w//' <<< "$(basename "$path" .wav)")
    dur="$(soxi -D "$path")"

    for x in "${partitions[@]}"; do
      if [[ $x == "test" ]]; then
        partition_dir="$test_dir"
      elif [[ $x == "train" ]]; then
        partition_dir="$train_dir"
      elif [[ $x == "dev" ]]; then
        partition_dir="$dev_dir"
      fi

      if [[ -z "$(find "$partition_dir" -name "*$name.txt" -print)" ]]; then
        continue
      else
        find "$partition_dir" -name "*$name.txt" -print |
        sort |
        xargs -I{} bash -c 'name="$(basename "$1" .txt | tr '_' '-' | cut -d - -f 1-3 )"; text="$(< "$1")"; echo -e "$name $text"' -- "{}" |
        tee -a "text_$x" |
        cut -d ' ' -f 1 |
        awk -v name="$name" -v partition="$x" \
        '{
          split($0, a, "-");
          printf "%s %s %.2f %.2f\n", $0, name, a[2] / 100, a[3] / 100 >> "segments_"partition
          print $0" "a[1] >> "utt2spk_"partition
        }'

        # make reco2dur files
        echo "$name $dur"  >> "reco2dur_$x"

        # make wav.scp files
        echo "$name $path" >> "wav_$x.scp"

      fi

    done

  done <<< "$(find "$cleaned_corpus_dir" -name "*.wav" | sort)"

  for x in "${partitions[@]}"; do
    for y in text_$x segments_$x utt2spk_$x reco2dur_$x wav_$x.scp; do
      sort -uk 1,1 "$y" > "$y"_
      mv "$y"{_,}
    done
  done

}

# splits text into individual phones
function split_text () {
  text_file="$1"

  awk \
  'BEGIN {
    FS = " ";
    OFS = " ";
    text = ""
  }

  {
    text = $2;

    for (i = 3; i <= NF; i++) {
      text = text $i;
    }

    gsub(/\[fp\]|d[zʒ]ː|tʃː|d[zʒ]|tʃ|\Sː|\S/, "& ", text);
    print $1, text;
    text = ""
  }' "$text_file" > "$text_file"_
  mv "$text_file"{_,}
}

cleaned_corpus_dir="$1"
test_dir="$2"
train_dir="$3"
dev_dir="$4"
dir="$(pwd -P)/data/local/data"
mkdir -p "$dir"
local="$(pwd -P)/local"
utils="$(pwd -P)/utils"

cd "$dir"

construct_kaldi_files 

split_text text_test
split_text text_train
split_text text_dev

# build LM
cut -d ' ' -f 2- text_train |
 "$local/ngram_lm.py" -o 5 --word-delim-expr " " |
 gzip -c > "lm.tri-noprune.gz"