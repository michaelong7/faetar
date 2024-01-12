#!/usr/bin/env bash

# extracts files with mappings, then
# renames files in hlvc to the format {hl,he}_w{0,1,...}(_t{0,1,...}) 
# (i.e. [homeland or heritage]_[wav number]_[transcript number])

nj=4

. utils/parse_options.sh

if [ $# -ne 2 ]; then
    echo "Usage: $0 [--nj N] mapping-file hlvc-root-data-dir"
    exit 1
fi

if [ ! -d "$2" ]; then
  echo "$0: '$2' is not a directory"
  exit 1
fi

dir="$(pwd -P)/data/local/corpus_data"

. ./path.sh

set -eo pipefail

# https://gist.github.com/hilbix/1ec361d00a8178ae8ea0
function relpath() {
    local X Y A
    # We can create dangling softlinks
    X="$(readlink -m -- "$1")" || return
    Y="$(readlink -m -- "$2")" || return
    X="${X%/}/"
    A=""
    # See http://stackoverflow.com/questions/2564634/bash-convert-absolute-path-into-relative-path-given-a-current-directory
    while   Y="${Y%/*}"
            [ ".${X#"$Y"/}" = ".$X" ]
    do
            A="../$A"
    done
    X="$A${X#"$Y"/}"
    X="${X%/}"
    echo "${X:-.}"
}

# assigns filecodes linking transcriptions with the same wav to that wav
function rename () {

    awk -v partition=$partition \
    'BEGIN {
    wavnum=0;
    transcriptnum=0;
    }

    {
    if (/.*\.wav/) {
        wavnum++;
        transcriptnum=0;
        }
    else {
        transcriptnum++
        }

    printf $0 partition "_w" "%.3d", wavnum;

    if (! /.*\.wav/) {
        printf "_t" "%.2d", transcriptnum

        if (/.*\.eaf/) {
            printf ".eaf\n"
            }
        else if (/.*\.docx/) {
            printf ".docx\n"
            }

        }
    else
        {printf ".wav\n"}

    }'
}

# copied from old hlvc_faetar_data_prep script
function get_old_bn2x_homeland () {

    fh_dir="$(find "$1" -name 'Speaker_catalog_2019.xls' -print0 | xargs -I{} -0 bash -c 'cd "$(dirname "$1")"; pwd -P' -- "{}")"
    mappings="$(pwd -P)/mappings"
    local="$(pwd -P)/local"
    mkdir -p "$dir"

    pushd "$dir"

    # find all unique files of various types
    # (we add a guard to avoid regenerating if we've already completed it once - very slow)
    for x in eaf wav; do
        if [ ! -f "old_${x}list_hl" ]; then
            find "$fh_dir" -name "*.$x" -and -not -name '._*' -print |
            grep -vi 'prodrop\|laura\|rick\|final deletion\|faetar data from 09\|problematic\|\$~' |
            tr '\n' '\0' |
            xargs -I {} -P $nj -0 rhash -p '%{crc32}:%p\n' {} |
            sort -t ':' |
            sort -t ':' -k 1,1 -us |
            cut -d ':' -f 2 |
            sort > "old_${x}list_hl_"
            mv "old_${x}list_hl"{_,}
        fi
    done

    # generate list of docx files according to directory ranking
    cat "$mappings"/docx_ranking.txt |
        tr '\n' '\0' |
        xargs -0 -i find "$fh_dir"/{} -maxdepth 1 -name '*.docx' > old_docxlist_ranked_hl

    # make docx mapping based on spreadsheet
    "$local/sheet_to_mapping.sh" "$sheet" docx old_docxlist_ranked_hl > old_bn2docx_hl

    # map eaf-basename-to-eaf as well as stored-wav-basename-to-eaf
    "$local/sheet_to_mapping.sh" "$sheet" eaf old_eaflist_hl > old_bn2eaf_hl

    # find all the files with that suffix in the directory and store them in bn2{x}_dups
    #
    # bn2x_dups is of the format
    #   <x basename minus '.x'>:<path1>[:<path2>[...]]
    # the weird choice of delimiters is b/c there are commas, spaces, ampersands,
    # etc. in filenames
    cat old_wavlist_hl | tr '\n' '\0' | \
        xargs -I{} -0 bash -c 'v="$(basename "$1")"; echo "${v%%.wav}:$1"' -- {} | \
        sort -t ':' -k 1,1 | awk -F ':' -f "$local/combine_colon_delimited_duplicates.awk" > old_bn2wav_dups_hl

    # delete duplicates by choosing the last modified
    cat old_bn2wav_dups_hl | cut -d ':' -f 2- | tr '\n' '\0' | \
        xargs -I{} -0 bash -c 'IFS=: read -ra v <<< "$1"; newest="${v[0]}"; for f in "${v[@]}"; do [ "$f" -nt "$newest" ] && newest="$f"; done; echo "$newest"' -- "{}" | \
        paste -d ':' <(cut -d ':' -f 1 old_bn2wav_dups_hl) - > old_bn2wav_hl

    popd

}

function get_old_bn2x_heritage () {

    fh_dir="$1/FAETAR (Heritage)"
    local="$(pwd -P)/local"
    mkdir -p "$dir"

    pushd "$dir"

    # find all unique wav files
    # (we add a guard to avoid regenerating if we've already completed it once - very slow)
    if [ ! -f "old_wavlist_he" ]; then
        find "$fh_dir" -name "*.wav" -and -not -name '._*' -print |
        grep -vi 'prodrop\|laura\|rick\|final deletion\|faetar data from 09\|problematic\|\$~' |
        tr '\n' '\0' |
        xargs -I {} -P$nj -0 rhash -p '%{crc32}:%p\n' {} |
        sort -t ':' |
        sort -t ':' -k 1,1 -us |
        cut -d ':' -f 2 |
        sort > "old_wavlist_he_"
        mv old_wavlist_he{_,}
    fi

    # generate list of eaf files from files in the Finished Transcriptions folder
    find "$fh_dir/Finished Transcriptions" -maxdepth 1 -name '*.eaf' > old_eaflist_he

    # make eaf mapping based on spreadsheet
    "$local/sheet_to_mapping.sh" "$sheet" eaf old_eaflist_he > old_bn2eaf_he

    # find all the files with that suffix in the directory and store them in bn2{x}_dups
    #
    # bn2x_dups is of the format
    #   <x basename minus '.x'>:<path1>[:<path2>[...]]
    # the weird choice of delimiters is b/c there are commas, spaces, ampersands,
    # etc. in filenames
    cat old_wavlist_he | tr '\n' '\0' | \
        xargs -I{} -0 bash -c 'v="$(basename "$1")"; echo "${v%%.wav}:$1"' -- {} | \
        sort -t ':' -k 1,1 | awk -F ':' -f "$local/combine_colon_delimited_duplicates.awk" > old_bn2wav_dups_he

    # delete duplicates by choosing the last modified
    cat old_bn2wav_dups_he | cut -d ':' -f 2- | tr '\n' '\0' | \
        xargs -I{} -0 bash -c 'IFS=: read -ra v <<< "$1"; newest="${v[0]}"; for f in "${v[@]}"; do [ "$f" -nt "$newest" ] && newest="$f"; done; echo "$newest"' -- "{}" | \
        paste -d ':' <(cut -d ':' -f 1 old_bn2wav_dups_he) - > old_bn2wav_he

    popd
    
}

# merges bn2x files and extracts paths
function find_paths () {

    if [[ $partition == "hl" ]]; then
        files="$dir/old_bn2docx_hl $dir/old_bn2eaf_hl $dir/old_bn2wav_hl"
    elif [[ $partition == "he" ]]; then
        files="$dir/old_bn2eaf_he $dir/old_bn2wav_he"
    fi

    awk \
    'BEGIN {
        FS=":";
    }

    {
        for (i=2;i<=NF;i++) {
            basename=gensub(/[^\t\n]*\//, "", "g", $i)
            printf basename "\t" $i "\n"
        }
    }' \
    $files 

}

# replaces basenames with paths
function attach_paths () {

    awk \
    'BEGIN {
        FS="\t"
    }
    
    NR == FNR {
    path[$1]=$2;
    next;
    }

    {
        if ($1 in path) {
            printf path[$1] "\t" $2 "\n"
        }
    }' $dir/old_bn2file_${partition} -
}

function delete_transcriptionless_wavs () {
    awk 'BEGIN {
        last=".wav"
    }

    ! /.*\.wav/ || last !~ /.*\.wav/ {
         printf last "\n";
    }

    {
        last=$0;
    }

    END {
        if (last !~ /.*\.wav/) {
            printf last "\n";
        }
    }' $dir/file2newbn_${partition}
}

function make_new_corpus () {

    lines=$(wc -l < $1)

    ddir="$cleaned/$partition"
    manifest="$ddir/manifest.tsv"
    rm -rf "$ddir"
    mkdir -p "$ddir"
    rm -f "$manifest"
    echo -e "Original file path\tcleaned corpus filename" | tee -a "$manifest"

    for ((i=1;i<=$lines;i++)); do
        filesource=$(awk -v line=$i 'BEGIN {FS="\t"} NR==line{print $1}' "$1")
        filename=$(awk -v line=$i 'BEGIN {FS="\t"} NR==line{print $2}' "$1")
        filedest="$ddir/$filename"
        echo -e "$(relpath "$filesource" "$hlvc_dir")\t$filename" | tee -a "$manifest"
        if [[ "$filename" == *.wav ]]; then
            "local/fix_wav_length.py" "$filesource" "$filedest"
        elif [[ "$filename" == *.eaf ]]; then
            "local/link_wav_to_eaf.py" "${filesource}" "${filedest%_t*}.wav" "$filedest"
        else
            cp "$filesource" "$filedest"
        fi
    done

}

sheet="$(cd $(dirname "$1"); pwd -P)/$(basename "$1")"
hlvc_dir="$(cd "$2"; pwd -P)"
if [ -z "$3" ]; then
    cleaned="$(cd "$hlvc_dir/.."; pwd -P)/HLVC_cleaned/faetar"
else
    cleaned="$3"
fi


if [[ $sheet == */wav_mapping_homeland.txt ]]; then
    partition="hl"
    columns="1,2,4"
    get_old_bn2x_homeland "$hlvc_dir"
elif [[ $sheet == */wav_mapping_heritage.txt ]]; then
    partition="he"
    columns="1,2"
    get_old_bn2x_heritage "$hlvc_dir"
else
    echo "Incorrect mapping sheet. Use wav_mapping_homeland.txt or wav_mapping_heritage.txt"
    exit 1
fi

find_paths > $dir/old_bn2file_${partition}

# deletes first row of mapping spreadsheet
sed '1 d' < "$sheet" |
# turns tabs into colons
tr '\t' ':' |
# turns newlines in quotes into tabs
perl -pe 's/\n$/\t/ if $v ^= tr/"/"/ % 2;' |
# takes wav, eaf, and docx columns (homeland)
# takes wav and eaf columns (heritage)
cut -d ":" -f $columns | 
# removes quotes
tr -d '"' |
tee $dir/sheet_${partition} |
# turns file into a list separated by newlines
tr ':' '\n' |
tr '\t' '\n' |
# deletes all empty lines
grep -v "^$" |
attach_paths |
rename > $dir/file2newbn_${partition}
# delete_transcriptionless_wavs > data/local/corpus_data/file2newbn_${partition}_
# mv data/local/corpus_data/file2newbn_${partition}{_,}

# double-check that, if a wav file is supposed to be mapped to an eaf or docx,
# at least one such resource exists in file2newbn. I've come across a few
# accidental spaces in the mapping file which might cause this
perl -se '
use File::Basename;

my %bns;
open(my $fh, "<", $file2newbn)
    or die "Cannot open $file2newbn: $!";
while (my $line = readline($fh)) {
    chomp $line;
    my ($file, $nn) = split /\t/, $line;
    my $bn = basename($file);
    $bns{$bn} = 1;
}
close($fh);

open($fh, "<", $sheet)
    or die "Cannot open $sheet: $!";
while (my $line = readline($fh)) {
    chomp $line;
    my @cols = split /:/, $line;
    my $wav = shift @cols;
    # FIXME(sdrobert): do we have redundant entries?
    (exists $bns{$wav}) or die "$wav has no entry in $file2newbn";
    foreach my $col ( @cols ) {
        chomp $col;
        my @cands = split /\t/, $col;
        next unless @cands;
        my $found = 0;
        foreach my $cand ( @cands ) {
            if (exists $bns{$cand}) {
                $found = 1;
                break;
            }
        }
        die "Could not find any of <$col> (for <$wav>) in $file2newbn"
            unless $found;
    }
}
' -- -file2newbn=$dir/file2newbn_${partition} -sheet=$dir/sheet_${partition}

make_new_corpus $(readlink -f data/local/corpus_data/file2newbn_${partition})