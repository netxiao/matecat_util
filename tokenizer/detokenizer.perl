#!/usr/bin/perl -w

# $Id: detokenizer.perl 4134 2011-08-08 15:30:54Z bgottesman $
# Sample De-Tokenizer
# written by Josh Schroeder, based on code by Philipp Koehn
# further modifications by Ondrej Bojar

binmode(STDIN, ":utf8");
binmode(STDOUT, ":utf8");
$|=1;

use strict;
use utf8; # tell perl this script file is in UTF-8 (see all funny punct below)

my $language = "en";
my $QUIET = 0;
my $HELP = 0;
my $UPPERCASE_SENT = 0;

while (@ARGV) {
	$_ = shift;
	/^-b$/ && ($| = 1, next);
	/^-l$/ && ($language = shift, next);
	/^-q$/ && ($QUIET = 1, next);
	/^-h$/ && ($HELP = 1, next);
	/^-u$/ && ($UPPERCASE_SENT = 1, next);
}

if ($HELP) {
	print "Usage ./detokenizer.perl (-l [en|fr|it|cs|...]) < tokenizedfile > detokenizedfile\n";
        print "Options:\n";
        print "  -u  ... uppercase the first char in the final sentence.\n";
        print "  -q  ... don't report detokenizer revision.\n";
        print "  -b  ... disable Perl buffering.\n";
	exit;
}

if ($language !~ /^(cs|en|fr|it)$/) {
  print STDERR "Warning: No built-in rules for language $language.\n"
}

if (!$QUIET) {
	print STDERR "Detokenizer Version ".'$Revision: 4134 $'."\n";
	print STDERR "Language: $language\n";
}

while(<STDIN>) {
	if (/^<.+>$/ || /^\s*$/) {
		#don't try to detokenize XML/HTML tag lines
		print $_;
	}
	else {
		print &detokenize($_);
	}
}


sub ucsecondarg {
  # uppercase the second argument
  my $arg1 = shift;
  my $arg2 = shift;
  return $arg1.uc($arg2);
}

sub detokenize {
	my($text) = @_;
	chomp($text);
	$text = " $text ";
  $text =~ s/ \@\-\@ /-/g;
  # de-escape special chars
  $text =~ s/\&bar;/\|/g;   # factor separator (legacy)
  $text =~ s/\&#124;/\|/g;  # factor separator
  $text =~ s/\&lt;/\</g;    # xml
  $text =~ s/\&gt;/\>/g;    # xml
  $text =~ s/\&bra;/\[/g;   # syntax non-terminal (legacy)
  $text =~ s/\&ket;/\]/g;   # syntax non-terminal (legacy)
  $text =~ s/\&quot;/\"/g;  # xml
  $text =~ s/\&apos;/\'/g;  # xml
  $text =~ s/\&#91;/\[/g;   # syntax non-terminal
  $text =~ s/\&#93;/\]/g;   # syntax non-terminal
  $text =~ s/\&amp;/\&/g;   # escape escape

	my $word;
	my $i;
	my @words = split(/ /,$text);
	$text = "";
	my %quoteCount =  ("\'"=>0,"\""=>0);
	my $prependSpace = " ";
	for ($i=0;$i<(scalar(@words));$i++) {		
		if (&startsWithCJKChar($words[$i])) {
		    if ($i > 0 && &endsWithCJKChar($words[$i-1])) {
			# perform left shift if this is a second consecutive CJK (Chinese/Japanese/Korean) word
			$text=$text.$words[$i];
		    } else {
			# ... but do nothing special if this is a CJK word that doesn't follow a CJK word
			$text=$text.$prependSpace.$words[$i];
		    }
		    $prependSpace = " ";
		} elsif ($words[$i] =~ /^[\p{IsSc}\(\[\{\¿\¡]+$/) {
			#perform right shift on currency and other random punctuation items
			$text = $text.$prependSpace.$words[$i];
			$prependSpace = "";
		} elsif ($words[$i] =~ /^[\,\.\?\!\:\;\\\%\}\]\)]+$/){
		    if (($language eq "fr") && ($words[$i] =~ /^[\?\!\:\;\\\%]$/)) {
			#these punctuations are prefixed with a non-breakable space in french
			$text .= " "; }
			#perform left shift on punctuation items
			$text=$text.$words[$i];
			$prependSpace = " ";
		} elsif (($language eq "en") && ($i>0) && ($words[$i] =~ /^[\'][\p{IsAlpha}]/) && ($words[$i-1] =~ /[\p{IsAlnum}]$/)) {
			#left-shift the contraction for English
			$text=$text.$words[$i];
			$prependSpace = " ";
		} elsif (($language eq "cs") && ($i>1) && ($words[$i-2] =~ /^[0-9]+$/) && ($words[$i-1] =~ /^[.,]$/) && ($words[$i] =~ /^[0-9]+$/)) {
			#left-shift floats in Czech
			$text=$text.$words[$i];
			$prependSpace = " ";
		}  elsif ((($language eq "fr") ||($language eq "it")) && ($i<=(scalar(@words)-2)) && ($words[$i] =~ /[\p{IsAlpha}][\']$/) && ($words[$i+1] =~ /^[\p{IsAlpha}]/)) {
			#right-shift the contraction for French and Italian
			$text = $text.$prependSpace.$words[$i];
			$prependSpace = "";
		} elsif (($language eq "cs") && ($i<(scalar(@words)-3))
				&& ($words[$i] =~ /[\p{IsAlpha}]$/)
				&& ($words[$i+1] =~ /^[-–]$/)
				&& ($words[$i+2] =~ /^li$|^mail.*/i)
				) {
			#right-shift "-li" in Czech and a few Czech dashed words (e-mail)
			$text = $text.$prependSpace.$words[$i].$words[$i+1];
			$i++; # advance over the dash
			$prependSpace = "";
		} elsif ($words[$i] =~ /^[\'\"„“`]+$/) {
			#combine punctuation smartly
                        my $normalized_quo = $words[$i];
                        $normalized_quo = '"' if $words[$i] =~ /^[„“”]+$/;
                        $quoteCount{$normalized_quo} = 0
                                if !defined $quoteCount{$normalized_quo};
                        if ($language eq "cs" && $words[$i] eq "„") {
                          # this is always the starting quote in Czech
                          $quoteCount{$normalized_quo} = 0;
                        }
                        if ($language eq "cs" && $words[$i] eq "“") {
                          # this is usually the ending quote in Czech
                          $quoteCount{$normalized_quo} = 1;
                        }
			if (($quoteCount{$normalized_quo} % 2) eq 0) {
				if(($language eq "en") && ($words[$i] eq "'") && ($i > 0) && ($words[$i-1] =~ /[s]$/)) {
					#single quote for posesssives ending in s... "The Jones' house"
					#left shift
					$text=$text.$words[$i];
					$prependSpace = " ";
				} else {
					#right shift
					$text = $text.$prependSpace.$words[$i];
					$prependSpace = "";
					$quoteCount{$normalized_quo} ++;

				}
			} else {
				#left shift
				$text=$text.$words[$i];
				$prependSpace = " ";
				$quoteCount{$normalized_quo} ++;

			}
			
		} else {
			$text=$text.$prependSpace.$words[$i];
			$prependSpace = " ";
		}
	}
	
	# clean up spaces at head and tail of each line as well as any double-spacing
	$text =~ s/ +/ /g;
	$text =~ s/\n /\n/g;
	$text =~ s/ \n/\n/g;
	$text =~ s/^ //g;
	$text =~ s/ $//g;
	
	#add trailing break
	$text .= "\n" unless $text =~ /\n$/;

        $text =~ s/^([[:punct:]\s]*)([[:alpha:]])/ucsecondarg($1, $2)/e if $UPPERCASE_SENT;

	return $text;
}

sub startsWithCJKChar {
    my ($str) = @_;
    return 0 if length($str) == 0;
    my $firstChar = substr($str, 0, 1);
    return &charIsCJK($firstChar);
}

sub endsWithCJKChar {
    my ($str) = @_;
    return 0 if length($str) == 0;
    my $lastChar = substr($str, length($str)-1, 1);
    return &charIsCJK($lastChar);
}

# Given a string consisting of one character, returns true iff the character
# is a CJK (Chinese/Japanese/Korean) character
sub charIsCJK {
    my ($char) = @_;
    # $char should be a string of length 1
    my $codepoint = &codepoint_dec($char);
    
    # The following is based on http://en.wikipedia.org/wiki/Basic_Multilingual_Plane#Basic_Multilingual_Plane

    # Hangul Jamo (1100–11FF)
    return 1 if (&between_hexes($codepoint, '1100', '11FF'));

    # CJK Radicals Supplement (2E80–2EFF)
    # Kangxi Radicals (2F00–2FDF)
    # Ideographic Description Characters (2FF0–2FFF)
    # CJK Symbols and Punctuation (3000–303F)
    # Hiragana (3040–309F)
    # Katakana (30A0–30FF)
    # Bopomofo (3100–312F)
    # Hangul Compatibility Jamo (3130–318F)
    # Kanbun (3190–319F)
    # Bopomofo Extended (31A0–31BF)
    # CJK Strokes (31C0–31EF)
    # Katakana Phonetic Extensions (31F0–31FF)
    # Enclosed CJK Letters and Months (3200–32FF)
    # CJK Compatibility (3300–33FF)
    # CJK Unified Ideographs Extension A (3400–4DBF)
    # Yijing Hexagram Symbols (4DC0–4DFF)
    # CJK Unified Ideographs (4E00–9FFF)
    # Yi Syllables (A000–A48F)
    # Yi Radicals (A490–A4CF)
    return 1 if (&between_hexes($codepoint, '2E80', 'A4CF'));

    # Phags-pa (A840–A87F)
    return 1 if (&between_hexes($codepoint, 'A840', 'A87F'));

    # Hangul Syllables (AC00–D7AF)
    return 1 if (&between_hexes($codepoint, 'AC00', 'D7AF'));

    # CJK Compatibility Ideographs (F900–FAFF)
    return 1 if (&between_hexes($codepoint, 'F900', 'FAFF'));

    # CJK Compatibility Forms (FE30–FE4F)
    return 1 if (&between_hexes($codepoint, 'FE30', 'FE4F'));

    # Range U+FF65–FFDC encodes halfwidth forms, of Katakana and Hangul characters
    return 1 if (&between_hexes($codepoint, 'FF65', 'FFDC'));

    # Supplementary Ideographic Plane 20000–2FFFF
    return 1 if (&between_hexes($codepoint, '20000', '2FFFF'));

    return 0;
}

# Returns the code point of a Unicode char, represented as a decimal number
sub codepoint_dec {
    if (my $char = shift) {
	return unpack('U0U*', $char);
    }
}

sub between_hexes {
    my ($num, $left, $right) = @_;
    return $num >= hex($left) && $num <= hex($right);
}