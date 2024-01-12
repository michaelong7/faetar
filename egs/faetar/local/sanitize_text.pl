#!/usr/bin/env -S perl -CS -n

use utf8;

my @x = split(/\h+/, $_, 2);
my $utt_id = shift(@x);
$_ = shift(@x);

# standardize unintelligible token
s/\b\[[^\]]*xx[^\]]*\]\b/[x]/;
s/\b\[?xx*\]?\b/[x]/g;

# standardize filled pauses (TODO: check with Naomi!)
s/\ba+h+\b/[fp]/g;
s/\be[eh]+\b/[fp]/g;
s/\bmm+\b/[fp]/g;
s/\bhm+\b/[fp]/g;
s/\buh+\b/[fp]/g;

# no modifier letters on their own or starting a token
s/\h\p{gc:Lm}//g;

# Ø appears in F62B_C_IV9_Tape 7b (17:45 - 18:00) with no pronunciation
# likely null subject marker
s/\N{U+00D8}//g;

# ˞ (rhotic hook modifier) appears in heritage eafs likely as a sign that the word was stopped halfway through
# seems to represent glottal stop
s/\N{U+02DE}//g;

# This may cover up some font issues, but I know that, sometimes, / is being
# used between alternate phonemic transcriptions
s:\b([^/]+)/\S+: \1:g;

s/\N{U+02B0}+/\N{U+02B0}/g;  # no more than one ʰ

# delete punctuation
# N.B. ʔ could be a glottal stop, but it's definitely being used in e.g.
# F8A&F27C2019_2019_convo as a question mark (?) instead

# (u+002e is .)  (u+002c is ,)  (u+0294 is ʔ) (u+00ab is « (angle quotation mark) (u+0022 is "))
s/[\N{U+002E}\N{U+002C}\N{U+0294}\N{U+00AB}\N{U+0022}]//g;
# (u+003b is <)  (u+003c is ;)  (u+003e is >) (u+2026 is …) (u+005c is \) (u+0027 is ' (apostrophe))
s/[\N{U+003B}\N{U+003C}\N{U+003E}\N{U+2026}\N{U+005C}\N{U+0027}]//g;
# (u+002f is /)  (u+003d is =)  (u+003f is ?)  (u+002a is *)  (u+002d is -)  (u+0060 is ` (grave accent))
s/[\N{U+002F}\N{U+003D}\N{U+003F}\N{U+002A}\N{U+002D}\N{U+0060}]//g;
# (u+02bc is ʼ (modifier apostrophe)) (u+00b4 is ´ (acute accent) (u+2013 is – (en dash))
# u+01c3 is ǃ (retroflex click) used in heritage eafs as an exclamation point
s/[\N{U+02BC}\N{U+00B4}\N{U+2013}\N{U+01C3}]//g;
# the lines above replace the punctuation listed (using the unicode numbers) with an empty string

# maybe a space (‿)?
s/\N{U+203F}/ /g;

# delete square braces unless it's one of the accepted special tokens
s/\[(?!fp)(?!x)//g; s/(?<!fp)(?<!x)\]//g;

# typos/inconsistencies TODO: (Check with Naomi!)
s/\[to child\]//;
s/\N{U+00F0}\N{U+0292}okat\N{U+0259}l\N{U+0259}/d\N{U+0292}okat\N{U+0259}l\N{U+0259}/g; # ðʒokatələ -> dʒokatələ
tr/g/\N{U+0261}/;  # g -> ɡ  (this may be wrong!)
tr/\N{U+03BB}/\N{U+028E}/;  # λ -> ʎ (probably fine - no ipa for lambda)
s/\N{U+02A4}/d\N{U+0292}/g;  # ʤ -> dʒ
s/\N{U+2202}/\N{U+00F0}/g;  # ∂ (partial differential) -> ð
s/\N{U+2020}/\N{U+03B8}/g;  # † (dagger) -> θ
s/\N{U+00C4}/\N{U+0072}/g;  # Ä -> r
s/sh/\N{U+0283}/g;  # sh -> ʃ
s/\N{U+04D9}/\N{U+0259}/g;  # ә (cyrillic schwa) -> ə (latin schwa)
s/\N{U+0264}/\N{U+0263}/g;  # ɤ (ram's horns) -> ɣ (latin gamma)
s/\N{U+028F}/j/g; # ʏ -> j
s/:/\N{U+02D0}/g; # : (colon) -> ː (vowel lengthening mark)
s/\N{U+026F}/m/g; # ɯ (turned m) -> m
s/\N{U+0325}//g; # deletes ◌̥ (voiceless marker) 
s/\N{U+02B2}//g; # deletes ʲ (used in heritage files instead of apostrophe at some points)
s/ h //g; # deletes lone h (prevents lexicon from having a word with empty pronunciation)

# faetar font conversion fixes:
tr/\N{U+00A8}/\N{U+028A}/; # ¨ -> 
tr/\N{U+02DC}/\N{U+014B}/; # ˜ (small tilde) -> ŋ
tr/\N{U+00E6}/\N{U+0061}/; # æ -> a
tr/\N{U+03BC}/\N{U+0272}/; # μ (greek mu) -> ɲ
tr/\N{U+00B5}/\N{U+0272}/; # µ (micro) -> ɲ
tr/\N{U+00E4}/\N{U+0077}/; # ä -> w
tr/\N{U+0086}/\N{U+0064}/; # (invisible control character) -> d

# Michael: If these are doc only, they shold go into sanitize_doctext.pl
# phone changes to fit accepted faetar phone list ASK LATER !!!!!!!!!!!!!!!!!!!!!!!!!11111!!!!!!
s/\N{U+0281}/\N{U+0263}/g;  # ʁ -> ɣ
s/\N{U+028B}/v/g; # ʋ -> v
s/\N{U+03B2}/v/g; # β -> v
s/\N{U+0279}/r/g; # ɹ -> r
s/\N{U+025B}\N{U+0303}/\N{U+025B}j/g; # ɛ̃ (tilde is a modifier) -> ɛj
s/a\N{U+0303}/a/g; # ã (tilde is a modifier) -> a
s/\N{U+00F5}/o/g; # õ (tilde is not a modifier) -> o
s/\N{U+0254}\N{U+0303}/\N{U+0254}/g; # ɔ̃ (tilde is a modifier) -> ɔ
s/u\N{U+0303}/u/g; # ũ (tilde is a modifier) -> u
# ASK NAOMI LATER !!!!!!!!!!!!!!!!!!1!!!!!!!!!!!1!!!!!!!!!!1!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# stress in the transcriptions is marked by an acute accent 
# when the stressed syllable is not in the expected position

# if dealing with stress is necessary, use the following three fixes, 
# then modify word_to_phoneme.pl to allow for accented vowels
# s/\N{U+0092}/\N{U+02CA}/g; # (invisible control character) -> ˊ (modifier acute accent)
# s/\N{U+02B0}/\N{U+02CA}/g;  # ʰ (modifier superscript h) -> ˊ (modifier acute accent)
# s/\N{U+2019}/\N{U+02CA}/g;  # ’ (right single quote) -> ˊ (modifier acute accent)

# otherwise, use the three fixes below which delete the characters corresponding to the acute accent
s/\N{U+0092}//g; # deletes an invisible control character
s/\N{U+02B0}//g;  # deletes ʰ (modifier small h)
s/\N{U+2019}//g;  # deletes ’ (right single quote)

# stressed vowels (not using the modifier) appear in heritage eafs
# if dealing with stress, remove these lines
tr/\N{LATIN SMALL LETTER I WITH ACUTE}/i/;  # í -> i
tr/\N{LATIN SMALL LETTER I WITH GRAVE}/i/;  # ì -> i
tr/\N{LATIN SMALL LETTER U WITH ACUTE}/u/;  # ú -> u
tr/\N{LATIN CAPITAL LETTER E WITH ACUTE}/e/;  # É -> e

# sdrobert: ¿ -> o
tr/\N{INVERTED QUESTION MARK}/o/;

# Italian orthography https://en.wikipedia.org/wiki/Italian_orthography
# there should be a more structured way of dealing with this, e.g. an Italian
# lexicon w/ IPA prons
tr/\N{LATIN SMALL LETTER E WITH GRAVE}/\N{U+025B}/;  # è -> ɛ
tr/\N{LATIN SMALL LETTER E WITH ACUTE}/e/;  # é -> e
tr/\N{LATIN SMALL LETTER O WITH GRAVE}/o/;  # ò -> o
tr/\N{LATIN SMALL LETTER U WITH GRAVE}/u/;  # ù -> u
tr/\N{LATIN SMALL LETTER O WITH ACUTE}/\N{U+0254}/;  # ó -> ɔ
tr/\N{LATIN SMALL LETTER A WITH GRAVE}/a/;  # à -> a
tr/\N{LATIN SMALL LETTER I WITH CIRCUMFLEX}/i/;  # î -> i
tr/\N{LATIN SMALL LETTER A WITH ACUTE}/a/;  # á -> a

s/sci(?=[aeiou\N{U+025B}\N{U+0254}])/\N{U+0283}/g;  # sci (before any vowel) -> ʃ
s/sc(?=[ei\N{U+025B}\N{U+0254}])/\N{U+0283}/g;  # sc (before front vowels) -> ʃ

s/cqu/kkw/g;  # cqu -> kkw
s/qu/kw/g;  # qu -> kw

s/cci(?=[aeiou\N{U+025B}\N{U+0254}])/tt\N{U+0283}/g; # cci (before any vowel) -> ttʃ
s/cc(?=[aou])/kk/g; # cc (before non-front vowels) -> kk
s/cc(?=[ei\N{U+025B}\N{U+0254}])/tt\N{U+0283}/g; # cc (before front vowels) -> ttʃ
s/cch/kk/g; # cch -> kk

s/ci(?=[aeiou\N{U+025B}\N{U+0254}])/t\N{U+0283}/g; # ci (before any vowel) -> tʃ
s/c(?=[aou])/k/g; # c (before non-front vowels) -> k
s/c(?=[ei\N{U+025B}\N{U+0254}])/t\N{U+0283}/g; # c (before front vowels) -> tʃ
s/ch/k/g; # ch -> k
s/c/k/g;  # c (other environments) -> k

s/\N{U+0261}\N{U+0261}i(?=[aeiou\N{U+025B}\N{U+0254}])/dd\N{U+0292}/g; # ggi (before any vowel) -> ddʒ
s/\N{U+0261}\N{U+0261}(?=[aou])/\N{U+0261}\N{U+0261}/g; # gg (before non-front vowels) -> gg
s/\N{U+0261}\N{U+0261}(?=[ei\N{U+025B}\N{U+0254}])/dd\N{U+0292}/g; # gg (before front vowels) -> ddʒ
s/\N{U+0261}\N{U+0261}h/\N{U+0261}\N{U+0261}/g; # ggh -> gg

s/\N{U+0261}i(?=[aeiou\N{U+025B}\N{U+0254}])/d\N{U+0292}/g; # gi (before any vowel) -> dʒ
s/\N{U+0261}(?=[aou])/\N{U+0261}/g; # g (before non-front vowels) -> g
s/\N{U+0261}(?=[ei\N{U+025B}\N{U+0254}])/d\N{U+0292}/g; # g (before front vowels) -> dʒ
# currently, the only italian word using 'gh' in the corpus is 'inghilterra' so it is replaced here
s/inɡhiltɛrra/inɡilterra/g;
# gh is turned into ɣ instead of g since the transcription uses gh to represent the velar fricative
s/\N{U+0261}h/\N{U+0263}/g; # gh -> ɣ

s/(?<=[aeiou\N{U+025B}\N{U+0254}])\N{U+0261}li(?=[aeiou\N{U+025B}\N{U+0254}])/\N{U+028E}\N{U+028E}/g; # gli (between vowels) -> ʎʎ
s/(?<=[aeiou\N{U+025B}\N{U+0254}])\N{U+0261}l(?=i)/\N{U+028E}\N{U+028E}/g; # gli (preceded by a vowel and word final) -> ʎʎi
s/\N{U+0261}l(?=i)/\N{U+028E}/g; # gli (other environments) -> ʎi

s/(?<=[aeiou\N{U+025B}\N{U+0254}])\N{U+0261}n(?=[aeiou\N{U+025B}\N{U+0254}])/\N{U+0272}\N{U+0272}/g; # ɡn (between vowels) -> ɲɲ

s/(\H)\1+/\1\N{U+02D0}/g;  # geminate (xx -> xː)

# sdrobert: M70_C_IV_Tape 25a
s/r\N{COMBINING SEAGULL BELOW}/r/g;

# clean up spaces
s/\h+$//;
s/^\h+//;
s/\h+/ /g;

print "$utt_id $_" unless (
  /\[[^]]*ita\]/ ||  # some italian in there
  /^\[[^]]*\]$/ ||  # utterance consists only of a non-word
  /^\h*$/ # empty utterance
);
