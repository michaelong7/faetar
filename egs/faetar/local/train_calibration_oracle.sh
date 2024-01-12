#!/usr/bin/env bash
# Copyright 2015, Brno University of Technology (Author: Karel Vesely). Apache 2.0.

# Trains logistic regression, which calibrates the per-word confidences in 'CTM'.
# The 'raw' confidences are obtained by Minimum Bayes Risk decoding.

# The input features of logistic regression are:
# - logit of Minumum Bayer Risk posterior
# - log of word-length in characters
# - log of average-depth depth of a lattice at words' position
# - log of frames per character ratio
# (- categorical distribution of 'lang/words.txt', DISABLED)

# begin configuration section.
cmd=
lmwt=12
decode_mbr=false
word_min_count=10 # Minimum word-count for single-word category,
normalizer=0.0025 # L2 regularization constant,
category_text= # Alternative corpus for counting words to get word-categories (by default using 'ctm'),
stage=0
# end configuration section.

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 5 ]; then
  echo "Usage: $0 [opts] <data-dir> <lang-dir|graph-dir> <word-feats> <decode-dir> <calibration-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --lmwt <int>                    # scaling for confidence extraction"
  echo "    --decode-mbr <bool>             # use Minimum Bayes Risk decoding"
  echo "    --grep-filter <str>             # remove words from calibration targets"
  exit 1;
fi

set -euo pipefail

data=$1
lang=$2 # Note: may be graph directory not lang directory, but has the necessary stuff copied.
word_feats=$3
latdir=$4
dir=$5

if [ -e $latdir/final.mdl ]; then
  model=$latdir/final.mdl
elif [ -e $latdir/../final.mdl ]; then
  model=$latdir/../final.mdl
else
  echo "$0: expected $latdir/final.mdl or $latdir/../final.mdl to exist"
  exit 1
fi

for f in $data/text "$lang/"{words.txt,oov.int} \
         $word_feats "$latdir/"{lat.1.gz,num_jobs}; do
  [ ! -f $f ] && echo "$0: Missing file $f" && exit 1
done
[ -z "$cmd" ] && echo "$0: Missing --cmd '...'" && exit 1

[ -d $dir/log ] || mkdir -p $dir/log

nj=$(cat $latdir/num_jobs)
oov=$(cat $lang/oov.int)

# Store the setup,
echo $lmwt >$dir/lmwt
echo $decode_mbr >$dir/decode_mbr
cp $word_feats $dir/word_feats

frame_shift_opt=
if [ -f $latdir/../frame_shift ]; then
  frame_shift_opt="--frame-shift=$(cat $latdir/../frame_shift)"
  echo "$0: $latdir/../frame_shift exists, using $frame_shift_opt"
elif [ -f $latdir/../frame_subsampling_factor ]; then
  factor=$(cat $latdir/../frame_subsampling_factor) || exit 1
  frame_shift_opt="--frame-shift=0.0$factor"
  echo "$0: $latdir/../frame_subsampling_factor exists, using $frame_shift_opt"
fi


utils/split_data.sh $data $nj
sdata=$data/split${nj}

if [ $stage -le 1 ]; then
  $cmd JOB=1:$nj $latdir/log/get_oracle.JOB.log \
    lattice-oracle \
    "ark:gunzip -c $latdir/lat.JOB.gz |" \
    "ark:utils/sym2int.pl --map-oov $oov -f 2- $lang/words.txt $sdata/JOB/text|" \
    ark:$latdir/oracle_hyp.JOB.int || exit 1;

  echo -n "lattice_oracle_align.sh: overall oracle %WER is: "
  grep 'Overall %WER'  $latdir/log/get_oracle.*.log  | \
    perl -e 'while (<>){ if (m: (\d+) / (\d+):) { $x += $1; $y += $2}}  printf("%.2f%%\n", $x*100.0/$y); ' | \
    tee $latdir/log/oracle_overall_wer.log
fi

# Create the ctm with raw confidences,
# - we keep the timing relative to the utterance,
if [ $stage -le 2 ]; then
  $cmd JOB=1:$nj $dir/log/get_ctm.JOB.log \
    lattice-scale --inv-acoustic-scale=$lmwt "ark:gunzip -c $latdir/lat.JOB.gz|" ark:- \| \
    lattice-limit-depth ark:- ark:- \| \
    lattice-push --push-strings=false ark:- ark:- \| \
    lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- \| \
    lattice-to-ctm-conf --decode-mbr=$decode_mbr ark:- - \| \
    utils/int2sym.pl -f 5 $lang/words.txt \
    '>' $dir/JOB.ctm
  # Merge and clean,
  for ((n=1; n<=nj; n++)); do cat $dir/${n}.ctm; done |
    local/fiddle_ctm_overlaps.pl |
    awk '($4 > 0) {print}' > $dir/ctm
  rm $dir/*.ctm
fi

# Get evaluation of the 'ctm' using the 'text' reference,
if [ $stage -le 3 ]; then
  steps/conf/convert_ctm_to_tra.py $dir/ctm - | \
  align-text --special-symbol="<eps>" ark:$data/text ark:- ark,t:- | \
  utils/scoring/wer_per_utt_details.pl --special-symbol "<eps>" \
  >$dir/align_text 
  # Append alignment to ctm,
  steps/conf/append_eval_to_ctm.py $dir/align_text $dir/ctm $dir/ctm_aligned
  # Convert words to 'ids',
  cat $dir/ctm_aligned | utils/sym2int.pl -f 5 $lang/words.txt >$dir/ctm_aligned_int
fi

# Prepare word-categories (based on word frequencies in 'ctm'),
if [ -z "$category_text" ]; then
  steps/conf/convert_ctm_to_tra.py $dir/ctm - | \
  steps/conf/prepare_word_categories.py --min-count $word_min_count $lang/words.txt - $dir/word_categories
else
  steps/conf/prepare_word_categories.py --min-count $word_min_count $lang/words.txt "$category_text" $dir/word_categories
fi

# Compute lattice-depth,
latdepth=$dir/lattice_frame_depth.ark
if [ $stage -le 4 ]; then
  steps/conf/lattice_depth_per_frame.sh --cmd "$cmd" $latdir $dir
fi

# Create the training data for logistic regression,
if [ $stage -le 5 ]; then
  steps/conf/prepare_calibration_data.py \
    --conf-targets $dir/train_targets.ark --conf-feats $dir/train_feats.ark \
    --lattice-depth $latdepth $dir/ctm_aligned_int $word_feats $dir/word_categories
fi

# Train the logistic regression,
if [ $stage -le 6 ]; then
  logistic-regression-train --binary=false --normalizer=$normalizer ark:$dir/train_feats.ark \
    ark:$dir/train_targets.ark $dir/calibration.mdl 2>$dir/log/logistic-regression-train.log
fi

# Apply calibration model to dev,
if [ $stage -le 7 ]; then
  logistic-regression-eval --apply-log=false $dir/calibration.mdl \
    ark:$dir/train_feats.ark ark,t:- | \
    awk '{ key=$1; p_corr=$4; sub(/,.*/,"",key); gsub(/\^/," ",key); print key,p_corr }' | \
    utils/int2sym.pl -f 5 $lang/words.txt \
    >$dir/ctm_calibrated_int
fi

exit 0
