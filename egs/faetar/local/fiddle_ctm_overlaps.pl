#! /usr/bin/env perl

# Copyright 2023 Sean Robertson
# Apache 2.0

use warnings;
use strict;
use Getopt::Long;
use Pod::Usage;

my $help = 0;
my $man = 0;
my $sil = "<eps>";
my $no_empty = -1;
my $precision = 2;
GetOptions(
  'help|?' => \$help,
  'man' => \$man,
  'sil=s' => \$sil,
  'precision=i' => \$precision,
  'no-empty:2' => \$no_empty,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;
pod2usage("$0: --precision must be positive") if ($precision < 1);
pod2usage("$0: --sil '$sil' contains whitespace") if ($sil =~ / /);
pod2usage("$0: Too many arguments") if ($#ARGV > 1);

my ($in, $in_name);
if ($#ARGV >= 0) {
  $in_name = $ARGV[0];
  unless (open($in, "<", $in_name)) {
    pod2usage("$0: Could not open in_ctm $in_name for reading");
  }
} else {
  ($in_name, $in) = ("STDIN", *STDIN);
}

my ($out, $out_name);
if ($#ARGV == 1) {
  $out_name = $ARGV[1];
  unless (open($out, ">", $out_name)) {
    pod2usage("$0: Could not open out_ctm $out_name for writing");
  }
} else {
  ($out_name, $out) = ("STDOUT", *STDOUT);
}

my $line_fmt = sprintf(
  "%%s %%s %%.0%df %%.0%df %%s%%s\n",
  $precision, $precision
);

my ($last_reco, $last_channel, $last_tok, $last_conf) = ("") x 4;
my ($last_start, $last_end) = (-1) x 2;
my $about_zero = 10 ** (-$precision);

my $last_no = 0;
sub print_last {
  my $start = scalar(@_) ? shift(@_) : ($last_start + 1);
  return unless (($last_reco) && ($last_start >= 0));
  my $last_duration = $last_end - $last_start;
  if ($last_duration < $about_zero) {$last_duration = 0};
  if ($last_duration == 0) {
    return if (($no_empty < -1) || (($no_empty == -1) && ($last_tok eq $sil)));
    if (($no_empty == 1) && ($last_start == $start)) {
      die "$0: $in_name line $last_no: segment is empty and shares start with next segment";
    } elsif ($no_empty == 1) {
      die "$0: $in_name line $last_no: segment is empty";
    }
  }
  printf(
    $out $line_fmt,
    $last_reco, $last_channel, $last_start, $last_duration, $last_tok, $last_conf
  );
}

while (my $line = <$in>) {
  my $no = $last_no + 1;
  chomp($line);
  my @toks = split(/ /, $line);
  my ($reco, $channel, $start, $duration, $tok, $conf);
  if (scalar(@toks) == 5) {
    ($reco, $channel, $start, $duration, $tok) = @toks;
    $conf = "";
  } elsif (scalar(@toks) == 6) {
    ($reco, $channel, $start, $duration, $tok, $conf) = @toks;
    $conf = " " . $conf;
  } else {
    die "$0: $in_name line $no: invalid format '$line'";
  }
  die "$0: $in_name line $no: invalid segment start time $start" if ($start < 0);
  die "$0: $in_name line $no: invalid segment duration $duration" if ($duration < 0);
  my $end = $start + $duration;

  if (($reco ne $last_reco) || ($channel ne $last_channel)) {
    # print the previous record and clear the boundaries
    print_last();
    ($last_reco, $last_channel) = ($reco, $channel);
    $last_start = $last_end = -1;
  }

  die "$0: $in_name line $no: start time $start precedes previous segment's start time $last_start"
    if ($start < $last_start);

  # N.B. since we don't adjust the start time of the segment -- only its
  # duration -- we don't violate the sorted invariant
  $last_end = ($last_end > $start) ? $start : $last_end;

  print_last($start);

  ($last_reco, $last_channel, $last_start) = ($reco, $channel, $start);
  ($last_end, $last_tok, $last_conf, $last_no) = ($end, $tok, $conf, $no);
}
print_last();

__END__

=head1 NAME

fiddle_ctm_overlaps - modify ctm segment boundaries to remove overlap

=head1 SYNOPSIS

fiddle_ctm_overlaps [options] [in_ctm [out_ctm]]

  Arguments
    in_ctm                Path to input CTM. Defaults to STDIN
    out_ctm               Path to output CTM. Defaults to STDOUT

  Options
    --help                Brief help message
    --man                 Full help message
    --precision NAT       Number of decimals in segment boundaries. Defaults
                          to 2
    --sil STR             Silence token in CTM. Defaults to <eps>
    --no-empty [INT]      Disallow empty segments with optional severity. See
                          description for more details on severity.

=head1 DESCRIPTION

Intended to resolve indeterminacy in lattice-based CTM generation, this script
modifies the start and end times of segments by increments of the frame shift
until segments are non-overlapping. The script differs in behaviour from
utils/ctm/resolve_ctm_overlaps.py in that overlapping segments are adjusted
rather than removed.

We assume that the input CTM has already been sorted (i.e. by ascending 
recording id, channel, and then start time). When successive segments
(by line) in the same recording are overlapping, the duration of the earlier
segment is decreased until there is no longer overlap.

The resulting CTM may contain empty (0-second) segments. By default, this
script throws away any empty silences while keeping non-empty silences intact.
If the --no-empty option is specified without an argument, this script will
error as soon as it sees an empty segment. Finer-grained control of this
behaviour is possible by specifying the severity of the --no-empty option with
an integer argument. The levels of severity are:

=over

=item *
B<less than -1>: All empty segments (silence and non-silence) are discarded

=item *
B<-1 (default w/o --no-empty)>: All empty silence segments are discarded;
empty non-silence segments are permitted

=item *
B<0>: All empty segments are permitted

=item *
B<1>: Empty segments are permitted unless they share a start time

=item *
B<greater than 1 (default w/ --no-empty)>: No empty segments are permitted

=back

=cut