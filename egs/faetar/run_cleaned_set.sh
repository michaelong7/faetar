#!/usr/bin/env bash

usage="Usage: $0 [-h] [--stage I] [--only {true,false}] [--test-dir DIR] [--train-dir DIR] [--dev-dir DIR] [--cleaned-dir DIR] [--feat-jobs N] [--train-jobs N] [--decode-jobs N]"
stage=0
cleaned_dir=
test_dir=
train_dir=
dev_dir=
feat_jobs=4
train_jobs=4
decode_jobs=8
only=false
remake_graphs=false
scoring_opts="--min-lmwt 1 --max-lmwt 12"
help_message="Train model on cleaned and split HLVC Faetar subset

$usage

Options
-h            Display this help message
--stage       Start from this stage (deft: $stage)
--only        Run only one stage (deft: $only)
--cleaned-dir    Path to cleaned HLVC directory (deft: '$cleaned_dir')
--test-dir    Path to split test directory (deft: '$test_dir')
--train-dir    Path to split train directory (deft: '$train_dir')
--dev-dir    Path to split validation directory (deft: '$dev_dir')
--feat-jobs   Number of jobs to run in parallel when computing features
              (deft: $feat_jobs)
--train-jobs  Number of jobs to run in parallel when training models
              (deft: $train_jobs)
--decode-jobs Number of jobs to run in parallel when decoding audio
              (deft: $decode_jobs)
"



# . ./cmd.sh
# . utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "$usage"
  exit 1
fi

set -e

# prepare data
if [ $stage -le 0 ]; then
  if [ -z "$test_dir" ]; then
    echo "--test-dir unspecified!"
    exit 1
  elif [ -z "$train_dir" ]; then
    echo "--train-dir unspecified!"
    exit 1
  elif [ -z "$dev_dir" ]; then
    echo "--dev-dir unspecified!"
    exit 1
  elif [ -z "$cleaned_dir" ]; then
    echo "--cleaned-dir unspecified!"
    exit 1
  fi

  local/forced_ali_data_prep.sh "$cleaned_dir" "$test_dir" "$train_dir" "$dev_dir"
  local/faetar_prepare_dict.sh _train
  utils/prepare_lang.sh data/local/dict_train \
                "[x]" data/local/lang_tmp_train data/lang_train
  local/faetar_format_data.sh _train

  $only && exit 0
fi

 # construct mfccs
if [ $stage -le 1 ]; then
  for x in train test dev; do
    steps/make_mfcc.sh --cmd "$feat_cmd" --nj "$feat_jobs" data/$x
    steps/compute_cmvn_stats.sh data/$x
    utils/validate_data_dir.sh --non-print data/$x
  done
  
  $only && exit 0
fi

frame_shift=$(cat data/train/frame_shift)

# make speaker-independent monophone model
if [ $stage -le 2 ]; then
  steps/train_mono.sh --cmd "$train_cmd" --nj "$train_jobs" \
    data/train data/lang_train exp/mono0

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/mono0 exp/mono0/graph

  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" \
    data/train data/lang_train exp/mono0 exp/mono0_ali

  $only && exit 0
fi

# make speaker-independent triphone model
if [ $stage -le 3 ]; then
  steps/train_deltas.sh --cmd "$train_cmd" 2000 10000 \
    data/train data/lang_train exp/mono0_ali exp/tri1

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/tri1 exp/tri1/graph

  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" \
    data/train data/lang_train exp/tri1 exp/tri1_ali

  $only && exit 0
fi

# make speaker-independent triphone model with MLLT
if [ $stage -le 4 ]; then
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
    data/train data/lang_train exp/tri1_ali exp/tri2

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/tri2 exp/tri2/graph

  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" --use-graphs true \
    data/train data/lang_train exp/tri2 exp/tri2_ali

  $only && exit 0
fi

# make speaker-adaptive triphone model
if [ $stage -le 5 ]; then
  steps/train_sat.sh --cmd "$train_cmd" 4200 40000 \
    data/train data/lang_train exp/tri2_ali exp/tri3

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/tri3 exp/tri3/graph

  for y in train test dev; do
    steps/align_fmllr.sh --nj "$train_jobs" --cmd "$train_cmd" \
      data/$y data/lang_train exp/tri3 exp/tri3_${y}_ali
  done

  $only && exit 0
fi

# testing
if [ $stage -le 6 ]; then
    for y in train test dev; do
      local/ali_to_praat.sh --frame-shift $frame_shift \
       exp/tri3_${y}_ali data/$y
    done

  $only && exit 0
fi
