#!/usr/bin/env bash

cmd=run.pl
copy_wav=false
frame_shift=0.01
help_message="Usage: $0 model_dir data_dir

e.g. $0 exp/mono0 data/core

Options
--cmd {run.pl,queue.pl}
--copy-wav {true,false}
--frame-shift POS
"

echo "$0 $@"  # Print the command line for logging

. ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "$help_message"
  exit 1
fi

model_dir="$1"
data_dir="$2"

if [ ! -f "$model_dir/final.mdl" ] || [ ! -f "$model_dir/phones.txt" ]; then
  echo "$model_dir does not contain final.mdl and/or phones.txt (is this a model directory?)"
  exit 1
fi 

if [ ! -f "$data_dir/segments" ] || [ ! -f "$data_dir/text" ]; then
  echo "$data_dir does not countain text and/or segments (is this a data directory?)"
  exit 1
fi

alis=( "$model_dir"/ali.*.gz )
if [ "${#alis[@]}" = 0 ]; then
  echo "No alignments in $model_dir!"
  exit 1
fi

set -e

praat_dir="$model_dir/praat"
tmp_dir="$praat_dir/tmp"

rm -rf "$praat_dir"/*
mkdir -p "$praat_dir" "$tmp_dir"

for i in "${!alis[@]}"; do
  cp "${alis[i]}" "$tmp_dir/ali.$((i+1)).gz"
done

$cmd JOB=1:"${#alis[@]}" "$tmp_dir/show_alignments.JOB.log" \
  show-alignments \
    "$model_dir/phones.txt" \
    "$model_dir/final.mdl" \
    "ark:gunzip -c $tmp_dir/ali.JOB.gz |" \
  \> "$tmp_dir/readable.JOB"

awk '
BEGIN {last = ""}
last == $1 {
  for (n=2; n<=NF; n++) print $1, starts[n - 2], ends[n - 2], $n
}
last != $1 {
  si=0; ei=0
  for (n=2; n<=NF; n++) {
    if ($n == "[") {starts[si] = n - si - ei - 1; si++}
    if ($n == "]") {ends[ei] = n - si - ei - 1; ei++}
  }
  last = $1
}
' "$tmp_dir/readable."* | \
  sed '/SIL$/d; s/_[BIES]//' > "$tmp_dir/phones_frames"

awk -v "fs=$frame_shift" '
FNR == NR {utt2start[$1] = $3}
FNR != NR {printf "%s %.2f %.2f %s\n", $1, utt2start[$1] + $2 * fs, utt2start[$1] + $3 * fs, $4}
' "$data_dir/segments" "$tmp_dir/phones_frames" | \
  perl -CS -p "local/sampa_to_ipa.pl" > "$tmp_dir/phones_segments"

awk '
BEGIN {last=""}
$1 == last {end=$3}
$1 != last {
  if (last != "") print last, start, end;
  last=$1; start=$2; end=$3;
}
END {print last, start, end}' "$tmp_dir/phones_segments" | sort | \
  join - "$data_dir/text" > "$tmp_dir/utts_segments"

if [ -f "$data_dir/vad.scp" ]; then
  # N.B. This cmd uses the same utterance id to refer to different segments.
  # This isn't a problem for the python cmd below as it doesn't rely on
  # uniqueness
  copy-vector "scp:$data_dir/vad.scp" "ark,t:-" | \
    sed -e "s/\[ //g;s/ \]//g" | \
    utils/segmentation.pl --remove-noise-only-segments false | \
    join -1 2 - "$data_dir/segments" -o '2.1,2.3,1.3,1.4' | \
    awk '{print $1, $2 + $3, $2 + $4, "[x]"}' > "$tmp_dir/vad_segments"
fi

wav-to-duration "scp,s,o:$data_dir/wav.scp" "ark,t:$tmp_dir/rec2dur"

python -c '
import os
import sys
import pympi
import warnings

dir_ = sys.argv[1]
TOLERANCE_SEC = 0.1

rec2dur = dict()
with open(f"{dir_}/rec2dur") as f:
  for line in f:
    rec, dur = line.strip().split()
    rec2dur[rec] = float(dur)

rec2tier2segs = dict()
for tier in ("utts", "phones", "vad"):
  seg_file = f"{dir_}/{tier}_segments"
  if not os.path.exists(seg_file):
    warnings.warn(f"Missing tier {tier}")
    continue
  with open(seg_file) as f:
    prev_rec, prev_spk = None, None
    prev_interval_end = 0
    for line in f:
      utt, start, end, label = line.strip().split(maxsplit=3)
      spk, _, _, rec = utt.rsplit("-", maxsplit=3)

      if prev_rec is None or prev_rec != rec or prev_spk != spk:
        prev_interval_end = 0
        prev_rec = rec
        prev_spk = spk

      tier2segs = rec2tier2segs.setdefault(rec, dict())
      interval = tier2segs.setdefault(f"{spk} {tier}", [])

      overlap_sec = prev_interval_end - float(start)
      if overlap_sec <= 0:
        interval.append((float(start), float(end), label))
      elif overlap_sec <= TOLERANCE_SEC:
        interval.append((prev_interval_end, float(end), label))
      else:
        raise Exception(f"Substantial overlap in {rec}-{spk}: {prev_interval_end} > {float(start)}")
      prev_interval_end = float(end)

recs = set(rec2dur) & set(rec2tier2segs)
for missing_seg in set(rec2dur) - recs:
  warnings.warn(f"Mising segmentation of {missing_seg}")

for missing_wav in set(rec2tier2segs) - recs:
  warnings.warn(f"Missing wav of {missing_wav}")

for rec in recs:
  tg = pympi.Praat.TextGrid(xmax=rec2dur[rec])
  for tier, segs in sorted(rec2tier2segs[rec].items()):
    tier = tg.add_tier(tier)
    for seg in segs:
      tier.add_interval(*seg)
  tg.to_file(f"{dir_}/{rec}.TextGrid")
' "$tmp_dir"

cp "$tmp_dir/"*.TextGrid "$praat_dir"

if $copy_wav; then
  cut -d ' ' -f 3 "$data_dir/wav.scp" | \
    xargs -I{} bash -c 'cp -Lf "$2" "$1/$(basename "$2")"' -- "$praat_dir" {}
fi

rm -rf "$tmp_dir"
