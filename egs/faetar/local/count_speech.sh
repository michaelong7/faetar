#! /usr/bin/env bash

if [ $# -ne 2 ] && [ $# -ne 3 ]; then
  echo "Usage: $0 path-to-ctm path-to-output-dir [path-to-corpus-text-file]"
  exit 1
fi

local="$(dirname "$0")"
. "$local/../path.sh"

ctm="$1"
out_d="$2"
out_f="$out_d/speech_count_$(basename "$ctm").csv"


if [ $# -eq 3 ]; then
  corpus_text_file="$3" # We retrieve the original word count from here. data/local/text_rough
fi

if [ ! -f "$ctm" ]; then
  echo "$0: File '$ctm' does not exist or is not a file"
  exit 1
fi

if [ ! -d "$out_d" ]; then
  mkdir -p "$out_d"
fi

speech_s=$(awk '{ print $4 }' "$ctm" | \
	python -c "import sys; s = sum(float(l) for l in sys.stdin); print(round(s, 2))")
speech_m=$(python -c "v = $speech_s / float(60); print(round(v, 2))")
speech_h=$(python -c "v = $speech_s / float(3600); print(round(v, 2))")
model_tokens=$(wc -l < "$ctm")
ctm_count_source="$(basename $(dirname $ctm))/$(basename $ctm)" # a la mono0/ctm

header="ctm_source_file,seconds,minutes,hours,ctm_word_tokens,orig_word_tokens,proportion_tokens_covered\n"
elsedata="$ctm_count_source,$speech_s,$speech_m,$speech_h,$model_tokens,N/A,N/A\n"

if [ ! -z "$corpus_text_file" ]; then
  if [ -f "$corpus_text_file" ]; then
    orig_tokens_n=$(cut -d ' ' -f 2- "$corpus_text_file" | \
      python -c "import sys; s = sum(len(l.split()) for l in sys.stdin); print(s)")
    prop=$(python -c "v = $model_tokens / $orig_tokens_n; print(round(v, 2))")
    out_data="$ctm_count_source,$speech_s,$speech_m,$speech_h,$model_tokens,$orig_tokens_n,$prop\n"
  else
    echo "$0: WARNING: File '$corpus_text_file' does not exist or is not a file"
    out_data=$elsedata
  fi
else
  out_data=$elsedata
fi

printf "$header" > "$out_f"
printf "$out_data" >> "$out_f"
