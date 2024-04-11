#! /usr/bin/env bash

. ./path.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 test-dir train-dir dev-dir"
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

# construct kaldi files for given partition
function construct_kaldi_files () {
  search_dir="$1"
  suffix="$2"

  # make wav.scp files + text + segments files
  # only utterances with durations longer or equal to 500 ms are retained

  # clears files if they already exist / makes them if they don't
  :> "wav_${suffix}.scp"
  :> "text_${suffix}"
  :> "segments_${suffix}"

  while read -r path; do
    name="$(basename "$path" .wav)"
    dur="$(soxi -D "$path")"
    textfile="${path%%.wav}.txt"
    text="$(< "$textfile")"

    if (( $(bc -l <<< "$dur >= 0.5") )); then
      echo ""$name" "$path"" >> "wav_${suffix}.scp"

      printf "%s-000000-%06.0f %s\n" "$name" "$(bc -l <<< "$dur * 100")" "$text" |
      tee -a "text_${suffix}" |
      awk -v name="$name" -v dur="$dur" \
      '{printf "%s %s 0.00 %.2f\n", $1, name, dur}' - >> "segments_${suffix}"
    fi
  done <<< "$(find "$search_dir" -name "*.wav" | sort)"

  # make reco2dur files
  awk 'BEGIN {FS = " "} {print $2, $4}' < "segments_${suffix}" > "reco2dur_${suffix}"

  # make utt2spk files
  awk 'BEGIN {FS = "_"} {print $0, $1}' <<< "$(cut -d ' ' -f 1 < "text_${suffix}")" > "utt2spk_${suffix}"

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

function mannerize () {
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

    # remove length marker
    gsub(/ː/, "", text);

    # vowels + glides
    gsub(/a|i|e|o|u|ə|ɛ|ɪ|ɑ|ɔ|ʊ|ʌ|j|w/, "V ", text);

    # filled pauses
    gsub(/\[fp\]/, "Q ", text);

    # affricates
    gsub(/d[zʒ]|tʃ/, "C C ", text);

    # nasals
    gsub(/m|n|ŋ|ɲ/, "C ", text);

    # sibilants
    gsub(/s|z|ʃ|ʒ/, "C ", text);

    # other fricatives
    gsub(/ɣ|θ|ð|f|v|h/, "C ", text);

    # stops
    gsub(/b|d|ɡ|k|p|t/, "C ", text);

    # liquids
    gsub(/l|ʎ|r/, "C ", text);

    # others
    gsub(/x/, "C C ", text);
    gsub(/q/, "C ", text);
    gsub(/y|@/, "V ", text);

    print $1, text;
  }' "$text_file" > "$text_file"_
  mv "$text_file"{_,}
}

test_dir="$1"
train_dir="$2"
dev_dir="$3"
dir="$(pwd -P)/data/local/data"
mkdir -p "$dir"
local="$(pwd -P)/local"
utils="$(pwd -P)/utils"

cd "$dir"

construct_kaldi_files "$test_dir" "test"
construct_kaldi_files "$train_dir" "train"
construct_kaldi_files "$train_dir" "dev"

split_text text_test
split_text text_train
split_text text_dev

# mannerize text_train

# build LM
cut -d ' ' -f 2- text_train |
 "$local/ngram_lm.py" -o 5 --word-delim-expr " " |
 gzip -c > "lm.tri-noprune.gz"