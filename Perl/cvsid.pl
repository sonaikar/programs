#!/usr/bin/perl

#
# File: cvsid.pl
#
# Description: Searches cvsidinfo file for a match and displays
#              information about that matching entry/entries.
#
# Usage: cvsid search_word...
#
# Fields in cvsidinfo are colon-separated
#
#   cvsuserid:Lastname,Firstname:email:phone:location:address
#

BEGIN {
if (! defined($ENV{'TOOLS_DIRECTORY'}))
   {
   $ENV{'TOOLS_DIRECTORY'} = "/pdd/cvs";
   }
}
use lib "$ENV{'TOOLS_DIRECTORY'}/lib";

use Birt::CVS qw($ARCHIVE_ROOT $CVS_ADMIN_EMAIL
                 $CVS_SERVER_HOSTNAME $CVSROOT_PATH);
use Birt::Stats qw( cli_usage_stats );
require "getopts.pl";

my(@search_words);
my($cvsuser, $fullname, $email, $phone, $location, $address, $null,
   $USAGE, $options, $linecount, $matches);

$USAGE = "
USAGE: cvsid -H                   Displays this help message
       cvsid search_word...       Searches for cvs user id entries

cvsid returns cvs user information for entries matching
all of your search words.  Output includes cvs userid, full name,
email address, phone number, and location information.

Example invocations:

     cvsid csharpe         Searches by cvsuserid
     cvsid Chris Sharpe    Searches by first and last name
     cvsid Sharpe          Searches by partial name
     cvsid 6137            Searches by partial phone number


Contact $CVS_ADMIN_EMAIL for corrections.

";
# Usage stats variables.
my ($VERSION) = sprintf "%d.%d", q$Revision: 1.9 $ =~ /: (\d+)\.(\d+)/;
my (%stats_data); $stats_data{'tool_version'} = $VERSION;
my ($debug) = 0;
$stats_data{'UsageID'} = &cli_usage_stats("", %stats_data);

$options = "H";
if ( ! do Getopts($options) )
   {
   &cli_usage_stats(1, %stats_data);
   die "$USAGE";
   }

if ($opt_H)
   {
   print "$USAGE";
   &cli_usage_stats(0, %stats_data);
   exit (0);
   }

@search_words = @ARGV;

if ( ! @search_words )
   {
   &cli_usage_stats(1, %stats_data);
   die "$USAGE";
   }

if ( "$^O" =~ /win/i )
   {
   $null = "nul";
   }
else
   {
   $null = "/dev/null";
   }

#
# If running on the cvs server, access the cvsidinfo file
# directly since it is in CVSROOT and will always be current.
#
my ($thishost) = `hostname`;
chomp($thishost);

my ($cvsserver) = $CVS_SERVER_HOSTNAME;
$cvsserver =~ s/\..*$//;          # remove any domain info

if ( "$thishost" eq "$cvsserver" )
   {
   open(CVSIDINFO, "$CVSROOT_PATH/cvsidinfo");
   }
else
   {
   #
   # If we're on some other host, then checkout the file to a pipe.
   # Assumes cvs is on path and $CVSROOT is set.
   #
   # With CVS authentication now in place, you must have a CVSid to
   # use this CLI.  If you don't, you can only use this via the web.
   #
   open(CVSIDINFO, "cvs co -p CVSROOT/cvsidinfo 2>$null |");
   }

$linecount = 0;
$matches = 0;

ID_ENTRY: while (<CVSIDINFO>)
   {
   $linecount++;
   next ID_ENTRY if /^#/;
   next ID_ENTRY if /^\s*$/;
   chomp;

   foreach $word (@search_words)
      {
      #
      # Matches are case-insensitive.
      #
      if (! m/$word/i)
         {
         next ID_ENTRY;
         }
      }

   #
   # If we make it here, this entry is a match for all search words.
   #
   $matches++;
   ($cvsuser, $fullname, $email, $phone, $location, $address) = split(/:/);
   $fullname =~ s/,/, /;
   write;
   }

close (CVSIDINFO);

if ($linecount == 0)
   {
   print "ERROR (cvsid.pl): Failed to read database.\n";
   print "      Is a cvs binary on your path?  Is the cvs server available?\n";
   print "      Contact $CVS_ADMIN_EMAIL for help.\n";
   &cli_usage_stats(1, %stats_data);
   exit 1;
   }

if ($matches == 0)
   {
   print "No matches.\n";
   &cli_usage_stats(0, %stats_data);
   exit 0;
   }

format STDOUT =
CVSid:  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<    Address:  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$cvsuser, $address
Name:   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<    Location: @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$fullname, $location
Email:  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<    Phone:    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$email, $phone

.

&cli_usage_stats(0, %stats_data);
exit (0);

