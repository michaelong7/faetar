#!/usr/bin/env -S perl -CS

use feature 'unicode_strings';

# sanitation specific to doc files

my $v = "";

while (<STDIN>) {
  chomp;  # remove leading/trailing space
  s/\[(?:V|NP|.?\N{U+0283})//g;  #removes the phrase markers NP, V, ʃ, and ɛʃ when appearing immediately after a left square bracket
  tr/[A-Z]/[a-z]/;
  s/\t*([^\t]+)\t.*$/\1/;  # remove everything after first block of text without tabs (speaker id and/or translation)
  s/^[^:]+: *//;  # remove first word preceding a colon
  s/\b(IV)\b//g;  # remove these words
  s/\(?[^\h\)]+\)//g; s/\(//g; # remove any parenthetical terms (possibly without matching brace)

  # Some weirdness. Looking at the "Symbol Table - IPAPhon.doc" docs, you'll
  # likely see a bunch of symbols mismatch with their descriptions -- even with
  # the correct font installed. For example, "Symbol Table - IPAPhon.doc" has
  # the entry
  # 
  # - Code: 171 (0XAB)
  # - Symbol: *looks like* ɥ
  # - Unicode name: latin small letter open e (i.e. ɛ)
  #
  # This mismatch is consistent with "Faetar font issues.pdf". However,
  # IPAPhon.fmap maps the code to the unicode name, not to the *visual* symbol.
  # That is, an ɛ may be intended, but instead of that, we might get the code
  # 180 (0XB4), corresponding to latin small letter turned h (i.e. ɥ).
  #
  # It's unclear why this is happening. Perhaps there was some optical
  # character recognition going on when converting doc -> docx? Regardless, if
  # one comes across a font issue, one should first check what unicode name the
  # problematic symbol matches up to in "Symbol Table - IPAPhon.doc" and make
  # the conversion from the symbol to the listed name. Here's one such
  tr/\N{LATIN SMALL LETTER N WITH RETROFLEX HOOK}/\N{LATIN SMALL LETTER OPEN O}/; # ɳ -> ɔ

  # from Michael, fixing the extensionless files
  tr/\N{REVERSE SOLIDUS}/\N{LATIN SMALL LETTER SCHWA}/;  # \ -> ə
  # specific mappings specified by Naomi in "Faetar font issues.pdf"
  # FIXME(sdrobert): These could go in docx_to_text.py, but I've found some of
  # the errors in one font transfer to another font. I suspect there's a bunch
  # of overlap
  # - Times New Roman (probably PalPhon or IPAPhon, actually)
  tr/\N{COPYRIGHT SIGN}/\N{LATIN SMALL LETTER GAMMA}/;  # © -> ɣ
  # - IPAPhon
  tr/\N{LATIN SMALL LETTER D WITH HOOK}/\N{LATIN LETTER SMALL CAPITAL I}/; # ɗ -> ɪ
  tr/\N{LATIN LETTER BILABIAL CLICK}/\N{LATIN SMALL LETTER ENG}/; # ʘ -> ŋ
  tr/\N{LATIN SMALL LETTER TURNED H}/\N{LATIN SMALL LETTER OPEN E}/; # ɥ -> ɛ
  tr/\N{LEFT DOUBLE QUOTATION MARK}/\N{LATIN SMALL LETTER TURNED Y}/; # “ -> ʎ
  tr/\N{LATIN SMALL LETTER S WITH HOOK}/\N{LATIN SMALL LETTER ESH}/; # ʂ -> ʃ
  # - PalPhon
  tr/\N{LATIN CAPITAL LETTER O WITH GRAVE}/\N{LATIN SMALL LETTER TURNED Y}/;  # Ò -> ʎ
  tr/\N{LATIN SMALL LETTER O WITH STROKE}/\N{LATIN SMALL LETTER OPEN O}/;  # ø -> ɔ
  tr/\N{LATIN SMALL LETTER SHARP S}/\N{LATIN SMALL LETTER ESH}/;  # ß -> ʃ
  tr/\N{ACUTE ACCENT}/\N{LATIN SMALL LETTER OPEN E}/;  # ´ -> ɛ
  tr/\N{SQUARE ROOT}/\N{LATIN SMALL LETTER TURNED V}/;  # √ -> ʌ
  tr/\N{GREEK CAPITAL LETTER OMEGA}/\N{LATIN SMALL LETTER EZH}/;  # Ω -> ʒ
  tr/\N{MODIFIER LETTER CIRCUMFLEX ACCENT}/\N{LATIN LETTER SMALL CAPITAL I}/;  # ˆ (circumflex) -> ɪ

  # English tokens suggest the run is something to throw out (N.B. final
  # deadbeef allows all lines to end in |)
  next if m/\b(
    [\N{U+025B}e]nds?|
    [\N{U+0283}s]tarts?|
    adje[c\N{U+028E}\N{U+03BB}]tives?|
    adverbs?|
    ages?|
    birthdays?|
    and|
    conversations?|
    days?|
    eight|
    else|
    explains?|
    express|
    first|
    for|
    games?|
    had|
    his|
    int[e\N{U+025B}]rvi[e\N{U+025B}]w|
    is|
    lots?|
    makes?|
    obje[\N{U+028E}\N{U+03BB}c]ts?|
    microphon[\N{U+025B}e]s?|
    numbers?|
    pages?|
    probability|
    proximal|
    reads?|
    relatives?|
    restaurants?|
    resumptive|
    rules?|
    some|
    subordinate|
    tap[e\N{U+025B}]s?|
    the|
    their|
    there|
    they|
    things?|
    this|
    travels?|
    used|
    very|
    words?|
    palphon.?|
  deadbeef)\b/ix;
  next if m/\d/;  # digits
  next if m/xlv/;  # roman numerals
  $v .= " " . $_;
}

chomp $v;
print $v . "\n";