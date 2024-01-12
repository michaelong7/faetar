#!/usr/bin/env -S perl -CO

# Convert IPAPhon character encodings to UTF, followed by some idiosyncratic
# character mappings.

# This script relies on my custom antiword install from the sdrobert channel
# being installed into $CONDA_PREFIX. It includes the "ipaphon.txt" mapping and
# skips some of the formatting antiword does (e.g. tab replacement) which later
# scripts rely on. The text should be piped in from antiword like so:
#
#  antiword -m ipaphon path/to/doc.doc | local/ipaphon_to_utf.pl > out_file.txt

# If you're interested in how I did it for posterity or you plan on improving
# the mapping, read on.
#
# To get the conversions in ipaphon.txt, I downloaded IPADOCS.zip and
# IPAPHON.zip from
#
# https://web.archive.org/web/20041222230044/http://www.chass.utoronto.ca/~rogers/fonts/
#
# IPAPHON.zip stores the TrueType versions of the font, which can be installed
# by opening them up in Windows and hitting "install". Then the symbol table
# document 'symfind.doc' in IPADOCS.zip can be cross-referenced with the
# TrueType glyphs (which you can see with a program such as Fontographer). Do
# not rely on the pictures in symfind.doc: they are most likely wrong! Just use
# the decimal/ASCII codes (which need to be converted to hex) and the UTF
# character names (e.g. LATIN SMALL LETTER A). Note that in the installed
# truetype fonts, glyph hexes are of the format 0xf0__, not 0x00__. ipaphon.txt
# not only stores the mapping between hex codes and character names, but is
# also used by antiword to subtract 0xf000 from all the codes.

use utf8;
use charnames ':full';
use Env;
use File::Find;

my $ipaphon_txt;

find( sub { ($ipaphon_txt = $File::Find::name ) if m/.*ipaphon\.txt$/ }, $ENV{CONDA_PREFIX});

open(my $fh, '<', $ipaphon_txt) or die "Could not open '$ipaphon_txt'";

my %hex2utf;
while (my $line = <$fh>) {
  chomp $line;
  if ($line =~ m/(0X..)\t0X....\t# (.*)$/) {
    my ($key, $val) = (hex($1), charnames::string_vianame($2));
    die "Line '$line' has invalid or missing utf name '$2'"
      unless ("$val" ne "");
    $hex2utf{$key} = $val;
  }
}
close $fh;

while ($line = <STDIN>) {
  my $v = join(
    "",
    map { (exists $hex2utf{$_}) ? $hex2utf{$_} : chr($_) } unpack("C*", $line)
  );
  # specific mappings specified by Naomi in "Faetar font issues.pdf"
  # ipaphon.txt maps the ipaphon characters to their corresponding unicode characters, so the characters
  # displayed by ipaphon are the same as the unicode characters in the expressions below
  $v =~ s/\N{LATIN SMALL LETTER D WITH HOOK}/\N{LATIN LETTER SMALL CAPITAL I}/g;  # ɗ -> ɪ
  $v =~ s/\N{LATIN LETTER BILABIAL CLICK}/\N{LATIN SMALL LETTER ENG}/g;  # ʘ -> ŋ
  $v =~ s/\N{LATIN SMALL LETTER TURNED H}/\N{LATIN SMALL LETTER OPEN E}/g;  # ɥ -> ɛ
  $v =~ s/\N{LEFT DOUBLE QUOTATION MARK}/\N{LATIN SMALL LETTER TURNED Y}/g; # “ -> ʎ
  $v =~ s/\N{LATIN SMALL LETTER S WITH HOOK}/\N{LATIN SMALL LETTER ESH}/g;  # ʂ -> ʃ
  $v =~ s/\N{MODIFIER LETTER CIRCUMFLEX ACCENT}/\N{LATIN SMALL LETTER ESH}/g;  # ˆ -> ʃ
  print $v;
}
