#!/usr/bin/env bash

usage="Usage: $0 [-h] [--with-nooverlap {true,false}] [--clean {true,false}] [--frame-shift SEC] data-dir lang-dir exp-dir"
clean=true
with_nooverlap=false
frame_shift=0.01
help_message="Get CTM file from data and alignments and write to exp-dir/ctm

$usage
e.g. data/core data/lang_rough exp/mono0

--frame-shift     Seconds per frame increment (deft: $frame_shift)
--with-nooverlap  If true, generate exp-dir/ctm_nooverlap, which
                  resolves overlapping word segments (deft: $with_nooverlap)
--clean           Clean temporary files (deft: $clean)
"

echo "$0 $@"  # Print the command line for logging

. ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "$usage"
  exit 1
fi

data="$1"
lang="$2"
exp="$3"

set -e

steps/get_train_ctm.sh --frame-shift $frame_shift --print-silence true \
  "$data" "$lang" "$exp"

if $with_nooverlap; then
  tmp="$exp/ctm_segments"
  mkdir -p "$tmp"
  steps/get_train_ctm.sh --use-segments false --frame-shift $frame_shift \
    "$data" "$lang" "$exp" "$tmp"
  
  utils/ctm/resolve_ctm_overlaps.py \
    "$data/segments" "$tmp/ctm" - | \
    utils/ctm/convert_ctm.pl "$data/"{segments,reco2file_and_channel} | \
    sort -k1,1 -k2,2 -k3,3nb > "$exp/ctm_nooverlap"
  
  $clean && rm -rf "$tmp"
fi