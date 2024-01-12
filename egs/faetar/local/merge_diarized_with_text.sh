#!/usr/bin/env bash

# this script is dependent on the files in diarized_dir and textgrid_dir having the same basenames 
# which match the basename of the sound file

local="$(dirname "$0")"
# if diarization for all speakers covers less than this proportion of the utterance,
# the utterance is assigned to 'no speaker'
coverage_threshold=0.7
# if the ratio 
# amount of utterance covered by main speaker / amount of utterance covered by all other speakers
# is less than this, the utterance is assigned to 'ambiguous speaker'
ambiguity_threshold="$(bc -l <<< '7/3')"
# if the length of another speaker's coverage during an utterance surpasses this threshold,
# the utterance is assigned to 'multiple utterances'
absolute_threshold=1
out_dir="$(pwd -P)/diarized_textgrids"
text_dir="$(pwd -P)/diarized_with_text"

. ./path.sh

. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "Usage: $0 diarized_dir textgrid_dir"
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

diarized_dir="$1"
textgrid_dir="$2"

mkdir -p "$out_dir"
mkdir -p "$text_dir"

# necessary for the textgrid to be displayed properly
# also removes intervals where the start and end are the same (which causes problems with textgrid display)
function add_blank_intervals() {
    original_intervals="$1"

    awk -v duration="$duration" -v orig_intervals_num="$(wc -l <<< "$original_intervals")"\
    'BEGIN {
        old_end = 0;
        OFS = "\t"
    }

    # adds a blank interval to the start if the first interval does not start at 0
    NR == 1 && ($1 > 0) {
        print "0", $1, "blank";
    }

    # adds a blank interval if the start of the current interval does not
    # coincide with the end of the previous one
    NR != 1 && old_end != $1 {
        print old_end, $1, "blank";
    }
    
    # only executes when the start and end of the current interval are not the same
    $1 != $2 {
        print $0;
    }

    NR == orig_intervals_num && $2 < duration {
        print $2, duration, "blank";
    }
    
    {
        old_end = $2;
    }' <<< "$original_intervals"
}

function get_duration() {
    filename=$(basename "$1")
    awk -v filename=$filename \
    '$1 == filename {print $2}' data/local/data/reco2dur_unlab
}

function make_tier() {
    speaker="$1"
    original_intervals="$(grep -w "$speaker" "$file")"

    new_intervals="$(add_blank_intervals "$original_intervals")"

    echo -e "\t\tclass = \"IntervalTier\""
    echo -e "\t\tname = \"$(tr '_' ' ' <<< $speaker | tr [:upper:] [:lower:])\""
    echo -e "\t\txmin = 0"
    echo -e "\t\txmax = $duration"
    echo -e "\t\tintervals: size = $(wc -l <<< "$new_intervals")"

    awk \
    'BEGIN {
        FS = "\t";
        utt_text = ""
    }
    
    {
        print "\t\tintervals [" NR "]:";
        print "\t\t\txmin = " $1; 
        print "\t\t\txmax = " $2;
        if ($3 == "blank") {
            print "\t\t\ttext = \"\"";
        }
        else {
            utt_text = $4;
            print "\t\t\ttext = " utt_text;
            utt_text = "";
        }
    }' <<< "$new_intervals"

}

function make_textgrid () {
    file="$1"

    duration="$(get_duration "$(basename "$file" "$speaker_and_phone_suffix")")"
    speaker_list="$(awk '{print $3}' "$file" | sort -u)"
    speaker_num="$(wc -l <<< "$speaker_list")"

    echo "File type = \"ooTextFile\""
    echo "Object class = \"TextGrid\""
    echo ""
    echo "xmin = 0"
    echo "xmax = $duration"
    echo "tiers? <exists>"
    echo "size = $speaker_num"
    echo "item []:"

    item_num=0

    while read -r speaker; do
        echo -e "\titem [$((++item_num))]:"
        make_tier "$speaker"
    done <<< "$speaker_list"

}

function get_tier () {

    textgrid="$1"
    tier_name="$2"

    if [[ $tier_name == "phone" ]]; then
        tier=1
    elif [[ $tier_name == "utt" ]]; then
        tier=2
    else
        echo "the tier name must be 'phone' or 'utt'"
        exit 1
    fi

    filename="$(basename "$textgrid" .TextGrid)"
    # line 7 of a TextGrid file contains the number of tiers as "size = x"
    # since each speaker has a phones, utts, and vad tier, we divide the number of tiers by 3
    speakers="$(("$(sed '7q;d' $textgrid | sed 's/[^0-9]*//g')" / 3))"
    # wipes the text files
    out="$text_dir/${filename}_text_${tier_name}"
    echo -n "" > "$out"

    for i in $(seq 0 $(($speakers - 1))); do
        tier_code=$(bc <<< "$i * 3 + $tier")
        # gets lines between "item [utt_tier]:" and "item [utt_tier + 1]:" in the textgrid
        sed -n '/[ ]*item \['"$tier_code"'\]:/,/[ ]*item \['"$(($tier_code + 1))"'\]:/p' "$textgrid" |
        sed '1,6d;$d' |
        # removes "xmin = ", "xmax = ", and "text = " from lines
        sed 's/.*= //g' |
        # removes trailing spaces
        awk '{sub(/ +$/, ""); print}' |
        # removes the "intervals [n]:" lines and prints the interval on one line
        awk \
        'NR % 4 != 1 {
            if (NR % 4 != 0) {
                printf "%.2f%s", $0, "\t";
            } 
            else {
                print $0;
            }
        }' |
        # removes any lines with no text in interval
        awk '$3 != "\"\""' >> "$out"
    done

}

function assign_speaker() {

    file="$1"

    filename="$(basename "$file")"
    text="$text_dir/${filename}_text_utt"

    if [ ! -f "$text" ]; then
        echo "Missing textfile for $filename"
        exit 1
    fi

    cmd='python '"$local"'/assign_speaker.py "$1" "$2" "$3" "$4" "$5"'

    bash -c "$cmd" -- "$file" "$text" "$coverage_threshold" "$ambiguity_threshold" "$absolute_threshold" 

}

function assign_phones() {

    textgrid_file="$1"
    diarized_file="$2"
    filename="$(basename "$textgrid_file" .TextGrid)"
    known_speaker_list="$(grep -vf <(echo -e "no_speaker\nambiguous_speaker\nmultiple_utterances") "$file" | awk '{print $3}' | sort -u)"

    get_tier "$textgrid_file" "phone"
    text="$text_dir/${filename}_text_phone"

    while read -r speaker; do
        awk -v speaker="$speaker" \
        'BEGIN {
            OFS = "\t"
        }
        
        NR == FNR && $3 == speaker {
            # the system used for assigning keys to utt_intervals only needs each interval to have a distinct key
            utt_interval_starts[NR] = $1;
            utt_interval_ends[NR] = $2;
            print $0;
        }
        
        NR != FNR {
            for (utt in utt_interval_starts) {
                if (utt_interval_starts[utt] <= $1 && $2 <= utt_interval_ends[utt]) {
                    print $1, $2, speaker "_phones", $3;
                    next;
                }
            }
        }' "$diarized_file" "$text" |
        sort -k 1,1 -n
    done <<< "$known_speaker_list"

}

export -f get_tier
export text_dir

find "$textgrid_dir" -name "*.TextGrid" -print0 |
xargs -I{} -0 bash -c 'get_tier "$1" "utt"' -- {}

speaker_suffix="_text_with_speaker"
speaker_and_phone_suffix="_text_with_pands"

for file in "$diarized_dir"/*; do
    # local/diarize.py creates empty files while it's working, so we check for content
    # so that we can run this while running diarize.py
    if [ -s "$file" ]; then 
        assign_speaker "$file" > "$text_dir/$(basename "$file")$speaker_suffix"
        assign_phones "$textgrid_dir/$(basename "$file").TextGrid" "$text_dir/$(basename "$file")$speaker_suffix" \
        > "$text_dir/$(basename "$file")$speaker_and_phone_suffix"

        { grep -f <(echo -e "no_speaker\nambiguous_speaker\nmultiple_utterances") "$diarized_file" || true; } >> "$text_dir/$(basename "$file")$speaker_and_phone_suffix"
        # make_textgrid requires the basename of $file to be present in the argument's basename
        make_textgrid "$text_dir/$(basename "$file")$speaker_and_phone_suffix" > "$out_dir/$(basename "$file").TextGrid"
    fi
done

