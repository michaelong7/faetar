#! /usr/bin/env bash

. ./path.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 test-dir train-dir"
  exit 1
fi

set -eo pipefail

if [ ! -d "$1" ]; then
  echo "$0: '$1' is not a directory"
  exit 1
fi

if [ ! -d "$2" ]; then
  echo "$0: '$2' is not a directory"
  exit 1
fi

# find all unique files of various types and creates bn2 files
# (we add a guard to avoid regenerating if we've already completed it once)
function find_files () {
  search_dir="$1"
  suffix="$2"

  for x in txt wav; do
    if [ ! -f "${x}list_${suffix}" ]; then
      find "$search_dir" -name "*.$x" |
      sort -V |
      tee "${x}list_${suffix}" |
      tr '\n' '\0' |
      xargs -I{} -0 bash -c 'filename="$(basename "$1" '".$x"')"; echo ""$filename":"$1""' -- {} > "bn2${x}_${suffix}"
    fi
  done
}

test_dir="$1"
train_dir="$2"
dir="$(pwd -P)/data/local/data"
mkdir -p "$dir"
local="$(pwd -P)/local"
utils="$(pwd -P)/utils"

cd "$dir"

find_files "$test_dir" "test"
find_files "$train_dir" "train"

# merges bn2wav_train and bn2wav_test, and wavlist_traind and wavlist_test
cat "bn2wav_test" "bn2wav_train" | sort -V > "bn2wav"
cat "wavlist_test" "wavlist_train" | sort -V > "wavlist"

# # make symbolic links to wav files in links/ directory
# mkdir -p links/
# rm -f links/*
# tr '\n' '\0' < wavlist |
#   xargs -0 -I{} bash -c 'v="$(basename "$1" .wav)"; ln -sf "$1" "links/${v}.wav"' -- "{}"

# # now we can use Kaldi's table format
# cat bn2wav | cut -d ':' -f 1 |
#   awk -v d="$(cd links; pwd -P)" '{print $1, "sox "d"/"$1".wav -t wav -b 16 - rate 16k remix 1 |"}' > wav_unlab.scp

# # get those durations (lots of warnings - don't worry about those)
# if [ ! -f "reco2dur_unlab" ]; then
#   wav-to-duration "scp,s,o:wav_unlab.scp" "ark,t:reco2dur_unlab"
# fi

# # these mappings will be used to build collapsed partitions as well as a global 
# # unlabelled partition (unlab)
# cat reco2dur_unlab | \
#   xargs -I{} bash -c 'read -ra v <<< "$1"; speaker=$(cut -d "_" -f 2 <<< "${v[0]}") ms=$(echo "${v[1]} * 100" | bc -l); printf "%s-%s-0000000-%06.0f %s 0.00 %.2f\n" "${v[0]}" "$speaker" "$ms" "${v[0]}" "${v[1]}"' -- {} \
#   > segments_unlab
# cut -d ' ' -f 1 segments_unlab > unlab.uttlist
# cut -d ' ' -f 1 reco2dur_unlab > unlab.recolist
# paste -d ' ' unlab.uttlist <(cut -d '-' -f 1-2 unlab.uttlist) > utt2spk_unlab

# # construct kaldi files for train partition (labelled core to align with past scripts)

# join -1 2 -2 1 <(sort segments_unlab | cut -d ' ' -f 1,2) <(tr ':' ' ' < bn2txt_train | sort) |
# tr '\n' '\0' |
# xargs -I{} -0 bash -c 'read -ra v <<< "$1"; text="$(cat ${v[2]})" ; printf "%s %s\n" "${v[1]}" "$text"' -- {} |
# sort -V > "text_core"

exit 20

# convert eaf files to <utt_id> <rec_id> <spkr_id> <start_s> <end_s> <trans>
cat bn2eaf | tr '\n' '\0' |
  xargs -0 -I{} bash -c 'IFS=: read -ra v <<< "$1"; for i in $(seq 1 $((${#v[@]} - 1))); do '"$local"'/dump_eaf.py "${v[0]}" "${v[i]}" || true; done' -- "{}" |
  sort -k 1,4 |
  awk -f "$local/delete_nested_utterances.awk" |
  awk '!(tolower($5) == "nn" || tolower($5) ~ /iver.*/ || $5 == "interviewer")' > eaf_dump_core

# check that no utterances are going past the length of the file
cut -d ' ' -f 2,4 eaf_dump_core |
  awk 'BEGIN {id=""; last=""} $1 != id {if (last != "") print last} {id=$1; last=$0} END {print last}' |
  join - reco2dur_unlab |
  awk '$2 <= ($3 + 0.005) {print $1}' > keeplist
if [ "$(cut -d ' ' -f 2 eaf_dump_core | uniq | wc -l)" != "$(cat keeplist | wc -l)" ]; then
  echo "WARNING: some eaf files have longer segment lengths than recordings!"
  diff <(cut -d ' ' -f 2 eaf_dump_core | uniq) keeplist || true
  echo "Ignoring!"
fi

# construct kaldi files for core partition
join -2 2 keeplist eaf_dump_core | 
  cut -d ' ' -f 2,6- |
  # Get rid of any segment containing '..'. It's how some segments mark
  # "I didn't transcribe this". Can't put this in sanitize_text b/c it mucks
  # with docx logic
  grep -vF '..' |
  perl -CS -n "$local/sanitize_text.pl" > text_core
cut -d ' ' -f 1 text_core > core.uttlist
awk -v "rlast=" '
{
  if (rlast != $2) {split("", spk2id); sidx=0}
  if (spk2id[$5] == "") spk2id[$5] = ++sidx;
  rlast=$2;
  print $1, $2"-"spk2id[$5];
}
' eaf_dump_core | join core.uttlist - > utt2spk_core
cut -d ' ' -f 1-4 eaf_dump_core | join core.uttlist - > segments_core
cut -d ' ' -f 2 segments_core | sort -u > core.recolist
join core.recolist wav_unlab.scp > wav_core.scp
join core.recolist reco2dur_unlab > reco2dur_core

# kaldi likes utterances sorted by speaker id first. utterance ids have
# DEADBEEF inserted in them, to be replaced by the speaker id
sed -e 's/^.*-DEADBEEF\([^ ]*\) \(.*\)$/\2\1/' utt2spk_core > core.uttlist
for x in text segments utt2spk; do
  paste -d ' ' core.uttlist <(cut -d ' ' -f 2- ${x}_core) | sort > ${x}_core_
  mv ${x}_core{_,}
done
sort core.uttlist > core.uttlist_
mv core.uttlist{_,}

# there could be more than one docx per recording, but they'll be ranked
# by suffixes (t01, t02, etc.). Take the first one
awk '{
  match($0, /[0-9][0-9]*\.docx$/);
  t=substr($0,RSTART, RLENGTH-5);
  print t":"$0}' bn2docx |
  sort -t ':' -k 2,2 -k 1,1n |
  sort -t ':' -k 2,2 -us |
  cut -d ':' -f 2- > bn2docx_toprank

# take the docs we have recordings for
cut -d ':' -f 1 bn2docx_toprank > doc.recolist

# make some of the doc partition based off reco
join doc.recolist wav_unlab.scp > wav_doc.scp
filter_scp.pl -f 2 doc.recolist segments_unlab > segments_doc
join doc.recolist reco2dur_unlab > reco2dur_doc

# construct transcriptions for _doc partition
cut -d ':' -f 2 bn2docx_toprank |
  tr '\n' '\0' |
  xargs -I{} -0 "$local/doc_to_text.sh" "{}" |
  paste -d ' ' <(cut -d ' ' -f 1 segments_doc) - |
  perl -CS -n "$local/sanitize_text.pl" > text_doc

# make the rest of the files for _doc
cut -d ' ' -f 1 text_doc > doc.uttlist
join doc.uttlist utt2spk_unlab > utt2spk_doc
join doc.uttlist segments_unlab > segments_doc

# make "core_collapsed" partition in which all segmented utterances are
# appended together
cp -f wav_core{,_collapsed}.scp
cp -f reco2dur_core{,_collapsed}
cp -f core{,_collapsed}.recolist
filter_scp.pl -f 2 core_collapsed.recolist segments_unlab \
  > segments_core_collapsed
cut -d ' ' -f 1 segments_core_collapsed > core_collapsed.uttlist
sed 's/-[0-9]-[0-9]*-[0-9]*//' text_core | \
  awk -F ' ' -f "$local/combine_colon_delimited_duplicates.awk" | \
  cut -d ' ' -f 2- | \
  paste -d ' ' core_collapsed.uttlist - > text_core_collapsed
join core_collapsed.uttlist utt2spk_unlab > utt2spk_core_collapsed

# rough partition = core_collapsed + doc
cat {doc,core_collapsed}.recolist | sort -u > rough.recolist
join rough.recolist wav_unlab.scp > wav_rough.scp
join rough.recolist reco2dur_unlab > reco2dur_rough
cat {doc,core_collapsed}.uttlist | sort -u > rough.uttlist
join rough.uttlist segments_unlab > segments_rough
join rough.uttlist utt2spk_unlab > utt2spk_rough
cat text_{doc,core_collapsed} | sort -k 1,1 -s -u > text_rough

# build LM
cut -d ' ' -f 2- text_rough | \
 "$local/ngram_lm.py" -o 1 --word-delim-expr " " | \
 gzip -c > "lm.tri-noprune.gz"
