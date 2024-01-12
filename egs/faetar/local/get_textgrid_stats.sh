#!/usr/bin/env bash

# this script requires data/local/data/reco2dur_unlab and data/local/data/text_rough 
# to exist to determine recording lengths and number of words per transcript

# this script is also dependent on textgrids existing for both he and hl
# textgrid files must have lf as line endings not crlf

. ./path.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 textgrid_dir"
  exit 1
fi

set -eo pipefail

if [ ! -d "$1" ]; then
  echo "$0: '$1' is not a directory"
  exit 1
fi

dir="$1"

stats_dir="$(pwd -P)/astats"
mkdir -p "$stats_dir"


function compile_doc () {
    he_rec_length="$(grep 'he' data/local/data/reco2dur_unlab | awk '{s+=$2} END {print s}')"
    hl_rec_length="$(grep 'hl' data/local/data/reco2dur_unlab | awk '{s+=$2} END {print s}')"
    corpus_rec_length="$(bc <<< $he_rec_length+$hl_rec_length)"

    he_vad_length="$(awk 'NR % 5 == 2 {s+=$0} END {print s}' $stats_dir/length_he_stats)"
    hl_vad_length="$(awk 'NR % 5 == 2 {s+=$0} END {print s}' $stats_dir/length_hl_stats)"
    corpus_vad_length="$(bc <<< $he_vad_length+$hl_vad_length)"

    he_utt_length="$(awk 'NR % 5 == 3 {s+=$0} END {print s}' $stats_dir/length_he_stats)"
    hl_utt_length="$(awk 'NR % 5 == 3 {s+=$0} END {print s}' $stats_dir/length_hl_stats)"
    corpus_utt_length="$(bc <<< $he_utt_length+$hl_utt_length)"

    textgrid_stats_file="$stats_dir/textgrid_stats"
    transcript_stats_file="$stats_dir/transcript_stats"

    get_text_stats "$textgrid_stats_file" "$transcript_stats_file"

    # must be defined after get_text_stats has run
    nonempty_textgrids=$(< "$stats_dir/nonempty_textgrids_num")

    echo "Heritage length stats:"
    echo "Total rec length for he: $he_rec_length seconds / "$(convert_sec_to_hms "$he_rec_length")""
    echo "Total utt length for he (excluding blank intervals): $he_utt_length seconds / "$(convert_sec_to_hms "$he_utt_length")""
    echo "Total vad length for he: $he_vad_length seconds / "$(convert_sec_to_hms "$he_vad_length")""
    echo "______________________________________________________________________________"
    echo "Homeland length stats:"
    echo "Total rec length for hl: $hl_rec_length seconds / "$(convert_sec_to_hms "$hl_rec_length")""
    echo "Total utt length for hl (excluding blank intervals): $hl_utt_length seconds  / "$(convert_sec_to_hms "$hl_utt_length")""
    echo "Total vad length for hl: $hl_vad_length seconds / "$(convert_sec_to_hms "$hl_vad_length")""
    echo "______________________________________________________________________________"
    echo "Corpus length stats:"
    echo "Total rec length for the corpus: $corpus_rec_length seconds / "$(convert_sec_to_hms "$corpus_rec_length")""
    echo "Total utt length for the corpus (excluding blank intervals): $corpus_utt_length seconds / "$(convert_sec_to_hms "$corpus_utt_length")""
    echo "Total vad length for the corpus: $corpus_vad_length seconds / "$(convert_sec_to_hms "$corpus_vad_length")""
    echo "______________________________________________________________________________"
    echo "Textgrid and transcript stats:"
    echo "Number of textgrids with non-empty utt tiers: $nonempty_textgrids"
    echo "(search for : 0.00% to find ids for nonexistent / utt-less textgrids)"
    echo ""
    echo "$(paste -d '\n' "$textgrid_stats_file" "$transcript_stats_file" |
    awk \
    'BEGIN {
        grid_words = 0;
        transcript_words = 0;
        percent = 0;
        name = "";
    }
    
    NR % 2 == 1 {
        grid_words = $NF;
        # this is dependent on the filename being the second last word in each line in textgrid_stats_file
        name = $(NF - 2);
        print $0;
    }

    NR % 2 == 0 {
        transcript_words = $NF;
        print $0;

        percent = sprintf("%.2f", grid_words * 100 / transcript_words);
        printf "Percentage of words retained by textgrid for %s: %s%%\n\n", name, percent;
    }')"
    echo "______________________________________________________________________________"
    echo "Word level stats:"
    echo "***"
    echo "Word frequencies (over entire corpus): (ctrl+f for three asterisks to skip this section)"
    echo "$(awk \
    'BEGIN {
        text = "";
    }

    NR % 5 == 0 {
        text = text $0
    }
    
    END {
        text_len = split(text, a);

        for (i = 1; i <= text_len; i++) {
            words[a[i]]++;
        }

        for (word in words) {
            print word "\t" words[word];
        }

    }' $stats_dir/length_he_stats $stats_dir/length_hl_stats | sort -k 2,2 -rn )"
    echo "***"
    echo "(ctrl+f for three asterisks to jump to top of the word frequencies section)"

}

function convert_sec_to_hms () {
    total_seconds="$1"
    num_hours="$(bc <<< "$total_seconds / 3600")" 
    num_minutes="$(bc <<< "($total_seconds - ($num_hours * 3600)) / 60" | awk '{($0 >= 10) ? out = $0 : out = "0" $0; print out}')"
    num_seconds="$(bc <<< "($total_seconds - (($num_hours * 3600) + ($num_minutes * 60)))" | awk '{($0 >= 10) ? out = $0 : out = "0" $0; print out}')"
    echo -n "${num_hours}:${num_minutes}:${num_seconds}"
}

function get_file_stats () {

    textgrid="$1"
    filename="$(basename "$1" .TextGrid)"
    # line 7 of a TextGrid file contains the number of tiers as "size = x"
    # since each speaker has a phones, utts, and vad tier, we divide the number of tiers by 3
    speakers="$(("$(sed '7q;d' $textgrid | sed 's/[^0-9]*//g')" / 3))"
    # wipes the stats files
    out="$stats_dir/${filename}_stats"
    echo -n "" > "$out"

    for i in $(seq 1 $speakers); do
            # this is the vad tier for each speaker
            vad_tier=$(bc <<< "$i * 3")
            
            if [[ $i -ne $speakers ]]; then
                # gets lines between "item [vad_tier]:" and "item [vad_tier + 1]:" in the textgrid
                vad_tier_text="$(sed -n '/[ ]*item \['"$vad_tier"'\]:/,/[ ]*item \['"$(($vad_tier + 1))"'\]:/p' "$textgrid")"
            else
                # gets lines between "item [vad_tier]:" and the end of the file
                vad_tier_text="$(sed -n '/[ ]*item \['"$vad_tier"'\]:/,$p' "$textgrid")"
            fi
        
            sed '1,6d;$d' <<< "$vad_tier_text" |
            # removes "xmin = ", "xmax = ", and "text = " from lines
            sed 's/.*= //g' |
            tr -d '"' >> "$out"
    done

        # counts length of vad intervals in file
    awk \
        'BEGIN {
            start = 0;
            end = 0;
            total = 0;
            text = "";
        } 
        
        NR % 4 == 1 {next;}
        
        NR % 4 == 2 {start = $0;}

        NR % 4 == 3 {end = $0;}

        NR % 4 == 0 {
            if (NF == 0) {next;}
            else {total += end - start;}
        }
        
        END {
            print total;
        }' "$out" > "${out}_"

        echo -n "" > "$out"

    for i in $(seq 0 $(($speakers - 1))); do
        utt_tier=$(bc <<< "$i * 3 + 2")
        # gets lines between "item [utt_tier]:" and "item [utt_tier + 1]:" in the textgrid
        sed -n '/[ ]*item \['"$utt_tier"'\]:/,/[ ]*item \['"$(($utt_tier + 1))"'\]:/p' "$textgrid" |
        sed '1,6d;$d' |
        # removes "xmin = ", "xmax = ", and "text = " from lines
        sed 's/.*= //g' |
        tr -d '"' >> "$out"
    done

    # counts length of utterances in file excluding intervals with blank text
    awk \
        'BEGIN {
            start = 0;
            end = 0;
            total = 0;
            text = "";
        } 
        
        NR % 4 == 1 {next;}
        
        NR % 4 == 2 {start = $0;}

        NR % 4 == 3 {end = $0;}

        NR % 4 == 0 {
            if (NF == 0) {
                next;
            }
            else {
                total += end - start;
                text = text $0 " ";
            }
        }
        
        END {
            text_len = split(text, a);

            print total;
            print text_len;
            print text;
            for (i = 1; i <= text_len; i++) {
                words[a[i]]++;
            }
            for (word in words) {
                print word "\t" words[word];
            }
        }' "$out" >> "${out}_"

        mv "$out"{_,}

}

# combines he and hl stats files (partition must be either "he" or "hl")
function collect_length_stats () {
    partition="$1"
    if [[ $partition != "he" && $partition != "hl" ]]; then
        echo "collect_stats only accepts \"he\" or \"hl\" as its argument."
        exit 1
    fi

    find "$stats_dir" -type f -name "${partition}*" ! -name "length_*_stats" |
    sort |
    tr '\n' '\0' |
    xargs -I{} -0 bash -c 'basename $1; head -q -n4 $1' -- "{}" > "$stats_dir/length_${partition}_stats"
}

function get_text_stats () {
    textgrid_out="$1"
    transcript_out="$2"

    awk \
    'FNR % 5 == 1 {
        split($0, a, "_");
        printf "Total number of words in %s_%s textgrid: ", a[1], a[2];
    }

    FNR % 5 == 4 {
        print $0
    }' "$stats_dir/length_he_stats" "$stats_dir/length_hl_stats" > "$textgrid_out"

    awk \
    '{
        split($1, a, "-");
        printf "Total number of words in %s transcript: ", a[1];
        total_words = split($0, b) - 1;
        print total_words
    }' data/local/data/text_rough > "$transcript_out"

    wc -l < "$textgrid_out" > "$stats_dir/nonempty_textgrids_num"

    if [[ $(wc -l < "$textgrid_out") -ne $(wc -l < "$transcript_out") ]]; then
        awk \
        'BEGIN {
            FS = ":"
        }
        
        NR == FNR {
            textgrid_filename_position = split($1, a, " ") - 1;
            file[a[textgrid_filename_position]] = $2;
            next;
        }
        
        {
            transcript_filename_position = split($1, b, " ") - 1;
            if (b[transcript_filename_position] in file) {
                print "Total number of words in " b[transcript_filename_position] " textgrid:" file[b[transcript_filename_position]]
            }
            else {
                print "Total number of words in " b[transcript_filename_position] " textgrid: 0"
            }
        }' "$textgrid_out" "$transcript_out" > "${textgrid_out}_"

        mv "$textgrid_out"{_,}
    fi

}

export -f get_file_stats
export stats_dir

find "$dir" -name "*.TextGrid" -print0 |
xargs -I{} -0 bash -c 'get_file_stats "$1"' -- {}

collect_length_stats "he"
collect_length_stats "hl"

compile_doc > "$stats_dir/zstats"
