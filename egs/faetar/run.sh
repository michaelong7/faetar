#!/usr/bin/env bash

usage="Usage: $0 [-h] [--stage I] [--only {true,false}] [--hlvc-dir DIR] [--feat-jobs N] [--train-jobs N] [--decode-jobs N] [--copy-wav {true,false}]"
stage=0
hlvc_dir=
feat_jobs=4
train_jobs=4
decode_jobs=8
only=false
copy_wav=false
graph_opts="--min-lm-state-count 1 --discounting-constant 0.15"
help_message="Train model on cleaned and split HLVC Faetar subset

$usage

Options
-h            Display this help message
--stage       Start from this stage (deft: $stage)
--only        Run only one stage (deft: $only)
--hlvc-dir    Path to cleaned HLVC directory (deft: '$hlvc_dir')
--feat-jobs   Number of jobs to run in parallel when computing features
              (deft: $feat_jobs)
--train-jobs  Number of jobs to run in parallel when training models
              (deft: $train_jobs)
--decode-jobs Number of jobs to run in paralllel when decoding audio
              (deft: $decode_jobs)
--copy-wav    If true, when generating praat TextGrid files, copy wav files
              to the directory as well (deft: $copy_wav)
"



. ./cmd.sh
. utils/parse_options.sh

if [ $# -ne 0 ]; then
  echo "$usage"
  exit 1
fi

set -e

if [ $stage -le 0 ]; then
  if [ -z "$hlvc_dir" ]; then
    echo "--hlvc-dir unspecified!"
    exit 1
  fi
  if [ $(find "$hlvc_dir" -name 'hl_w011.wav' | head -n 1 | wc -l) != 1 ]; then
    echo "Could not find hl_w011.wav in '$hlvc_dir'"
    if [ $(find "$hlvc_dir" -name 'FAETAR (Homeland)' -type d | head -n 1 | wc -l) = 1 ]; then
      echo "This could be the unclean version." 
      echo "Try calling:"
      echo "  local/remake_corpus.sh mappings/wav_mapping_homeland.txt '$hlvc_dir'"
      echo "  local/remake_corpus.sh mappings/wav_mapping_heritage.txt '$hlvc_dir'"
      echo "and setting --hlvc-dir to '${hlvc_dir}_cleaned'"
    fi
    exit 1
  fi

  local/hlvc_faetar_data_prep.sh "$hlvc_dir"
  local/hlvc_faetar_prepare_dict.sh _rough
  utils/prepare_lang.sh data/local/dict_rough \
                "[x]" data/local/lang_tmp_rough data/lang_rough
  local/hlvc_faetar_format_data.sh _rough

  $only && exit 0
fi

# construct mfccs
if [ $stage -le 1 ]; then
  steps/make_mfcc.sh --cmd "$feat_cmd" --nj "$feat_jobs" data/unlab
  steps/compute_cmvn_stats.sh data/unlab
  steps/compute_vad_decision.sh data/unlab

  # these are subsets of unlab; don't recompute anything
  for x in core_collapsed doc rough; do
    join <(cut -d ' ' -f 1 data/$x/utt2spk) data/unlab/feats.scp \
      > data/$x/feats.scp
    join <(cut -d ' ' -f 1 data/$x/utt2spk) data/unlab/vad.scp \
      > data/$x/vad.scp
    join <(cut -d ' ' -f 1 data/$x/spk2utt) data/unlab/cmvn.scp \
      > data/$x/cmvn.scp
    utils/validate_data_dir.sh data/$x
  done

  # the core partition involves subsegmenting data/core_collapsed.
  # We use subsegment_data_dir.sh to avoid re-computing features. However,
  # the script overwrites the speaker ids, which we revert. Also, we compute
  # cmvn info
  join -1 2 -2 2 data/{core_collapsed,core}/segments -o '2.1,1.1,2.3,2.4' \
    > data/core/subsegments
  utils/data/subsegment_data_dir.sh \
    data/core_collapsed data/core/subsegments data/core
  rm data/core/subsegments
  sed -i -e 's/^\(.*\)-\([1-9]\)-\(.*\)[1-9]$/\1-\2-\3\2/' data/core/utt2spk 
  utils/utt2spk_to_spk2utt.pl < data/core/utt2spk > data/core/spk2utt
  steps/compute_cmvn_stats.sh data/core
  
  $only && exit 0
fi

frame_shift=$(cat data/unlab/frame_shift)

# make speaker-independent monophone model off core partition
if [ $stage -le 2 ]; then
  steps/train_mono.sh --cmd "$train_cmd" --nj "$train_jobs" \
    data/core data/lang_rough exp/mono0
  
  local/get_ctms.sh --frame-shift $frame_shift \
    data/core data/lang_rough exp/mono0
  local/ali_to_praat.sh --frame-shift $frame_shift \
    --copy-wav $copy_wav exp/mono0 data/core

  $only && exit 0
fi

# # make speaker-independent triphone model off core partition
# if [ $stage -le 3 ]; then
#   steps/train_deltas.sh --cmd "$train_cmd" 2000 10000 \
#     data/core data/lang_rough exp/mono0 exp/tri1

#   local/get_ctms.sh --frame-shift $frame_shift \
#     data/core data/lang_rough exp/tri1
#   local/ali_to_praat.sh --frame-shift $frame_shift \
#     --copy-wav $copy_wav exp/tri1 data/core

#   $only && exit 0
# fi

# # same, but with MLLT
# if [ $stage -le 4 ]; then
#   steps/train_lda_mllt.sh --cmd "$train_cmd" \
#     --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
#     data/core data/lang_rough exp/tri1 exp/tri2

#   local/get_ctms.sh --frame-shift $frame_shift \
#     data/core data/lang_rough exp/tri2
#   local/ali_to_praat.sh --frame-shift $frame_shift \
#     --copy-wav $copy_wav exp/tri2 data/core

#   $only && exit 0
# fi

# We're roughly following along with wsj/s5/local/run_segmentation_long_utts.sh
#
# N.B. you'll see a 
#
#   sort: write failed: 'standard output': Broken pipe
#
# message. This is by design. See steps/cleanup/make_biased_lm_graphs.sh:102
if [ $stage -le 5 ]; then
  steps/cleanup/segment_long_utterances.sh \
    --cmd "$train_cmd" --nj "$train_jobs" \
    --align-full-hyp true \
    --max-segment-duration 30 --overlap-duration 5 \
    --num-neighbors-to-search 0 --graph-opts "$graph_opts" \
    exp/mono0 data/lang_rough data/rough{,_reseg} exp/rough_reseg

  steps/compute_cmvn_stats.sh data/rough_reseg

  utils/fix_data_dir.sh data/rough_reseg

  $only && exit 0
fi

# cleans segmentations
if [ $stage -le 6 ]; then
  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" \
    data/rough_reseg data/lang_rough exp/mono0 exp/mono0_ali_rough_reseg

  local/get_ctms.sh --with-nooverlap true --frame-shift $frame_shift \
    data/rough_reseg data/lang_rough exp/mono0_ali_rough_reseg

  local/fix_utt_names.sh data/rough_reseg data/rough_reseg_fixed_utts

  # # change conf_thresh later
  # local/clean_and_segment_data.sh \
  #   --cmd "$train_cmd" --nj "$train_jobs" \
  #   --conf-thresh 1.0 \
  #   data/rough_reseg data/lang_rough exp/mono0_ali_rough_reseg exp/rough_reseg_cleaned \
  #   data/rough_reseg_cleaned

  $only && exit 0
fi

if [ $stage -le 7 ]; then
  local/construct_nooverlap_data_dir.sh --clean false \
    data/rough data/rough_reseg_fixed_utts exp/mono0_ali_rough_reseg data/rough_reseg_nooverlap
    
  steps/compute_cmvn_stats.sh data/rough_reseg_nooverlap

  steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" \
    data/rough_reseg_nooverlap data/lang_rough exp/mono0 \
    exp/mono0_ali_rough_reseg_nooverlap

  local/get_ctms.sh --with-nooverlap true --frame-shift $frame_shift \
    data/rough_reseg_nooverlap data/lang_rough \
    exp/mono0_ali_rough_reseg_nooverlap
  local/ali_to_praat.sh --frame-shift $frame_shift \
    --copy-wav $copy_wav exp/mono0_ali_rough_reseg_nooverlap \
    data/rough_reseg_nooverlap

  $only && exit 0
fi

# # train speaker-adaptive triphone model based on resegmentations
# if [ $stage -le 6 ]; then
#   utils/split_data.sh data/rough_reseg "$train_jobs"
#   steps/align_si.sh --nj "$train_jobs" --cmd "$train_cmd" \
#     data/rough_reseg data/lang_rough exp/tri2 exp/tri2_ali_rough_reseg

#   steps/train_sat.sh --cmd "$train_cmd" 4200 40000 \
#     data/rough_reseg data/lang_rough exp/tri2_ali_rough_reseg exp/tri3
  
#   local/get_ctms.sh --with-nooverlap true --frame-shift $frame_shift \
#     data/rough_reseg data/lang_rough exp/tri3

#   $only && exit 0
# fi

# # clean up segmentations using SAT model
# if [ $stage -le 7 ]; then
#   steps/cleanup/clean_and_segment_data.sh \
#     --cmd "$train_cmd" --nj "$train_jobs" \
#     data/rough_reseg data/lang_rough exp/tri3 exp/rough_reseg_cleaned \
#     data/rough_reseg_cleaned
  
#   $only && exit 0
# fi

# # train once again a SAT model on the cleaned segmentations
# if [ $stage -le 8 ]; then
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
# if [ $stage -le 9 ]; then
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

# # TODO
# # - incorporate some pre-trained speaker diarization model to determine
# #   when speakers change, e.g. https://kaldi-asr.org/models/m6
# # - set aside interviewer speech (filtered out in dump_eafs.py; modify filter
# #   regexes), then train a speaker identification system to identify if/when
# #   Naomi is speaking in the partition
