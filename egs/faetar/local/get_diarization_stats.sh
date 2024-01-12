#!/usr/bin/env bash

. ./path.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 diarized_w_text_dir"
  exit 1
fi

set -eo pipefail

if [ ! -d "$1" ]; then
  echo "$0: '$1' is not a directory"
  exit 1
fi

function get_stats () {

    file="$1"
    filename="$(basename "$file" _text_with_speaker)"
    speaker_list="$(awk '{print $3}' "$file" | sort -u)"
    total_time="$(awk '{s += $2 - $1} END {print s}' "$file")"
    unsure_time=0
    sure_time=0

    echo "$filename stats"
    echo "Time covered by all utterances: $total_time"
    while read -r speaker; do
        speaker_time="$(grep "$speaker" "$file" | awk '{s += $2 - $1} END {print s}')"
        echo "Time covered by '$speaker' tier: $speaker_time"
        echo "Percent (of total time) covered by '$speaker' tier: $(percentize $speaker_time $total_time)"
        if [[ "$speaker" == "no_speaker" || "$speaker" == "ambiguous_speaker" || "$speaker" == "multiple_utterances" ]]; then
            unsure_time="$(bc -l <<< "$unsure_time + $speaker_time")"
        else
            sure_time="$(bc -l <<< "$sure_time + $speaker_time")"
        fi
    done <<< "$speaker_list"
    echo ""
    echo "Time covered by known speakers: $sure_time"
    echo "Percent (of total time) covered by known speakers: $(percentize $sure_time $total_time)"
    echo "Time covered by unknown speakers: $unsure_time"
    echo "Percent (of total time) covered by unknown speakers: $(percentize $unsure_time $total_time)"
    echo "__________________________________________________________________________"

}

function extract_stats () {

    pattern="$1"

    echo "$(grep -F "$pattern" "$stats_file" | awk 'BEGIN {FS=":"} {s+=$2} END {print s}')"

}

function percentize () {
    proportion="$1"
    total="$2"

    echo "$(bc -l <<< "$proportion * 100 / $total" | awk '{printf "%.2f\n", $0}')%"
}

function get_overall () {
    overall_time="$(extract_stats "Time covered by all utterances")"
    overall_known="$(extract_stats "Time covered by known speakers")"
    overall_unknown="$(extract_stats "Time covered by unknown speakers")"
    overall_nsp="$(extract_stats "Time covered by 'no_speaker'")"
    overall_asp="$(extract_stats "Time covered by 'ambiguous_speaker'")"
    overall_mut="$(extract_stats "Time covered by 'multiple_utterances'")"

    echo "**************************************************************************"
    echo "overall stats"
    echo "Time covered across all files by all utterances: $overall_time"
    echo "Time covered across all files by known speakers: $overall_known"
    echo "Percent (of total time across all files) covered by known speakers: $(percentize $overall_known $overall_time)"
    echo "Time covered across all files by unknown speakers: $overall_unknown"
    echo "Percent (of total time across all files) covered by unknown speakers: $(percentize $overall_unknown $overall_time)"

    echo ""
    echo "detailed unknown speaker stats"
    echo "Time covered across all files by 'no_speaker': $overall_nsp"
    echo "Percent (of total time across all files) covered by 'no_speaker': $(percentize $overall_nsp $overall_time)" 
    echo "Time covered across all files by 'ambiguous_speaker': $overall_asp"
    echo "Percent (of total time across all files) covered by 'ambiguous_speaker': $(percentize $overall_asp $overall_time)" 
    echo "Time covered across all files by 'multiple_utterances': $overall_mut"
    echo "Percent (of total time across all files) covered by 'multiple_utterances': $(percentize $overall_mut $overall_time)"
    echo ""
    echo "Percent (of total time covered by unknown speakers across all files) covered by 'no_speaker': $(percentize $overall_nsp $overall_unknown)"
    echo "Percent (of total time covered by unknown speakers across all files) covered by 'ambiguous_speaker': $(percentize $overall_asp $overall_unknown)"
    echo "Percent (of total time covered by unknown speakers across all files) covered by 'multiple_utterances': $(percentize $overall_mut $overall_unknown)"
    echo "**************************************************************************"
}

export -f get_stats
export -f percentize

dir="$1"
stats_file="$dir"/stats

echo -n "" > "$stats_file"

find "$dir" -name "*_with_speaker" |
    sort |
    tr '\n' '\0' |
    xargs -I{} -0 bash -c 'get_stats "$1"' -- {} >> "$stats_file"

get_overall >> "$stats_file"