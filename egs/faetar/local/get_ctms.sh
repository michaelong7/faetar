#!/usr/bin/env bash

usage="Usage: $0 [-h] [--frame-shift SEC] data-dir lang-dir exp-dir"
frame_shift=0.01
help_message="Get CTM file from data and alignments and write to exp-dir/ctm

$usage
e.g. data/core data/lang_rough exp/mono0

--frame-shift     Seconds per frame increment (deft: $frame_shift)
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

# --print-silence in steps/get_train_ctm.sh gives incorrect values, so silence is added here
function add_silence() {
  ctm_file="$1"
  awk \
  'BEGIN {
    FS = " ";
    OFS = " ";
    new_file = 0;
    old_filename = "";
    old_start = 0;
    old_dur = 0;
  }
  
  NR == FNR {
    file_durs[$1] = $2;
    next;
  }
  
  {
    filename = $1;
    start = $3;
    dur = $4;
    
    if (old_filename != filename) {
      if (FNR != 1 && old_start + old_dur < file_durs[old_filename]) {
        printf "%s A %.2f %.2f <eps>\n", old_filename, old_start + old_dur, file_durs[old_filename] - old_start - old_dur;
      }
      
      if (start != 0) {
        printf "%s A %.2f %.2f <eps>\n", filename, 0, start;
        print $0;
      }
      else {
        print $0;
      }

      old_filename = filename
      old_start = start;
      old_dur = dur;
      next;
    }

    start_rounded = sprintf("%.2f", start);
    old_end_rounded = sprintf("%.2f", old_start + old_dur);
    if (start_rounded != old_end_rounded) {
      printf "%s A %.2f %.2f <eps>\n", filename, old_start + old_dur, start - old_start - old_dur;
      print $0;
      old_start = start;
      old_dur = dur;
      next;
    }
    else {
      print $0;
      old_start = start;
      old_dur = dur;
      next;
    }

  }' "$data"/reco2dur "$ctm_file" > "$ctm_file"_
  mv "$ctm_file"{_,}
}

steps/get_train_ctm.sh --frame-shift $frame_shift \
  "$data" "$lang" "$exp"

add_silence "$exp"/ctm