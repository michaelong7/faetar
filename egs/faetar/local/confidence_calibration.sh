#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

set -euo pipefail

train_jobs=4
decode_jobs=8
lm=tri-noprune
mdl=exp/mono0
data=data/core
arpa_gz="data/local/data/lm.$lm.gz"
latdir=
caldir=
graph=

echo "$0: $*"
. ./utils/parse_options.sh

tmpdir="$(mktemp -d)"

if [ -z "$graph" ]; then
  graph="$mdl/graph_test_$lm"
  utils/mkgraph.sh data/lang_rough_test_$lm $mdl $graph
fi

if [ -z "$latdir" ]; then
  latdir="$mdl/decode_calib_$lm"
  steps/decode.sh --nj $decode_jobs --cmd $decode_cmd $graph $data $latdir
fi


lmwt=$(cat "$latdir/scoring_kaldi/cer_details/lmwt")
if [ -z "$caldir" ]; then
  caldir="$latdir/confidence_$lmwt"
fi

# Prepare filtering for excluding data from train-set (1 .. keep word, 0 .. exclude word),
# - only excludes from training-targets, the confidences are recalibrated for all the words,
word_filter="$tmpdir/word_filter"
awk '{ keep_the_word = $1 !~ /^(\[.*\]|<.*>|%.*|!.*|-.*|.*-)$/; print $0, keep_the_word }' \
  $graph/words.txt >$word_filter

# Calcualte the word-length,
word_length="$tmpdir/word_length"
awk '{if(r==0) { len_hash[$1] = NF-2; } 
      if(r==1) { if(len_hash[$1]) { len = len_hash[$1]; } else { len = -1 }  
      print $0, len; }}' \
  r=0 $graph/phones/align_lexicon.txt \
  r=1 $graph/words.txt \
  >$word_length

# Extract unigrams,
unigrams="$tmpdir/unigrams"
steps/conf/parse_arpa_unigrams.py $graph/words.txt $arpa_gz "$unigrams"

###### Paste the 'word-specific' features (first 4 columns have fixed position, more feature-columns can be added),
# Format: "word word_id filter length other_features"
word_feats="$tmpdir/word_feats"
paste $word_filter <(awk '{ print $3 }' $word_length) <(awk '{ print $3 }' $unigrams) > $word_feats

cp data/lang_rough/oov.int $graph/

###### Train the calibration,
local/train_calibration_oracle.sh --cmd "$decode_cmd" --lmwt $lmwt \
  $data $graph $word_feats $latdir $caldir
