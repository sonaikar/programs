#!/usr/bin/perl

#
# File: cvschroot $Revision: 1.2 $
#
# Syntax: cvschroot
#

BEGIN {
if (! defined($ENV{'TOOLS_DIRECTORY'}))
   {
   $ENV{'TOOLS_DIRECTORY'} = "/pdd/cvs";
   }
}
use lib "$ENV{'TOOLS_DIRECTORY'}/lib";

require "getopts.pl";

use Birt::CVS qw( cvschroot );
use Birt::Stats qw( cli_usage_stats );
use File::Basename;

#==============================================
# BEGIN MAIN
#==============================================

#
# Declare variables
#
my($USAGE, $command_line, $local_mode);

my($thisperl) = "$^X";
my($thisscript) = "$0";
my($progname) = &basename($0);
$progname =~ s/\.pl$//;

$local_mode = 0;

$USAGE = "
cvschroot -H
cvschroot [-l] new_cvsroot checkout_dir

where:
   -H            Displays this help message
   -l            Local mode; only changes \$CVSROOT for specified dir
   new_cvsroot   Specifies the new \$CVSROOT for this checkout area
   checkout_dir  Specifies which directory tree to modify

This command modifies the \$CVSROOT setting for a cvs checkout area.
It operates recursively by default.  Use with caution.
";

# Usage stats variables.
my ($VERSION) = sprintf "%d.%d", q$Revision: 1.2 $ =~ /: (\d+)\.(\d+)/;
my (%stats_data); $stats_data{'tool_version'} = $VERSION;
my ($debug) = 0;
$stats_data{'UsageID'} = &cli_usage_stats("", %stats_data);

#
# Parse command line.
#
$command_line = "$progname";
$command_line .= " " . join(" ", @ARGV);

$options = "Hl";
if ( ! Getopts($options) )
   {
   &cli_usage_stats(1, %stats_data);
   die "$USAGE";
   }

#
# References to defeat perl -w
#
$opt_H = $opt_H;
$opt_l = $opt_l;

if ($opt_H)   { print $USAGE; &cli_usage_stats(0, %stats_data); exit (0); }
if ($opt_l)   { $local_mode = 1; }

$new_cvsroot = "$ARGV[0]";
$checkout_dir = "$ARGV[1]";

#
# Validate options
#
if ( $new_cvsroot !~ /\S+/ )
   {
   print STDERR "\n";
   print STDERR "ERROR ($progname): New \$CVSROOT not specified.  Use -H for usage.\n";
   print STDERR "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

if ( ! -d "$checkout_dir" )
   {
   print STDERR "\n";
   print STDERR "ERROR ($progname): Checkout directory, $checkout_dir,\n";
   print STDERR "      does not exist.  Use -H for usage.\n";
   print STDERR "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Change the CVS/Root file(s).
#
if ($local_mode)
   {
   if (! open(ROOT, ">$checkout_dir/CVS/Root"))
        {
        &cli_usage_stats(1, %stats_data);
        die "Cannot open $checkout_dir/CVS/Root for writing.\n$!\n";
        }
   print ROOT "$new_cvsroot\n";
   close ROOT;
   }
else
   {
   cvschroot("$new_cvsroot", "$checkout_dir");
   }

#==============================================
# END MAIN
#==============================================

