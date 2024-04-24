#!/usr/bin/env -S perl -CS -p

# see word_to_phoneme.pl to explain most of this

# this might be wrong. SPN could refer to, e.g., [fp]. To resolve this,
# one'd have to consult the original utterance. Too much effort
s/ SPN$/ [x]/;

s/_h$/\N{U+02B0}/;

tr/N@OEgG/\N{U+014B}\N{U+0259}\N{U+0254}\N{U+025B}\N{U+0261}\N{U+0263}/;
tr/IJSULZ/\N{U+026A}\N{U+0272}\N{U+0283}\N{U+028A}\N{U+028E}\N{U+0292}/;
tr/:/\N{U+02D0}/;
