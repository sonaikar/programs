#!/usr/bin/perl

#
# File: cvsmirror $Revision: 1.19 $
#
# Syntax: cvsmirror [cvs global opts] subcommand [subcommand opts]
#
# subcommands are:
#       checkout - checks out from mirror and then changes CVS/Root;
#              also handle checkout synonyms
#       status (and synonyms)
#       sync - pulls new info from cvsup server (privileged)
#
# cvsup client should mirror most of CVSROOT, but prevent checkins,
# reminding them that CVS/Root should be changed if commit is attempted
#
# Search for ENHANCE for other suggestions
#
# ENHANCE
#       - cvsup logs are maintained on server (get via http?)
#
#   synclog - displays cvsup sync log
#       syncsched - displays current cvsup schedule
#       lastsync? - displays date/time of last cvsup sync
#       nextsync? - displays date/time of next scheduled cvsup sync
#

BEGIN {
if (! defined($ENV{'TOOLS_DIRECTORY'}))
   {
   $ENV{'TOOLS_DIRECTORY'} = "/pdd/cvs";
   }
}
use lib "$ENV{'TOOLS_DIRECTORY'}/lib";
use Birt::Stats qw( cli_usage_stats );
use Birt::CVS qw( %CVS_MIRRORS
                  %CVSUP_COMMAND
                  $CVS_SERVER_HOSTNAME
                  cvschroot
                  get_cvsroot
                  get_mirror_cvsroot
                  get_cvsroot_from_workdir
                  );
use Birt::Focus qw( is_branched_module );

use POSIX qw ( uname );
use File::Basename;
use Cwd;

#==============================================
# BEGIN MAIN
#==============================================

#
# Declare variables
#
my($USAGE, $command_line, $global_opts, $subcommand, $subcommand_opts,
   $cvsroot_arg, $orig_cvsroot, $mirror_cvsroot, $subcommands_regexp, $null,
   $debug);

select(STDERR);
$| = 1;
select(STDOUT);
$| = 1;

my($thisperl) = "$^X";
my($thisscript) = "$0";
my($progname) = &basename($0);
$progname =~ s/\.pl$//;
# Usage stats variables.
my ($VERSION) = sprintf "%d.%d", q$Revision: 1.19 $ =~ /: (\d+)\.(\d+)/;
my (%stats_data); $stats_data{'tool_version'} = $VERSION;
$stats_data{'UsageID'} = &cli_usage_stats("", %stats_data);

#
# Where to dump output not to be seen
#
if ( "$^O" =~ /win/i )
    {
    $null = "nul";
    }
else
    {
    $null = "/dev/null";
    }

#
# Parse command line, determine and initialize global variables.
#
&initialize();

#
# Accept any cvs subcommand
#
# When adding new subcommands, also change regexp beneath
# "Add new subcommands here!" comment in initialize().
#
$subcommands_regexp="add\|ad\|new\|admin\|adm\|rcs\|annotate\|ann\|checkout\|co\|get\|commit\|ci\|com\|diff\|di\|dif\|edit\|editors\|export\|exp\|ex\|history\|hi\|his\|import\|im\|imp\|log\|lo\|login\|logon\|lgn\|rannotate\|rann\|ra\|rdiff\|patch\|pa\|release\|re\|rel\|remove\|rm\|delete\|rlog\|rl\|rtag\|rt\|rfreeze\|status\|st\|stat\|sync\|tag\|ta\|freeze\|update\|up\|upd\|unedit\|watch\|watchers\|version\|ve\|ver";
if ( ("$subcommand" eq "checkout")
     or ("$subcommand" eq "co")
     or ("$subcommand" eq "get") )
   {

   #
   # Determine the module(s)
   #
   my($module) = "$subcommand_opts";
   if ($module =~ m/\-d\s*(\S+)/)
      {
      $module = "$1";
      }
   else
      {
      #
      # Attempt to capture possibility of multiple modules.  This relies
      # heavily on ignoring all options to 'cvs co'.  Prepend a space
      # to facilitate matching of switches while preventing matching
      # of module names containing hyphens.
      #
      $module = " $module";

      #
      # Strip out options which have args.
      #
      while ($module =~ m/\s+\-(r|D|k|j)\s*\S+/)
         {
         $module =~ s/\s+\-(r|D|k|j)\s*\S+(.*)/$2/;
         }

      #
      # Strip out options without args.
      #
      while ($module =~ m/\s+\-[ANPRcflnps]+/)
         {
         $module =~ s/\s+\-[ANPRcflnps]+(.*)/$1/;
         }
      }

   #
   # check if the -r option is present in the command line.
   #
   $branch_option = ($subcommand_opts =~ /\-r/);

   #
   # check each module to see if it is branched and build a list of them
   # if no -r was provided at the command line.
   #
   foreach (split ' ', $module)
      {
      $module_name = $_;
      if ( is_branched_module($module_name) )
         {
         if ( !($branch_option) )
            {
            $branched_modules = $branched_modules . " $module_name";
            }
         }
      }

   #
   # If found modules that require -r option at the command line
   # we abort the checkout.
   #
   if ( $branched_modules )
      {
      print "\nERROR!!\n";
      print "\nThe following modules require branch option ( -r <branch> )\n";
      print "Modules: $branched_modules\n\n";
      exit (1);
      }

   #
   # Do the checkout
   #
   if ($debug)
      {
      print "+cvs -d $mirror_cvsroot $global_opts $subcommand $subcommand_opts\n";
      }
   if ("$mirror_cvsroot" ne "$orig_cvsroot")
      {
      print "Checking out from $ENV{'CVS_LOCATION'}...\n";
      }

   ($a,$b,$MIRROR_HOST) = split /:/, $mirror_cvsroot;
   print "\nMIRROR_HOST: $MIRROR_HOST\n\n";

   system("cvs -d $mirror_cvsroot $global_opts $subcommand $subcommand_opts");

   #
   # Change the CVS/Root files back to the original CVSROOT
   # if we really checked out from a mirror
   #
   if ("$mirror_cvsroot" ne "$orig_cvsroot")
      {
      print "Reorienting checkout area to master server...\n";
      foreach (split ' ', $module)
         {
         $item_requested = $_;
         if (-e "$item_requested")
            {
            #
            # In case only a file or a lower level directory was checked out, we change
            # the cvsroot information at the very top of the module to propagate downwards.
            #
            ( $module_top_level_directory ) = split( '/', $item_requested);

            if ($debug)
               {
               print "+cvschroot($orig_cvsroot, $module_top_level_directory)\n";
               }
            cvschroot("$orig_cvsroot", "$module_top_level_directory");
            }
         else
            {
            print STDERR "ERROR ($progname): Item requested, $item_requested, does not exist.  Perhaps checkout failed?\n";
            }
         }
      }
   }
elsif ( ("$subcommand" eq "status")
     or ("$subcommand" eq "stat")
     or ("$subcommand" eq "st") )
   {
   if ($debug)
      {
      print "+cvs -d $mirror_cvsroot $global_opts $subcommand $subcommand_opts\n";
      }
   system("cvs -d $mirror_cvsroot $global_opts $subcommand $subcommand_opts");
   }
elsif ("$subcommand" eq "sync")
   {
   #
   # This subcommand is only available to the CVS administrator account
   #
   my($id) = scalar getpwuid($<);
   if ("$id" ne "cvsadm")
      {
      print STDERR "ERROR ($progname): The $subcommand option is only available to the CVS administrator.\n";
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }

   #
   # Determine the correct cvsup command for this host.
   #
   my ($hostname)  = (&uname())[1];
   my($cvsup_command) = "$CVSUP_COMMAND{$hostname}";
   if ((!defined($cvsup_command)) or ("$cvsup_command" !~ /\S+/))
      {
      print STDERR "ERROR ($progname): Unable to determine the cvsup command for this host, $hostname.\n";
      print STDERR "      Is this machine really an official cvs mirror?\n";
      print STDERR "      Known hosts are:  " . join (",", keys(%CVSUP_COMMAND)) . "\n";
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }

   #
   # Determine if the cvsup command is already running.
   #
   my($cvsup_short_cmd) = $cvsup_command;
   $cvsup_short_cmd =~ s!(\S+)\s.*!$1!;
   my($is_running) = `ps -eo args | grep "$cvsup_short_cmd" | grep -v grep`;
   chomp($is_running);

   #
   # Start an update if there's not already one running.
   #
   if ($is_running)
      {
      #
      # Be quiet by default so we don't get load of mail from cron
      #
      print "An instance of $cvsup_short_cmd is already running.  Try again later.\n" if ($debug);
      }
   else
      {
      print "Running $cvsup_command\n" if ($debug);
      print `$cvsup_command`;
      }
   }
else
   {
   $command_line =~ s/cvsmirror/cvs/;
   if ($debug) {print "+Running $command_line ...\n"};
   system("$command_line");
   }

&cli_usage_stats(0, %stats_data);
exit (0);

#==============================================
# END MAIN
#==============================================


#----------------------------------------------
# sub initialize
#----------------------------------------------
sub initialize
{
$debug = 0;

#
# Don't advertise the backup mirrors.
#
@MIRROR_LOCATIONS = grep (!/BACKUP/, keys (%CVS_MIRRORS));

$USAGE = "
cvsmirror -H
cvsmirror [cvs_global_opts] subcommand [subcommand_opts]

where:
   -H           Displays a help message

Any CVS command can be passed in as a parameter. Example:
   checkout     Performs a 'cvs checkout' from the mirror archive
   status       Performs a 'cvs status' on the mirror archive;
                Note that status will not reflect the latest info in
                the master archive.
   sync         Update the mirror archive on this host (requires privilege)

This command executes the specified subcommand on the mirror server
as determined by the environment variable \$CVS_LOCATION.
Valid locations are:

";

$USAGE .= "     " . join(', ', sort @MIRROR_LOCATIONS);

$USAGE .= "

The subcommands accept the same options as their cvs counterparts.
Synonyms for the subcommands are also supported.

Example:

     \$ setenv CVS_LOCATION SOBO
     \$ cvsmirror checkout -r maint11 Dart

";

#
# Parse command line.
#
$command_line = "$progname";
$command_line .= " " . join(" ", @ARGV);

if ($command_line =~ /\-H/)
   {
   print "$USAGE";
   &cli_usage_stats(0, %stats_data);
   exit (0);
   }

#
# Add new subcommands here!
#
if ($command_line =~ m/$progname\s*(.*)\s+(sync)$/)
   {
   $global_opts = $1;
   $subcommand = $2;
   $subcommand_opts = "";
   }
elsif ($command_line =~ m/$progname\s*(.*)\s+(checkout|co|get|status|stat|st)\s+(.*)$/)
   {
   $global_opts = $1;
   $subcommand = $2;
   $subcommand_opts = $3;
   }
else
   {
   print "$USAGE";
   &cli_usage_stats(0, %stats_data);
   exit (0);
   }

if ($global_opts =~ /\-D/)
   {
   $debug = 1;
   $global_opts =~ s/\-D//;
   }

#
# The sync subcommand doesn't get passed through to cvs
# so no additional information is required from initialize().
#
if ("$subcommand" eq "sync")
   {
   return;
   }

#
# Look for any '-d CVSROOT' in the command line and strip it out
# of global opts.  It will be overridden with $mirror_cvsroot.
#
if ($global_opts =~ m/\-d\s*(\S+)/)
   {
   $cvsroot_arg = "$1";
   $global_opts =~ s/\-d\s*\S+//;
   }

if ($debug)
   {
   print "+Cmd: $command_line\n";
   print "+Global: $global_opts\n";
   print "+Subcommand: $subcommand\n";
   print "+Subopts: $subcommand_opts\n";
   }

#
# Verify CVSROOT is defined or -d arg was used
#
if (defined($cvsroot_arg))
   {
   $orig_cvsroot = $cvsroot_arg;
   }
elsif (-r "CVS/Root")
   {
   $orig_cvsroot = get_cvsroot_from_workdir(&cwd());
   }
elsif (defined($ENV{'CVSROOT'}))
   {
   $orig_cvsroot = $ENV{'CVSROOT'};
   }
if ($orig_cvsroot !~ /\S+/)
   {
   print STDERR "\n";
   print STDERR "ERROR ($progname): Unable to determine \$CVSROOT.  You should set your\n";
   print STDERR "      environment variable \$CVSROOT.  Perhaps something like\n";
   print STDERR "      " . get_cvsroot('YourCVSid') . "\n";
   print STDERR "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Lookup mirror for CVS_LOCATION and set new CVSROOT
#
$cvsid = $orig_cvsroot;
$cvsid =~ s/:[^:]+://;
$cvsid =~ s/\@.*$//;
if ($debug)
   {
   print "+get_mirror_cvsroot($cvsid, $ENV{'CVS_LOCATION'})\n";
   }
$mirror_cvsroot = get_mirror_cvsroot($cvsid, $ENV{'CVS_LOCATION'});

if ("$mirror_cvsroot" !~ m/\S/)
   {
   print STDERR "\n";
   print STDERR "ERROR ($progname): Unable to determine \$CVSROOT setting for local mirror.\n";
   if ("$ENV{'CVS_LOCATION'}" eq "")
      {
      print STDERR "      The environment variable \$CVS_LOCATION is not set.\n";
      }
   else
      {
      print STDERR "      Perhaps the environment variable \$CVS_LOCATION is set incorrectly.\n";
      }
   print STDERR "      Valid choices are :\n";
   print STDERR "\n";
   print STDERR "           " . join(', ', sort @MIRROR_LOCATIONS) . "\n";
   print STDERR "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Verify current credentials exist for mirror machine.
#
my($cred_file, %creds); 
if (defined($ENV{'CVS_PASSFILE'}) and -r "$ENV{'CVS_PASSFILE'}")
   {
   $cred_file = "$ENV{'CVS_PASSFILE'}";
   }
elsif (defined($ENV{'HOME'}) and -r "$ENV{'HOME'}/.cvspass")
   {
   $cred_file = "$ENV{'HOME'}/.cvspass";
   }
else
   {
   print STDERR "\n";
   print STDERR "ERROR ($progname): Unable to authenticate with archive.  Try 'cvs login' first.\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Check $cred_file for $mirror_cvsroot and that encrypted password matches the one for $orig_cvsroot.
#
open (CRED, "$cred_file") or die "ERROR: Cannot open $cred_file.\n";
while (<CRED>)
   {
   if (m/^(\S+)\s+(\S+)\s+(.*)$/)
      {
      $creds{$2} = $3;
      }
   }
close (CRED);

#
# .cvspass entries always have the port number but $CVSROOT may not, so account for default port of 2401
#
my($orig_cvsroot_with_port) = cvsroot_with_port($orig_cvsroot);
my($mirror_cvsroot_with_port) = cvsroot_with_port($mirror_cvsroot);

#
# Compare master creds with mirror creds
#
if (exists($creds{$orig_cvsroot_with_port}))
   {
   if (exists($creds{$mirror_cvsroot_with_port}))
      {
      if ($creds{$orig_cvsroot_with_port} ne $creds{$mirror_cvsroot_with_port})
         {
         #
         # Update creds for mirror
         #
         print "+Updating .cvspass credentials\n" if ($debug);
         open (CREDNEW, ">${cred_file}.new") or die "ERROR: Cannot create ${cred_file}.new\n";
         open (CREDOLD, "${cred_file}") or die "ERROR: Cannot read ${cred_file}.\n";
         while (<CREDOLD>)
            {
            s!(.*\s+$mirror_cvsroot_with_port\s+).*!$1$creds{$orig_cvsroot_with_port}!;
            print CREDNEW;
            }
         close(CREDOLD);
         close(CREDNEW);
         rename("${cred_file}.new", "${cred_file}") or die "ERROR: Failed to rename ${cred_file}.new.\n       $!\n";
         }
      }
   else
      {
      #
      # Add entry for mirror using creds from master.
      #
      print "+Adding .cvspass entry\n" if ($debug);
      open (CRED, ">>$cred_file") or die "ERROR: Cannot update $cred_file.\n";
      print CRED "/1 $mirror_cvsroot_with_port $creds{$orig_cvsroot_with_port}\n";  # /1 is the cvs passwd version
      close (CRED);
      }
   }
else
   {
   #
   # Tell user to cvs login to master archive
   #
   print STDERR "ERROR ($progname): You must 'cvs login' first.\n";
   exit (1);
   }

#
# Determine if CVS mirror is up or not.
#
my ($mirror_server) = (split(/@/, $mirror_cvsroot))[1];
$mirror_server = (split(/:/, $mirror_server))[0];
if ($debug)
   {
   print "+CVS mirror: $mirror_server\n";
   }

if ("$mirror_server" ne "$CVS_SERVER_HOSTNAME")
    {
    #
    # Check if the CVS mirror server is available.
    # No need to check if fortknox is available or not
    # because everything will fail anyway if that is the case.
    #
    my ($status) = system("cvs -d $mirror_cvsroot -f co -p CVSROOT/.cvsignore >${null} 2>&1") / 256;

    if ($status)
        {
        print "WARNING: The CVS mirror ($mirror_server) for $ENV{'CVS_LOCATION'} appears to be " .
              "unavailable or you are not authorized to use it.\n\n" .
              "Using $CVS_SERVER_HOSTNAME to checkout sources...\n\n";
        $mirror_cvsroot = $orig_cvsroot;
        }
    }

if ($debug)
   {
   print "+cvsroot arg: $cvsroot_arg\n";
   print "+orig cvsroot: $orig_cvsroot\n";
   print "+mirror cvsroot: $mirror_cvsroot\n";
   }

}

#----------------------------------------------
# sub cvsroot_with_port
#----------------------------------------------
sub cvsroot_with_port
{
#
# Take a $CVSROOT that may or may not include a port number.
# If it doesn't, insert the default port number.
#
my($cvsroot) = @_;
my($default_port) = "2401";

if ($cvsroot !~ m!:[^:]+:[^:]+:\d+/!)
   {
   if ($cvsroot =~ m!(:[^:]+:[^:]+:)([^:]+)!)
      {
      #
      # Insert default port number
      #
      $cvsroot = "${1}${default_port}${2}";
      }
   else
      {
      #
      # Failure to parse
      #
      $cvsroot = "";
      }
   }
   
return $cvsroot;
}
