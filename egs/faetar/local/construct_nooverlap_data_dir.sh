#!/usr/bin/env bash

clean=true
mseg_opts="--min-seg-length 0.05 --max-seg-length 10.0"
usage="Usage: $0 [-h] [--clean {true,false}] [--mseg-opts OPTS] full-dir overlap-dir exp-dir out-dir"
help_message="Construct segmented data dir without overlaps from one with

$usage
E.g. $0 data/rough data/rough_reseg_cleaned exp/tri4 data/rough_reseg_nooverlap

-h                    Display this help message
--clean               Whether to clean temporary folder in exp-dir
                      (deft: $clean)
--mseg-opts           Options to pass along to steps/cleanup/make_segmentation_data_dir.sh
                      (deft: '$mseg_opts')
"

echo "$0 $*"

. path.sh
. parse_options.sh

if [ $# -ne 4 ]; then
  echo "$usage"
  exit 1
fi

full="$1"
overlap="$2"
exp="$3"
out="$4"
tmp="$exp/construct_nooverlap_data_dir"
tmp_overlap="$tmp/overlap"
tmp_nooverlap="$tmp/nooverlap"

if [ ! -f "$full/segments" ]; then
  echo "No segments file in '$full'"
  exit 1
fi

if [ ! -f "$exp/ctm" ]; then
  echo "No ctm in '$exp'"
  exit 1
fi

utils/validate_data_dir.sh "$full" || exit 1
utils/validate_data_dir.sh --no-feats --no-text "$overlap" || exit 1

set -e

# use existing script to handle segment merging
mkdir -p "$tmp_overlap" "$tmp_nooverlap"
cp -f "$overlap/"{wav.scp,segments,utt2spk} "$tmp_overlap/"
paste -d ' ' \
  <(cut -d ' ' -f 1 "$full/wav.scp") \
  <(cut -d ' ' -f 2- "$full/text") \
  > "$tmp_overlap/text.orig"
#sed '/\[x\]$/d' "$exp/ctm" > "$tmp_overlap/ctm.no_oov"
steps/cleanup/make_segmentation_data_dir.sh \
  $mseg_opts "$exp/ctm" "$tmp_overlap" "$tmp_nooverlap"

# make new utterance names using the standard format
awk '
{printf "%s-1-%07.0f-%07.0f\n", $2, $3 * 100, $4 * 100}
' "$tmp_nooverlap/segments" > "$tmp/uttids"

# update transcription with new utterance names
cut -d ' ' -f 2- "$tmp_nooverlap/text" | \
  paste -d ' ' "$tmp/uttids" - > "$tmp/text"

# create subsegments file 
join -1 2 -2 2 "$tmp_nooverlap/segments" "$full/segments" -o '2.1,1.3,1.4' | \
  paste -d ' ' "$tmp/uttids" - > "$tmp/subsegments"

# actually create output
utils/data/subsegment_data_dir.sh \
  "$full" "$tmp/subsegments" "$tmp/text" "$out"

utils/fix_data_dir.sh "$out"
utils/validate_data_dir.sh "$out"

$clean && rm -rf "$tmp" || true
