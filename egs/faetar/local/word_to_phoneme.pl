#!/usr/bin/env -S perl -CS -p

use utf8;

# we use SAMPA codes b/c they're easier to type on a US keyboard

# spoken noise
s/\[x\]/ SPN/g;

# start with the 2-character phones
s/(?<! )t\N{U+0283}/ tS/g;  # tʃ
s/(?<! )d\N{U+0292}/ dZ/g;  # dʒ
s/(?<! )dz/ dz/g;

# now the one-char phones
s/(?<! )\N{U+0251}/ A/g;  # ɑ
s/(?<! )\N{U+014B}/ N/g;  # ŋ
s/(?<! )\N{U+0254}/ O/g;  # ɔ
s/(?<! )\N{U+0259}/ @/g;  # ə
s/(?<! )\N{U+025B}/ E/g;  # ɛ
s/(?<! )\N{U+0261}/ g/g;  # ɡ
s/(?<! )\N{U+0263}/ G/g;  # ɣ
s/(?<! )\N{U+026A}/ I/g;  # ɪ
s/(?<! )\N{U+0272}/ J/g;  # ɲ
s/(?<! )\N{U+0283}/ S/g;  # ʃ
s/(?<! )\N{U+028A}/ U/g;  # ʊ
s/(?<! )\N{U+028E}/ L/g;  # ʎ
s/(?<! )\N{U+0292}/ Z/g;  # ʒ
s/(?<! )\N{U+028C}/ V/g;  # ʌ
s/(?<! )\N{U+03B8}/ T/g;  # θ
s/(?<! )\N{U+00F0}/ D/g;  # ð
s/(?<! )a/ a/g;
s/(?<! )b/ b/g;
s/(?<! )c/ c/g;
s/(?<! )d/ d/g;
s/(?<! )e/ e/g;
s/(?<! )f/ f/g;
s/(?<! )h/ h/g;
s/(?<! )i/ i/g;
s/(?<! )j/ j/g;
s/(?<! )k/ k/g;
s/(?<! )l/ l/g;
s/(?<! )m/ m/g;
s/(?<! )n/ n/g;
s/(?<! )o/ o/g;
s/(?<! )p/ p/g;
s/(?<! )q/ q/g;
s/(?<! )r/ r/g;
s/(?<! )s/ s/g;
s/(?<! )t/ t/g;
s/(?<! )u/ u/g;
s/(?<! )v/ v/g;
s/(?<! )w/ w/g;
s/(?<! )y/ y/g;
s/(?<![d ])z/ z/g;
s/\N{U+02D0}/:/g;  # ː

# delete spaces at the beginning of the phone string
s/^ *//;

die "Found non-ascii character in pron: '$_'. Convert in word_to_phoneme.pl!"
  unless /^[[:ascii:]]+$/;