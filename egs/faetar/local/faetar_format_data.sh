#!/usr/bin/env bash

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 lang-suffix"
  exit 1
fi

set -e

. ./path.sh

lang_suffix="$1"

echo "$0 $@"  # Print the command line for logging

for x in test train; do
  mkdir -p data/$x
  # rm -rf data/$x/* 
  cp -f data/local/data/wav_$x.scp data/$x/wav.scp
  cp -f data/local/data/utt2spk_$x data/$x/utt2spk

  utils/utt2spk_to_spk2utt.pl < data/$x/utt2spk > data/$x/spk2utt

  cp -f data/local/data/text_$x data/$x/text
  utils/validate_data_dir.sh data/$x --no-feats --non-print
done

# I don't think we actually need this, but to keep things in order...
for lm_type in tri-noprune; do
  test=data/lang${lang_suffix}_test_${lm_type}
  mkdir -p $test
  rm -rf $test
  utils/format_lm.sh \
    data/lang${lang_suffix} \
    data/local/data/lm.${lm_type}.gz \
    data/local/dict${lang_suffix}/lexicon.txt \
    $test

  utils/validate_lang.pl --skip-determinization-check $test
done
