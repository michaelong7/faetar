#! /usr/bin/env bash

# Convert tab-separated mapping spreadsheet to colon-separated file mapping
# wav-basename to transcription-absolute-path.
# If the transcription type is EAF then each line may have multiple EAFs,
# separated by more colons.

if [ $# -ne 3 ]; then
    echo "Usage: $0 sheetfile ext extlist"
    exit 1
fi

sheetfile=$1
ext=$2
extlist=$3

# column number of the desired transcription file type in the spreadsheet
ext_fno=

max_mapped=-1
if [ "$ext" == "eaf" ]; then
    ext_fno=2
elif [ "$ext" == "doc" ]; then
    ext_fno=3
    max_mapped=1
elif [ "$ext" == "docx" ]; then
    ext_fno=4
    max_mapped=1
else
    echo "Unsupported extension: $ext"
    exit 1
fi

set -eo pipefail

cat "$sheetfile" |
    # Delete the header and carriage returns
    sed -e '1d' -e 's/\r//g' |
    # Turn newlines within quotation marks into colons
    perl -pe 's/\n$/:/ if $v ^= tr/"/"/ % 2;' |
    # Get only the first two columns
    cut -f 1,"$ext_fno" |
    # Remove leading/trailing whitespace
    sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' |
    # Keep only rows that have mappings
    grep $'\t' |
    # Remove all double quotes
    tr -d '"' |
    # Turn all tabs into colons
    tr '\t' ':' |
    # Remove .wav extensions
    sed 's/\.wav//' |
    # Replace file basenames with absolute paths from list of paths
    awk -F ':' -v "extlist=$extlist" -v "max_mapped=$max_mapped" $'{
        line=$1;
        m=0;
        for (i=2; i<=NF; i++) {
            paths=""
            cmd="grep -m " max_mapped " -F \'" $i "\' " extlist
            while (cmd | getline path) {
                if (m != max_mapped) {
                    paths=paths ":" path
                    m += 1
                }
            }
            close(cmd)
            line=line paths
            if (m == max_mapped) {
                break
            }
        }
        if (line != $1) {
            print line
        } else {
            print "Could not find any matching files for " $0 > /dev/stderr
            err=1
        }
    }
    END {exit err}' |
    sort -t ':' -k 1,1
