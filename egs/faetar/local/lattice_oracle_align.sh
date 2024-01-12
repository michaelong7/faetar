#! /bin/bash

# Copyright 2016  Vimal Manohar
#           2016  Johns Hopkins University (author: Daniel Povey)
# Apache 2.0

set -e
set -o pipefail

cleanup=true
stage=0
cmd=run.pl
special_symbol="***"    # Special symbol to be aligned with the inserted or
                        # deleted words. Your sentences should not contain this
                        # symbol.
frame_shift=0.01
acwt=0.083333


. ./path.sh
. utils/parse_options.sh

if [ $# = 4 ]; then
  data=$1
  lang=$2
  latdir=$3
  caldir=
  dir=$4
elif [ $# = 5 ]; then
  data=$1
  lang=$2
  latdir=$3
  caldir=$4
  dir=$5
else
  echo "This script computes oracle paths for lattices (against a reference "
  echo "transcript) and does various kinds of processing of that, for use by "
  echo "steps/cleanup/cleanup_with_segmentation.sh."
  echo "Its main input is <latdir>/lat.*.gz."
  echo "This script outputs a human-readable word alignment of the oracle path"
  echo "through the lattice in <dir>/oracle_hyp.txt, and a time-aligned ctm version of"
  echo "the same in <dir>/ctm."
  echo "It also creates <dir>/edits.txt (the number of edits per utterance),"
  echo "<dir>/text (which is <data>/text but filtering out any utterances that"
  echo "were not decoded for some reason), and <dir>/length.txt, which is the length"
  echo "of the reference transcript, and <dir>/all_info.txt and <dir>/all_info.sorted.txt"
  echo "which contain all the info in a way that's easier to scan for humans."
  echo "Note: most of this is the same as is done in steps/cleanup/find_bad_utts.sh,"
  echo "except it runs from pre-existing lattices."
  echo ""
  echo "Usage: $0 <data> <lang> <latdir> [<caldir>] <dir>"
  echo " e.g.: $0 data/train_si284 data/lang exp/tri4_bad_utts/lats exp/tri4_bad_utts/lattice_oracle"
  echo "Main options (for others, see top of script file)"
  echo "  --config <config-file>            # config containing options"
  echo "  --cleanup <true|false>            # set this to false to disable cleanup of "
  echo "                                    # temporary files (default: true)"
  echo "  --cmd <command-string>            # how to run jobs (default: run.pl)."
  echo "  --special-symbol <special-symbol> #  Symbol to pad with in insertions and deletions in the"
  echo "                                    # output produced in <dir>/analysis/ (default: '***'"
  echo "  --frame-shift <frame-shift>       # Frame shift in seconds; default: 0.01.  Affects ctm generation."
  echo "  --acwt <acwt>                     # acoustic scale; default is 0.0833"
  echo "  --beam <beam>                     # beam width (for pruning); default is 5"
  exit 1
fi


for f in $lang/oov.int $lang/words.txt $data/text $latdir/lat.1.gz $latdir/num_jobs $lang/phones/word_boundary.int; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1;
done

mkdir -p $dir/log

if [ -e $dir/final.mdl ]; then
  model=$dir/final.mdl
elif [ -e $dir/../final.mdl ]; then
  model=$dir/../final.mdl
else
  echo "$0: expected $dir/final.mdl or $dir/../final.mdl to exist"
  exit 1
fi

nj=$(cat $latdir/num_jobs)
oov=$(cat $lang/oov.int)

if [ $stage -le 0 ]; then
  utils/split_data.sh $data $nj
fi

sdata=$data/split${nj}

if [ $stage -le 1 ]; then
  $cmd JOB=1:$nj $dir/log/get_oracle.JOB.log \
    lattice-oracle \
    "ark:gunzip -c $latdir/lat.JOB.gz |" \
    "ark:utils/sym2int.pl --map-oov $oov -f 2- $lang/words.txt $sdata/JOB/text|" \
    ark,t:- \| utils/int2sym.pl -f 2- $lang/words.txt '>' $dir/oracle_hyp.JOB.txt || exit 1;

  echo -n "$0: overall oracle %WER is: "
  grep 'Overall %WER'  $dir/log/get_oracle.*.log  | \
    perl -e 'while (<>){ if (m: (\d+) / (\d+):) { $x += $1; $y += $2}}  printf("%.2f%%\n", $x*100.0/$y); ' | \
    tee $dir/log/oracle_overall_wer.log

  for x in $(seq $nj); do cat $dir/oracle_hyp.$x.txt; done | awk '{if(NF>=1){print;}}' > $dir/oracle_hyp.txt
  for x in $(seq $nj); do cat $dir/oracle_hyp.$x.txt | awk '{if(NF>=1){print;}}' | utils/sym2int.pl -f 2- $lang/words.txt > $dir/oracle_hyp.$x.int; done
  if $cleanup; then
    rm $dir/oracle_hyp.*.txt
  fi
fi

echo $nj > $dir/num_jobs


if [ $stage -le 2 ]; then
  # The following command gets the time-aligned ctm as $dir/ctm.JOB.txt.
  if [ -z "$caldir" ]; then
    scale_arg="--acoustic-scale=$acwt"
  else
    scale_arg="--inv-acoustic-scale=$(cat $caldir/lmwt)"
    echo "$0: calibration directory set; clobbering --acoustic-scale=$acwt with $scale_arg"
  fi

  $cmd JOB=1:$nj $dir/log/get_ctm.JOB.log \
    set -o pipefail '&&' \
    lattice-scale $scale_arg "ark:gunzip -c $latdir/lat.JOB.gz|" ark:- \| \
    lattice-limit-depth ark:- ark:- \| \
    lattice-push --push-strings=false ark:- ark:- \| \
    lattice-align-words $lang/phones/word_boundary.int $model ark:- ark:- \| \
    lattice-to-ctm-conf --frame-shift=$frame_shift --print-silence=true --decode-mbr=false ark:- "ark,t:$dir/oracle_hyp.JOB.int" - \| \
    utils/int2sym.pl -f 5 $lang/words.txt '>' $dir/ctm.JOB || exit 1;

  # https://github.com/kaldi-asr/kaldi/issues/1465
  # The segments output by lattice-to-ctm-conf are sometimes overlapping and
  # sometimes empty. empty <eps> entries mess with get_ctm_edits.py
  for j in $(seq $nj); do cat $dir/ctm.$j; done |
      local/fiddle_ctm_overlaps.pl > $dir/ctm_nocalib
  
  if [ -z "$caldir" ]; then
    cp $dir/ctm{_nocalib,}
  else
    calibration=$caldir/calibration.mdl
    word_feats=$caldir/word_feats
    word_categories=$caldir/word_categories

    # filter out all empty entries or prepare_calibration_data.py complains at
    # us
    awk '($4 > 0) {print}' $dir/ctm_nocalib |
      utils/sym2int.pl -f 5 $lang/words.txt > $dir/ctm_int_noempty
    
    latdepth=$dir/lattice_frame_depth.ark
    steps/conf/lattice_depth_per_frame.sh --cmd "$cmd" $latdir $dir

    steps/conf/prepare_calibration_data.py --conf-feats $dir/forward_feats.ark \
      --lattice-depth $latdepth $dir/ctm_int_noempty $word_feats $word_categories
    
    logistic-regression-eval --apply-log=false $calibration \
      ark:$dir/forward_feats.ark ark,t:- |
      awk '{ key=$1; p_corr=$4; sub(/,.*/,"",key); gsub(/\^/," ",key); print key,p_corr }' |
      utils/int2sym.pl -f 5 $lang/words.txt > $dir/ctm_noempty
    
    # re-introduce empty entries, assigning them a confidence of 0.00
    awk '{print $1, $2, $3, $4, $5"\t"NR"\t"$6}' $dir/ctm_nocalib |
      sort |
      join -t $'\t' -a1 - \
        <(awk '{print $1, $2, $3, $4, $5"\t"$6}' $dir/ctm_noempty | sort) |
      awk -F $'\t' '{conf = (NF == 4) ? $4 : "0.00"; print $2, $1, conf}' |
      sort -k 1,1n |
      cut -d ' ' -f 2- > $dir/ctm
    
    diff_="$(diff <(cut -d ' ' -f 1-5 $dir/ctm) <(cut -d ' ' -f 1-5 $dir/ctm_nocalib) || true)"
    if [ ! -z "$diff_" ]; then
      echo "Calibrated ctm has different segments (left) from uncalibrated (right):"
      echo "$diff_"
      exit 1
    fi
  fi

  if $cleanup; then
    rm $dir/ctm.*
    rm $dir/ctm_*
    rm $dir/oracle_hyp.*.int
  fi
  echo "$0: oracle ctm is in $dir/ctm"
fi

# Stages below are really just to satifsy your curiosity; the output is the same
# as that of find_bad_utts.sh.

if [ $stage -le 3 ]; then
  # in case any utterances failed to align, get filtered copy of $data/text
  utils/filter_scp.pl $dir/oracle_hyp.txt < $data/text  > $dir/text
  cat $dir/text | awk '{print $1, (NF-1);}' > $dir/length.txt

  mkdir -p $dir/analysis

  align-text --special-symbol="$special_symbol"  ark:$dir/text ark:$dir/oracle_hyp.txt  ark,t:- | \
    utils/scoring/wer_per_utt_details.pl --special-symbol "$special_symbol" > $dir/analysis/per_utt_details.txt

  echo "$0: human-readable alignments are in $dir/analysis/per_utt_details.txt"

  awk '{if ($2 == "#csid") print $1" "($4+$5+$6)}' $dir/analysis/per_utt_details.txt > $dir/edits.txt

  n1=$(wc -l < $dir/edits.txt)
  n2=$(wc -l < $dir/oracle_hyp.txt)
  n3=$(wc -l < $dir/text)
  n4=$(wc -l < $dir/length.txt)
  if [ $n1 -ne $n2 ] || [ $n2 -ne $n3 ] || [ $n3 -ne $n4 ]; then
    echo "$0: mismatch in lengths of files:"
    wc $dir/edits.txt $dir/oracle_hyp.txt $dir/text $dir/length.txt
    exit 1;
  fi

  # note: the format of all_info.txt is:
  # <utterance-id>   <number of errors>  <reference-length>  <decoded-output>   <reference>
  # with the fields separated by tabs, e.g.
  # adg04_sr009_trn 1 	12	 SHOW THE GRIDLEY+S TRACK IN BRIGHT ORANGE WITH HORNE+S IN DIM RED AT	 SHOW THE GRIDLEY+S TRACK IN BRIGHT ORANGE WITH HORNE+S IN DIM RED

  paste $dir/edits.txt \
      <(awk '{print $2}' $dir/length.txt) \
      <(awk '{$1="";print;}' <$dir/oracle_hyp.txt) \
      <(awk '{$1="";print;}' <$dir/text) > $dir/all_info.txt

  sort -nr -k2 $dir/all_info.txt > $dir/all_info.sorted.txt

  echo "$0: per-utterance details sorted from worst to best utts are in $dir/all_info.sorted.txt"
  echo "$0: format is: utt-id num-errs ref-length decoded-output (tab) reference"
fi

if [ $stage -le 4 ]; then
  ###
  # These stats might help people figure out what is wrong with the data
  # a)human-friendly and machine-parsable alignment in the file per_utt_details.txt
  # b)evaluation of per-speaker performance to possibly find speakers with
  #   distinctive accents/speech disorders and similar
  # c)Global analysis on (Ins/Del/Sub) operation, which might be used to figure
  #   out if there is systematic issue with lexicon, pronunciation or phonetic confusability

  cat $dir/analysis/per_utt_details.txt | \
    utils/scoring/wer_per_spk_details.pl $data/utt2spk > $dir/analysis/per_spk_details.txt

  echo "$0: per-speaker details are in $dir/analysis/per_spk_details.txt"

  cat $dir/analysis/per_utt_details.txt | \
    utils/scoring/wer_ops_details.pl --special-symbol "$special_symbol" | \
    sort -i -b -k1,1 -k4,4nr -k2,2 -k3,3 > $dir/analysis/ops_details.txt

  echo "$0: per-word statistics [corr,sub,ins,del] are in $dir/analysis/ops_details.txt"
fi

if [ $stage -le 5 ]; then
  echo "$0: obtaining ctm edits"

  $cmd $dir/log/get_ctm_edits.log \
    align-text ark:$dir/oracle_hyp.txt ark:$dir/text ark,t:-  \| \
      steps/cleanup/internal/get_ctm_edits.py --oov=$oov --symbol-table=$lang/words.txt \
       /dev/stdin $dir/ctm $dir/ctm_edits || exit 1

  echo "$0: ctm with edits information appended is in $dir/ctm_edits"
fi
