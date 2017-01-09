#!/usr/bin/perl
################################################################################
#
# File: analyzetree.pl
#
# Usage: perl analyzetree.pl <root of source tree>
#
# Description: Takes a clean directory tree (no s.* files, no build files, no
#              temp files, no extraneous symlinks, etc.) and archives it in CVS
#              This should only be run once, as it will create new modules and
#              add all files/dirs found in <root of source tree>.  Everything is
#              added on the trunk.  A series of cvs add's are used instead of
#              'cvs import' to allow more control over binary files.
#
################################################################################


################################################################################
#
# Library path and includes
#
################################################################################
use lib "$ENV{TOOLS_DIRECTORY}/lib";
use Cwd;
use File::Basename;
use POSIX qw(strftime);


################################################################################
#
# FILE TYPE HASHES:  YOU MAY NEED TO MODIFY THESE TO SUIT PARTICULAR PROJECTS
#
# ignore_list: Ignore files matching these regular expressions; case insensitive
#              Example: \.scc$ matches all files ending in .scc (literal period)
#
# binary_list: Files ending in these extensions or matching these root
#              relative paths are always considered binary
#              Examples: 1. dll will match files ending in ".dll"
#                        2. if $root=/foo/bar, one might specify bar/baz.buz
#
# text_list:   Files ending in these extensions or matching these root
#              relative paths are always considered text
#              Examples: 1. txt will match files ending in ".txt"
#                        2. if $root=/foo/bar, one might specify bar/baz.buz
#
# NOTE:  Ignored files take first precedence.  Binary takes second precendence,
#        thus any file or extension listed in both binary_list and text_list
#        will be treated as binary.
#
################################################################################
@ignore_list{ qw (
   \.scc$
   \.vspscc$
   \.vssscc$
   CVS\/Entries$
   CVS\/Entries\.log$
   CVS\/Repository$
   CVS\/Root$
   CVS\/Template$
) } = ();

@binary_list{ qw (
   2unzip
   a
   aps
   au
   avi
   bin
   bin.src
   bmp
   book
   bz2.src
   class
   com
   com.src
   cpl
   dat.src
   data.src
   dll
   doc
   eps
   exe
   exe.src
   fm
   gid
   gif
   gz
   gz.src
   hlp
   ht
   ico
   img.src
   jar
   jpeg
   jpg
   lib
   lib.src
   msg.src
   msi
   ncb
   o
   o.src
   opt
   pdf
   png
   ppt
   rom.src
   rpm
   rpm.src
   so.src
   tar
   tar.src
   tgz.src
   tif
   tlb
   trm
   wav
   wdt
   wsi
   wvr
   xls
   z
   z.src
   zip.src
) } = ();

@text_list{ qw ( reg txt ) } = ();


################################################################################
#
# SPECIAL HANDLING:  YOU MAY NEED TO MODIFY THESE TO SUIT PARTICULAR PROJECTS
#
# $EMPTY_IS_BINARY:  The flag works as follows, with extension and exception
#                    hashes taking first precendence before these rules:
#
#                    * if non-null, empty files are always treated as binary
#                    * otherwise, empty files are always treated as text
#
################################################################################
$EMPTY_IS_BINARY = "";


################################################################################
#
# BEGIN MAIN
#
# 1. Parse command line for tree root
# 2. Perform any necessary setup/initializations
# 3. Make our best effort to determine how to archive files:
#    a. Determine if file is to be ignored (i.e. do not archive)
#    b. Determine if file is specified via name or extension as binary or text
#    c. Determine via file test operator if a file is text or binary
#    d. If text, keep track of files containing the log expansion keyword
#
################################################################################

if ( $#ARGV )
   {
   error_exit("\nUSAGE:  analyzetree <root directory of source tree>\n\n");
   }

if ( ! -d "$ARGV[0]" )
   {
   error_exit("\nERROR:  $ARGV[0] does not exist or is not a directory.\n\n");
   }

$root = $ARGV[0];
$rootbase = basename($root);
print "\n" . strftime("%a %b %d %H:%M:%S %z %Y", localtime(time)) . "\n";
print "Analyzing tree rooted at $root\n";
print "Precedence for exceptions are: ignored first, binary second, text last\n";

if ( $EMPTY_IS_BINARY )
   {
   print "Empty files not found on the exception lists are always treated as binary\n";
   }
else
   {
   print "Empty files not found on the exception lists are always treated as text\n";
   }
print "After exceptions are processed, file test operators are utilized on non-empty files\n";

print "\nIGNORE ALWAYS:\n";
if ( %ignore_list )
   {
   print " * $_\n" foreach ( sort keys %ignore_list);
   }
else
   {
   print " *** Ignore List is Empty ***\n";
   }

print "\nBINARY ALWAYS:\n";
if ( %binary_list )
   {
   print " * $_\n" foreach ( sort keys %binary_list);
   }
else
   {
   print " *** Binary List is Empty ***\n";
   }

print "\nTEXT ALWAYS:\n";
if ( %text_list )
   {
   print " * $_\n" foreach ( sort keys %text_list);
   }
else
   {
   print " *** Text List is Empty ***\n";
   }

print "\n";

FILES:foreach $file (sort `find $root -type f -print`)
   {
   chomp($file);
   $is_text = 0;
   $rootpath = $file;
   $rootpath =~ s!^$root/!$rootbase/!;
   @atoms = split(/\./, $file);
   $extension = $atoms[$#atoms];
   $extension =~ tr/[A-Z]/[a-z]/;

   foreach $regexp ( keys %ignore_list )
      {
      if ( $file =~ m/$regexp/i )
         {
         push(@ignored, "$file");
         next FILES;
         }
      }

   if ( exists $binary_list{$rootpath} or exists $binary_list{$extension} )
      {
      push(@binfiles, "$file");
      }
   elsif ( exists $text_list{$rootpath} or exists $text_list{$extension} )
      {
      $is_text = 1;
      }
   elsif ( (-B "$file" and -s "$file") or (-z "$file" and $EMPTY_IS_BINARY) )
      {
      push(@binfiles, "$file");
      }
   elsif ( -T "$file" or -z "$file" )
      {
      $is_text = 1;
      }
   else
      {
      push(@errfiles, "$file");
      }

   if ( $is_text )
      {
      if ( keywords("$file") )
         {
         push(@errfiles, "$file");
         }
      else
         {
         push(@txtfiles, "$file");
         }
      }
   }

if ( @ignored )
   {
   print "IGNORED: $_\n" foreach ( @ignored );
   print "\n\n";
   }

if ( @binfiles )
   {
   print "BINARY FILE: $_\n" foreach ( @binfiles );
   print "\n\n";
   }

if ( @txtfiles )
   {
   print "TEXT FILE: $_\n" foreach ( @txtfiles );
   print "\n\n";
   }

if ( @errfiles )
   {
   print "AMBIGUOUS or KEYWORD FOUND: $_\n" foreach ( @errfiles );
   print "\n\n";
   }

exit 0;

################################################################################
#
# END MAIN
#
################################################################################


sub keywords
{
my ($filename) = @_;
my($keyword_count) = `grep -c '\\\$Log\\\$' '$filename'`;
chomp($keyword_count);
return($keyword_count);
}

sub find_total_size
{
my (@filelist) = @_;
my ($size, $total_size);

$total_size = 0;

foreach (@filelist)
   {
   $size = -s "$_";
   $total_size += $size;
   }

return ($total_size);
}


sub error_exit
{
my(@message) = @_;
print STDOUT @message;
exit(1);
}
