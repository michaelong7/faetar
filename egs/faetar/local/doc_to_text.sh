#! /usr/bin/env bash

set -eo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 path-to-doc-or-docx"
  exit 1
fi

local="$(dirname "$0")"
. "$local/../path.sh"

doc="$1"

if [ ! -f "$doc" ]; then
  echo "File '$doc' does not exist or is not a file"
  exit 1
fi

if [[ "$doc" =~ docx$ ]]; then
  # doc is docx file
  cmd='python '"$local"'/docx_to_text.py --map-folder '"$local/../conf"' "$1"'
else
  # doc is a win95 doc file
  cmd='antiword -m ipaphon -r "$1" | perl -CO '"$local/ipaphon_to_utf.pl"
fi

bash -c "$cmd" -- "$1" | \
  perl -CS $local/sanitize_doctext.pl
