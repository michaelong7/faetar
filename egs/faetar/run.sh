#!/usr/bin/env bash

usage="Usage: $0 [-h] [--stage I] [--only {true,false}] [--test-dir DIR] [--train-dir DIR] [--feat-jobs N] [--train-jobs N] [--decode-jobs N]"
stage=0
test_dir=
train_dir=
feat_jobs=4
train_jobs=4
decode_jobs=8
only=false
help_message="Train model on cleaned and split HLVC Faetar subset

$usage

Options
-h            Display this help message
--stage       Start from this stage (deft: $stage)
--only        Run only one stage (deft: $only)
--test-dir    Path to split test directory (deft: '$test_dir')
--train-dir    Path to split train directory (deft: '$train_dir')
--feat-jobs   Number of jobs to run in parallel when computing features
              (deft: $feat_jobs)
--train-jobs  Number of jobs to run in parallel when training models
              (deft: $train_jobs)
--decode-jobs Number of jobs to run in paralllel when decoding audio
              (deft: $decode_jobs)
"



. ./cmd.sh
. utils/parse_options.sh

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
  fi

  local/faetar_data_prep.sh "$test_dir" "$train_dir"
  local/faetar_prepare_dict.sh _train
  utils/prepare_lang.sh data/local/dict_train \
                "[x]" data/local/lang_tmp_train data/lang_train
  local/faetar_format_data.sh _train

  $only && exit 0
fi

# construct mfccs
if [ $stage -le 1 ]; then
  for x in train test; do
    steps/make_mfcc.sh --cmd "$feat_cmd" --nj "$feat_jobs" data/$x
    steps/compute_cmvn_stats.sh data/$x
    utils/validate_data_dir.sh --non-print data/$x
  done
  
  $only && exit 0
fi

# make speaker-independent monophone model off train partition
if [ $stage -le 2 ]; then
  if [ ! -f "exp/mono0/final.mdl" ]; then
    steps/train_mono.sh --cmd "$train_cmd" --nj "$train_jobs" \
      data/train data/lang_train exp/mono0
  fi

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/mono0 exp/mono0/graph

  if [ ! -f "exp/mono0/decode_test/scoring_kaldi/best_cer" ]; then
    steps/decode.sh --nj "$decode_jobs" --cmd "$decode_cmd" \
      exp/mono0/graph data/test exp/mono0/decode_test
  fi
  
  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" \
    data/train data/lang_train exp/mono0 exp/mono0_ali

  $only && exit 0
fi

# make speaker-independent triphone model off train partition
if [ $stage -le 3 ]; then
  if [ ! -f "exp/tri1/final.mdl" ]; then
    steps/train_deltas.sh --cmd "$train_cmd" 2000 10000 \
      data/train data/lang_train exp/mono0_ali exp/tri1
  fi

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/tri1 exp/tri1/graph

  if [ ! -f "exp/tri1/decode_test/scoring_kaldi/best_cer" ]; then
    steps/decode.sh --nj "$decode_jobs" --cmd "$decode_cmd" \
      exp/tri1/graph data/test exp/tri1/decode_test
  fi
  
  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" \
    data/train data/lang_train exp/tri1 exp/tri1_ali

  $only && exit 0
fi

# same, but with MLLT
if [ $stage -le 4 ]; then
  if [ ! -f "exp/tri2/final.mdl" ]; then
    steps/train_lda_mllt.sh --cmd "$train_cmd" \
      --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
      data/train data/lang_train exp/tri1_ali exp/tri2
  fi

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/tri2 exp/tri2/graph

  if [ ! -f "exp/tri2/decode_test/scoring_kaldi/best_cer" ]; then
    steps/decode.sh --nj "$decode_jobs" --cmd "$decode_cmd" \
      exp/tri2/graph data/test exp/tri2/decode_test
  fi
  
  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd"  --use-graphs true \
    data/train data/lang_train exp/tri2 exp/tri2_ali

  $only && exit 0
fi

# make speaker-adaptive triphone model from train partition
if [ $stage -le 5 ]; then
  if [ ! -f "exp/tri3/final.mdl" ]; then
    steps/train_sat.sh --cmd "$train_cmd" 4200 40000 \
      data/train data/lang_train exp/tri2_ali exp/tri3
  fi

  utils/mkgraph.sh data/lang_train_test_tri-noprune exp/tri3 exp/tri3/graph

  if [ ! -f "exp/tri3/decode_test/scoring_kaldi/best_cer" ]; then
    steps/decode_fmllr.sh --nj "$decode_jobs" --cmd "$decode_cmd" \
      exp/tri3/graph data/test exp/tri3/decode_test
  fi
  
  steps/align_fmllr.sh --nj "$train_jobs" --cmd "$train_cmd" \
    data/train data/lang_train exp/tri3 exp/tri3_ali

  $only && exit 0
fi

# # clean up segmentations using SAT model
# if [ $stage -le 6 ]; then
#   steps/cleanup/clean_and_segment_data.sh \
#     --cmd "$train_cmd" --nj "$train_jobs" \
#     data/rough_reseg data/lang_rough exp/tri3 exp/rough_reseg_cleaned \
#     data/rough_reseg_cleaned
  
#   $only && exit 0
# fi

# # train once again a SAT model on the cleaned segmentations
# if [ $stage -le 7 ]; then
#   steps/align_fmllr.sh --nj "$train_jobs" --cmd "$train_cmd" \
#     data/rough_reseg_cleaned data/lang_rough exp/tri3 \
#     exp/tri3_ali_rough_reseg_cleaned

#   steps/train_sat.sh --cmd "$train_cmd" 4200 40000 \
#     data/rough_reseg_cleaned \
#     data/lang_rough exp/tri3_ali_rough_reseg_cleaned exp/tri4
  
#   local/get_ctms.sh --with-nooverlap true --frame-shift $frame_shift \
#     data/rough_reseg_cleaned data/lang_rough exp/tri4

#   $only && exit 0
# fi

# # construct a new data dir without overlaps, then align using tri4
# # FIXME(sdrobert): we're relying on logic from wsj/s5/local/run_segmentation.sh
# # which doesn't quite hold for segment_long_utts.sh
# #
# # A better method might be to construct a segments file via vad.scp (see
# # local/ali_to_praat.sh), then fill in those segments with the overlapping text
# # from steps/resegment_text.sh. Something like:
# #
# #   steps/resegment_text.sh \
# #     data/rough_reseg_cleaned data/lang_rough exp/tri4 \
# #     data/rough_vad exp/resegment_rough_vad
# #
# if [ $stage -le 8 ]; then
#   local/construct_nooverlap_data_dir.sh \
#     data/rough data/rough_reseg_cleaned exp/tri4 data/rough_reseg_nooverlap
#   steps/compute_cmvn_stats.sh data/rough_reseg_nooverlap

#   steps/align_fmllr.sh --nj "$train_jobs" --cmd "$train_cmd" \
#     data/rough_reseg_nooverlap data/lang_rough exp/tri4 \
#     exp/tri4_ali_rough_reseg_nooverlap
  
#   local/get_ctms.sh --with-nooverlap true --frame-shift $frame_shift \
#     data/rough_reseg_nooverlap data/lang_rough \
#     exp/tri4_ali_rough_reseg_nooverlap
#   local/ali_to_praat.sh --frame-shift $frame_shift \
#     --copy-wav $copy_wav exp/tri4_ali_rough_reseg_nooverlap \
#     data/rough_reseg_nooverlap
  
#   $only && exit 0
# fi
