#! /usr/bin/env bash

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 dict-suffix"
  exit 1
fi

. ./path.sh

set -eo pipefail

echo "$0 $@"

# run this from ../
dict_suffix="$1"

dir=data/local/dict${dict_suffix}
mkdir -p $dir
rm -rf "$dir/"*

# get word list without specials (called "silences")
cat data/local/data/text${dict_suffix} | \
  cut -d ' ' -f 2- | \
  tr ' ' '\n' | sort -u | sed '/^ *$/d; /^\[/d' > "$dir/words.txt"

# make lexicon without specials
cat "$dir/words.txt" | \
  perl -CS -p local/word_to_phoneme.pl | \
  paste -d $'\t' "$dir/words.txt" - > "$dir/lexicon_nosil.txt"

# determine non-special (not "silent") phones
cat "$dir/lexicon_nosil.txt" | \
  cut -d $'\t' -f 2 | \
  tr ' ' '\n' | \
  sort -u | \
  sed '/^ *$/d' > "$dir/nonsilence_phones.txt"

cat <(echo $'[fp] SPN\n[x] SPN') "$dir/lexicon_nosil.txt" \
  > "$dir/lexicon.txt"

# "silent" phones. Optional silence is the actual silence
echo $'SIL\nSPN\nNSN' > $dir/silence_phones.txt
echo SIL > $dir/optional_silence.txt

# in addition to asking questions about the type of "silence", we'll also ask
# questions of any modifiers (i.e. aspirants _h or geminates :)
cat "$dir/nonsilence_phones.txt" | perl -CS -e '
print "SIL SPN NSN\n";
my ($last_ph, $last_qn, $count) = ("", "", 0);
while (my $line = <STDIN>) {
  chomp($line);
  my ($ph) = ($line =~ /^([^:_]+)/);
  if ($ph eq $last_ph) {
    $last_qn .= " $line";
    $count++;
  } else {
    print "$last_qn\n" if ($count > 1);
    ($last_ph, $last_qn, $count) = ($ph, $line, 1);
  }
}
print "$last_qn\n" if ($count > 1); 
' > "$dir/extra_questions.txt"
