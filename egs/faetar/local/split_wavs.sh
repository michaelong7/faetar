#!/usr/bin/env bash

# the diarized_with_text dir is assumed to only have files ending in _text_with_speaker, which can be generated 
# by running textgrid_to_tws.sh and using the output folder as the first argument

out_dir="audio_utterances"
test_dir="test"
train_dir="train"

. utils/parse_options.sh
. ./path.sh

if [ $# -ne 2 ]; then
  echo "Usage: $0 diarized_with_text_dir cleaned_corpus_dir"
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

function split_file () {
    file="$1"
    wav_name="$(basename "$file" _text_with_speaker)"
    wav_file="$(find "$audio_dir" -name "${wav_name}.wav")"
    utt_num=1

    # utterance consists of one line of the tws file in the format [start] [end] [speaker] [utterance text]
    while read -r utterance; do
        IFS=$'\t' read -ra utt_data <<< "$utterance"

        utt_start="${utt_data[0]}"
        utt_end="${utt_data[1]}"
        speaker_name="${utt_data[2]}"
        utt_text="$(tr -d '"' <<< "${utt_data[3]}")"

        subout_dir="$out_dir/$wav_name/$speaker_name"


        # filters utterances that don't have (known) speakers assigned to them
        if [[ "$speaker_name" != "no_speaker" && "$speaker_name" != "ambiguous_speaker" && "$speaker_name" != "multiple_utterances" && "$speaker_name" != *"T"* ]]; then
            mkdir -p "$subout_dir"
            audio_output="$subout_dir/$(sed 's/_w//' <<< ${wav_name})_$(tr -d "_" <<< ${speaker_name})_utt${utt_num}.wav"
            text_output="$subout_dir/$(sed 's/_w//' <<< ${wav_name})_$(tr -d "_" <<< ${speaker_name})_utt${utt_num}.txt"

            sox "$wav_file" "$audio_output" trim "$utt_start" ="$utt_end"
            echo "$utt_text" > "$text_output"
            ((utt_num++))
        fi

    done < "$file"
}

function partition_sets () {
    test_spks="heF005 heF006 heF007 heF008 heM005 heM006 heM007 hlM019 hlM021 hlM025 hlM028 hlM032 hlF010 hlF011 hlF014 hlF022 hlF025 hlF027"
    test_files="he014 he016 he018 he019 hl011 hl027 hl042 hl046 hl053 hl112 hl124 hl153 hl158 hl172"

    find "$out_dir" -type f |
    grep -vf <(tr ' ' '\n' <<< "$test_spks") "-" |
    xargs -I{} bash -c 'cp -R "$1" '"$train_dir"'' -- "{}"

    find "$out_dir" -type f |
    grep -f <(tr ' ' '\n' <<< "$test_spks") "-" |
    grep -f <(tr ' ' '\n' <<< "$test_files") "-" |
    xargs -I{} bash -c 'cp -R "$1" '"$test_dir"'' -- "{}"

}

segments_dir="$1"
audio_dir="$2"

mkdir -p "$out_dir"
mkdir -p "$test_dir"
mkdir -p "$train_dir"

for file in "$segments_dir"/*"_text_with_speaker"; do
    split_file "$file"
done

partition_sets