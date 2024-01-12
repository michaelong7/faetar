#! /usr/bin/env bash

cleanup=true

echo "$0 $@"

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# != 2 ]; then
  echo "Create a new data dir from an old one, but with utt ids in format "
  echo "  <spk>-<frame-start>-<frame-end>"
  echo ""
  echo "Usage: $0 [options] <source-data> <dest-data>"
  echo " Options:"
  echo "    --cleanup (true|false)  whether to clean up intermediate files."
  echo "                            Default true"
  echo "e.g.:"
  echo "$0 data/rough_reseg_no_x data/rough_reseg_fixed"
  exit 1
fi

srcdir="$1"
dir="$2"
workdir="$dir/fix_utt_names"

if [ ! -f "$srcdir/utt2spk" ] && [ -f "$srcdir/spk2utt" ]; then
  utils/spk2utt_to_utt2spk.pl < "$srcdir/spk2utt" > "$srcdir/utt2spk"
fi

for x in "$srcdir/segments" "$srcdir/utt2spk"; do
  if [ ! -f "$x" ]; then
    echo "Expected '$x' to exist!"
    exit 1
  fi
done

mkdir -p "$workdir"

set -e

awk -v p=0 -F ' ' '
{
  A = length($3); B = length($4);
  a = A - index($3, "."); b = B - index($4, ".");
  p = ((p < a) && (a != A)) ? a : p;
  p = ((p < b) && (b != B)) ? b : p;
}
END {print p}' "$srcdir/segments" > "$workdir/prec"

awk -v p=$(cat "$workdir/prec") -v d=0 -F ' ' '
{
  a = log($3) / log(10) + p;
  b = log($4) / log(10) + p;
  d = (d < a) ? a : d;
  d = (d < b) ? b : d;
}
END {print (d > int(d)) ? int(d) + 1 : int(d)}' "$srcdir/segments" > "$workdir/digits"

join -t ' ' -o1.1,2.2,1.3,1.4 "$srcdir/segments" "$srcdir/utt2spk" |
  awk -v p=$(cat "$workdir/prec") -v d=$(cat "$workdir/digits") -F ' ' '
BEGIN {
  fmt_str = sprintf("%%s-%%0%dd-%%0%dd %%s\n", d, d);
  p = 10 ** p;
}
{printf(fmt_str, $2, $3 * p, $4 * p, $1)}' > "$workdir/new2old_utt"

for x in utt2spk segments vad.scp feats.scp utt2dur utt2max_frames utt2num_frames text; do
  if [ -f "$srcdir/$x" ]; then
    utils/apply_map.pl -f 2 "$srcdir/$x" < "$workdir/new2old_utt" > "$dir/$x"
  fi
done
utils/utt2spk_to_spk2utt.pl  < "$dir/utt2spk" > "$dir/spk2utt"

for x in wav.scp reco2dur reco2file_and_channel frame_shift cmvn.scp; do
  if [ -f "$srcdir/$x" ]; then
    cp "$srcdir/$x" "$dir/$x"
  fi
done

utils/validate_data_dir.sh "$dir"

if $cleanup; then
  rm -rf "$workdir"
fi