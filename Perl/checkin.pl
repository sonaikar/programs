#!/usr/bin/perl
#!/usr/bin/perl -w

#
# File: checkin.pl $Revision: 1.73 $
#
# Description: Wrapper around 'cvs commit'
#              Only allowed method to commit files to the CVS archive.
#
# Requirements:  1) $CVSROOT must be set (unless provided with -d)
#                2) access to the appropriate tools directory
#                   (meaning the share or export is available)
#
# Enhancements:
#               o Use an EXCEPTION_LEVEL similar to DEBUG_LEVEL
#                 instead of BIRT_* variables
#               o Validate CVSROOT is same as login id.  See notes
#                 in validate_options() and NSQA-57141.
#               o Do something like a 'tail -f' on cmd output and filter
#                 out noise, but display the interesting stuff while
#                 doing commits.  Show lock errors, access validation,
#                 but present commits concisely.
#               o Could handle up-to-date checkin failed better when
#                 your locally modified file is out of date, but it
#                 will merge successfully.  Don't do the update for
#                 them, but give them the command to run to do it.
#               o Could detect if last 'cvs -n -q up' gives no output
#                 it might indicate changes are already in the downstream
#                 branch; do something nicer than print an error; isn't
#                 there a 'already contains' message from 'up -j -j'
#                 to look for and display?
#               o There have been requests not to propagate removes.
#               o Should propagations skip branches?  Maybe skip only
#                 if they are in a certain phase or are closed completely?
#                 For example, a opal checkin when garnetbeta is closed.
#               o Method to stop propagation for particular files.
#
# Assumptions:  1) To guarantee that all checkins to initial branch are
#                  properly propagated, the user should not make any
#                  changes in the working directory until the initial
#                  checkin is done.
#

BEGIN {
if (! defined($ENV{'TOOLS_DIRECTORY'}))
   {
   $ENV{'TOOLS_DIRECTORY'} = "/pdd/cvs";
   }
}
use lib "$ENV{'TOOLS_DIRECTORY'}/lib";

require "getopts.pl";

use Birt::Array qw( uniq );
use Birt::CVS qw( $ARCHIVE_ROOT
                  $CVS_ADMIN_EMAIL
                  allow_exception
                  cvsid_to_email
                  get_branch_from_workdir
                  get_cvsroot_from_workdir
                  get_module_from_workdir
                  get_repository_from_workdir
                  notify
                  notify_using_file
                  notify_with_follow_up_using_file
                  );
use Birt::Focus qw( get_propagation_chain
                    get_focus
                    get_focusinfo_field
                    get_checkin_template
                    is_official_branch );
use Birt::Stats qw( cli_usage_stats );
use POSIX qw( uname
              strftime );
use File::Basename;
use File::Copy;
use File::Find;
use File::Path;
use Sys::Hostname;
use Cwd qw( cwd
            abs_path );

my($thisperl) = "$^X";
my($thisscript) = "$0";
my($progname) = &basename($0);

#
# Predeclare this subroutine so we can call it with the same syntax
# as Perl's print.
#
sub print_and_log(@);

select(STDERR);
$| = 1;
select(STDOUT);
$| = 1;

#
# Declare variables
# It would be nice to use some capitalization convention here.
#
my($comment_file, $comment_file_arg, $cvsroot_arg, $local_mode_arg,
   $message_string, $message_string_arg, $no_action_arg, $propagation_chain,
   $gzip_level_arg, $debug_level, $take_defaults, $USAGE, $debug_level_map,
   $BIRT_NO_ACCESS, $BIRT_NO_MAIL, $BIRT_NO_STR, $BIRT_CVSRECON, $debug,
   $cvs_debug_arg, $branch, $user, $nextrev, $branch_phase, $status,
   $premerge_tag, $MAX_NUM_FILES, $checkin_with_file_list, $focus,
   $postmerge_tag, $working_dir, $LogDir, $module, $junk,
   $ignore_cvsrc_arg, $cvs_repository, $merge_dir, $run_cmd_counter,
   $cvs_repository_module, $CHECKINID, $COMMITID, $HOSTNAME, $HOSTIP,
   $USERID);
my(@files_to_commit, @original_files_to_commit);
my(%commits_done);
# Usage stats variables.
my ($VERSION) = sprintf "%d.%d", q$Revision: 1.73 $ =~ /: (\d+)\.(\d+)/;
my (%stats_data); $stats_data{'tool_version'} = $VERSION;
$stats_data{'UsageID'} = &cli_usage_stats("", %stats_data);

#
# Initialize variables, parse options, and validate.
#
initialize_variables();
validate_options();

#
# Initialize logging
#
if ( -d "$LogDir")
   {
   rmtree("$LogDir");
   }
if ( ! mkdir("$LogDir", 0777) )
   {
   print "\n";
   print "ERROR ($progname): Failed to create log directory, $LogDir.\n";
   print "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }
if ($opt_F)   { #if user specified a file for checkin comment, copy that file into
                #the log dir of current checkin
                copy("$opt_F", "$LogDir/comment.orig");
                $comment_file = "$LogDir/comment.orig";
                $comment_file_arg = "-F \"$comment_file\"";}
if ( ! open(LOGFILE, ">$LogDir/log") )
   {
   print "\n";
   print "ERROR ($progname): Failed to create log file, $LogDir/log.\n";
   print "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }
print "LogDir is $LogDir\n\n" if ($debug);
select(LOGFILE);
$| = 1;
select(STDOUT);

my($checkintime) = time;
print LOGFILE "Date:   " . strftime("%a %b %d %H:%M:%S %Z %Y\n", localtime($checkintime));
print LOGFILE "Cmd:    $command_line\n";
print LOGFILE "LogDir: $LogDir\n";
print LOGFILE "-----------------------------------------------------------------\n";
print LOGFILE "\n";


#
# Log some environment info
#
open(ENVIRONMENT, ">$LogDir/environment");
print ENVIRONMENT "Environment Information:\n";
print ENVIRONMENT "------------------------\n";

print ENVIRONMENT "Uname:      " . join(" ", uname) . "\n";
$HOSTNAME = hostname;
$HOSTIP = join(".", unpack('C4', gethostbyname($HOSTNAME)));
print ENVIRONMENT "Hostname:   $HOSTNAME\n";

$CHECKINID = strftime("%Y%m%d%H%M%S", localtime($checkintime));
$CHECKINID .= "_${HOSTNAME}.$$";

#
# get* user and group id functions are not supported on Win32,
# so get what we can from the Win32 core calls instead of calling &id().
#
if ( "$^O" =~ /win/i )
   {
   my($domain) = Win32::DomainName();
   my($login) = Win32::LoginName();
   my($node) = Win32::NodeName();
   print ENVIRONMENT "DomainName: $domain\n";
   print ENVIRONMENT "LoginName:  $login\n";
   print ENVIRONMENT "NodeName:   $node\n";
   $USERID = "$domain\\$login";
   }
else
   {
   my($id) = &id();
   print ENVIRONMENT "Id:         $id\n";
   $USERID = $id;
   }
chomp $USERID;

print ENVIRONMENT "\nCVS Info:\n";
print ENVIRONMENT "---------\n";
print ENVIRONMENT "CVSROOT=$ENV{'CVSROOT'}\n";
print ENVIRONMENT "CVS_LOCATION=$ENV{'CVS_LOCATION'}\n";
print ENVIRONMENT "TOOLS_DIRECTORY=$ENV{'TOOLS_DIRECTORY'}\n";
print ENVIRONMENT `cvs version`;

print ENVIRONMENT "\nAll Environment Variables:\n";
print ENVIRONMENT "--------------------------\n";
for $key (sort(keys(%ENV)))
   {
   print ENVIRONMENT "$key=$ENV{$key}\n";
   }
if ( "$^O" =~ /win/i )
   {
   print ENVIRONMENT "\n\nNetwork Shares for $ENV{'COMPUTERNAME'}:\n";
   print ENVIRONMENT `net use`;
   print ENVIRONMENT `net share`;
   }
close ENVIRONMENT;

if ( $debug_level & 4 )
   {
   #
   # Use '-t' for tracing CVS and also set CVS_CLIENT_LOG
   # to get a log of all client-server communication.
   #
   print LOGFILE "Everything sent to the server will be in cvstrace.in\n";
   print LOGFILE "Everything sent from the server will be in cvstrace.out\n";
   print LOGFILE "\n";
   $cvs_debug_arg = "-t";
   $ENV{'CVS_CLIENT_LOG'} = "$LogDir/cvstrace";
   }

print_and_log "Examining working area...\n";
print LOGFILE "\n+Current dir is now " . &cwd() . "\n";

#
# Use cvs -n -q update to get all files that will be changed
# Handle various cvs errors nicely
#
my($cmd);

$cmd = "cvs $cvs_debug_arg $cvsroot_arg $gzip_level_arg" .
       " -f -n -q update $local_mode_arg ";

undef (@update_output);
$status = 0;
$status = run_cmd($cmd, \@files_to_commit, \@update_output, 1);

#
# Check that list for required updates and for conflicts
#
my(@added_files, @conflict_files, @modified_files, @removed_files,
   @updated_files);
parse_cvs_update_output(\@update_output, \@added_files, \@conflict_files,
                        \@modified_files, \@removed_files, \@updated_files);

#
# Make sure there's something to checkin.
#
if ( !@added_files && !@removed_files && !@modified_files )
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): No files in your working area have been modified.\n";
   if (@update_output)
      {
      print_and_log "      Perhaps you are creating a new file but forgot to 'cvs add' it?\n";
      print_and_log "\n";
      print_and_log "      A 'cvs -n -q update' shows:\n";
      for (@update_output) { print_and_log "         $_\n"; }
      }
   print_and_log "\n";
   remove_logdir();
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Determine the repository name
#
# We need a full repository-root-relative pathname for some commands
# (elog/foo.h or just foo.c isn't sufficient)
#
# The CVS.pm routine will print an error and return undef if unable
# to determine the module.
#
$cvs_repository = get_repository_from_workdir("$working_dir");
print LOGFILE "+Repository: $cvs_repository\n";
if (! defined ($cvs_repository) )
   {
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Determine the top-level module and verify it is the same for all files.
#
# The CVS.pm routine will print an error and return undef if unable
# to determine the module.
#
my(%module_map);
foreach $file (@modified_files, @removed_files, @added_files)
   {
   #
   # The CVS.pm routine will print an error and return undef if unable
   # to determine the module.
   #
   my($dir) = dirname($file);
   if (! defined $module_map{$dir})
      {
      $module_map{$dir} = get_module_from_workdir($dir);
      }
   }
if (scalar(uniq(values %module_map)) != 1)
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): A single checkin cannot involve multiple modules.\n";
   print_and_log "      You are attempting to checkin changes to the following modules:\n";
   print_and_log "\n";
   print_and_log "           " . join(", ", uniq(values %module_map)) . "\n";
   print_and_log "\n";
   print_and_log "      Change directory into each module and perform separate checkins.\n";
   print_and_log "\n";
   &cli_usage_stats(1, %stats_data);
   exit(1);
   }

$module = (values %module_map)[0];
print LOGFILE "+Module: $module\n";
if (! defined ($module) )
   {
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Verify that the Repository name and the Module name match.
# These might be different if the current directory corresponded to one module
# ($cvs_repository) and checkin was given explicit filenames to files in
# another module ($module).  Specifically, the $module should be the first
# component of $cvs_repository.
#
if ( $cvs_repository =~ m!([^/]+)/! )
   {
   $cvs_repository_module = $1;
   }
else
   {
   $cvs_repository_module = $cvs_repository;
   }
if ( $cvs_repository_module !~ /^$module/ )
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): A checkin cannot involve multiple modules.\n";
   print_and_log "      Your current directory is in the '$cvs_repository_module' module,\n";
   print_and_log "      but the files you changed are in the '$module' module.\n";
   print_and_log "\n";
   print_and_log "      Change directory into the '$module' module and checkin from there.\n";
   print_and_log "\n";
   &cli_usage_stats(1, %stats_data);
   exit(1);
   }


#
# Determine the branch name and verify is is the same for all files.
#
# We require all files in the working directory to be from the
# same branch (or all from the trunk).  And each subdir with a
# file to be changed must also be from the same branch as all other
# subdirs.
#
# In other words, a single checkin can only affect a single branch.
#
my(%branch_map);
foreach $file (@modified_files, @removed_files, @added_files)
   {
   #
   # The CVS.pm routine will print an error and return undef if unable
   # to determine the module.
   #
   my($dir) = dirname($file);
   if (! defined $branch_map{$dir})
      {
      $branch_map{$dir} = get_branch_from_workdir($dir);
      }
   }
if (scalar(uniq(values %branch_map)) != 1)
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): A single checkin cannot involve multiple branches.\n";
   print_and_log "      You are attempting to checkin changes to the following branches:\n";
   print_and_log "\n";
   foreach $dir (keys %branch_map)
      {
      print_and_log "           $dir   ($branch_map{$dir})\n";
      }
   print_and_log "\n";
   print_and_log "      If this is surprising to you, your working area may be in an inconsistent state.\n";

   print_and_log "      If this is your intent, perform separate checkins for files from each branch.\n";
   print_and_log "\n";
   &cli_usage_stats(1, %stats_data);
   exit(1);
   }

$branch = (values %branch_map)[0];
print LOGFILE "+Branch: $branch\n";
if (! defined ($branch) )
   {
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Now determine the focus from the module and branch.
#
$focus = get_focus($module, $branch);
print LOGFILE "+Focus:  $focus\n";

if (! defined ($focus) )
   {
   print "\n";
   print "ERROR ($progname): Unable to determine focus.  The $branch branch\n";
   print "      of the $module module does not map to a single focus.  Contact\n";
   print "      $CVS_ADMIN_EMAIL for help fixing your working area.\n";
   print "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Validate the propagation chain
#
validate_prop_chain();
print LOGFILE "+PropCh: $propagation_chain\n";

#
# Check for conflicts
#
if (@conflict_files)
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): Some files in your working directory have conflicts.\n";
   print_and_log "      Edit the file(s) and resolve the conflicts.  Then rerun checkin.\n";
   print_and_log "\n";
   print_and_log "      Files with conflicts:\n";
   for (@conflict_files) { print_and_log "         $_\n"; }
   print_and_log "\n";
   remove_logdir();
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Display list of files that will be checked in
#
print_and_log "\n";
if (@added_files)
   {
   print_and_log "Add files:\n";
   for (@added_files) { print_and_log "   $_\n"; }
   print_and_log "\n";
   }
if (@removed_files)
   {
   print_and_log "Remove files:\n";
   for (@removed_files) { print_and_log "   $_\n"; }
   print_and_log "\n";
   }
if (@modified_files)
   {
   print_and_log "Modify files:\n";
   for (@modified_files) { print_and_log "   $_\n"; }
   print_and_log "\n";
   }

#
# Print a summary of where the checkin is going
#
print_and_log "Checkin to: $branch";
if ( is_official_branch($branch, $module) )
   {
   ($branch_phase, $required_keyword) = split /\//, get_focusinfo_field($focus, $branch, 'pt_phase');
   #
   # If no PT integration is used, don't print anything.
   #
   if ( "$branch_phase" ne "none" )
      {
      print_and_log " ($branch_phase phase";
      print_and_log " - $required_keyword keyword required" if ($required_keyword);
      print_and_log ")";
      }
   #
   # If PT phase is set to auto-props only, then error out.
   #
   if ( "$branch_phase" eq "autoproponly" )
      {
      print_and_log "\n\n";
      print_and_log "ERROR ($progname): The '$branch' branch has a Product Tracking phase of\n";
      print_and_log "      '$branch_phase' which only permits automatic propagations into the branch.\n";
      print_and_log "      If you have a need to checkin due to a failed automatic propagation that\n";
      print_and_log "      you wish to complete, contact $CVS_ADMIN_EMAIL.  If you desire privilege\n";
      print_and_log "      to checkin for some other reason, contact your Program Management and\n";
      print_and_log "      request this restriction be removed.\n";
      print_and_log "\n";
      &cli_usage_stats(1, %stats_data);
      exit(1);
      }
   }
print_and_log "\n";

$nextrev = get_nextrev($branch);
while ( "$nextrev" ne "NONE" )
   {
   if ( is_official_branch($branch, $module) )
      {
      my($nextphase, $next_keyword) = split /\//, get_focusinfo_field($focus, $nextrev, 'pt_phase');
      if ( "$nextphase" eq "noautoprop" )
         {
         print_and_log "\n";
         print_and_log "WARNING: Ignoring '$nextrev' and any later branches since pt_phase is '$nextphase'.\n";
         print_and_log "         Original propagation chain was '$propagation_chain'.\n";
         $propagation_chain =~ s/(.*):$nextrev(:.*|$)/$1/;
         print_and_log "         New propagation chain is '$propagation_chain'.\n";
         last;
         }
      elsif ( "$nextphase" eq "none" )
         {
         print_and_log "            $nextrev\n";
         }
      else
         {
         print_and_log "            $nextrev ($nextphase phase";
         print_and_log " - $next_keyword keyword required" if ($next_keyword);
         print_and_log ")\n";
         }
      }
   else
      {
      print_and_log "            $nextrev\n";
      }
   $nextrev = get_nextrev($nextrev);
   }

#
# Reset nextrev to the current nextrev
#
$nextrev = get_nextrev($branch);

#
# Summarize exceptions, if any.
#
if ($BIRT_NO_ACCESS || $BIRT_NO_MAIL || $BIRT_NO_STR || $BIRT_CVSRECON)
   {
   print_and_log "\n";
   print_and_log "Exceptions:\n";
   if ($BIRT_NO_ACCESS)
      {
      print_and_log "   BIRT_NO_ACCESS\n";
      }
   if ($BIRT_NO_MAIL)
      {
      print_and_log "   BIRT_NO_MAIL\n";
      }
   if ($BIRT_NO_STR)
      {
      print_and_log "   BIRT_NO_STR\n";
      }
   if ($BIRT_CVSRECON)
      {
      print_and_log "   BIRT_CVSRECON\n";
      }
   }

#
# The -n switch isn't much use anymore; see NSQA-56920
#
if (defined($no_action_arg))
   {
   print_and_log "\n";
   print_and_log "Taking no action due to -n switch.\n";
   print_and_log "$progname exiting...\n";
   remove_logdir();
   &cli_usage_stats(0, %stats_data);
   exit (0);
   }

#
# Prompt user if above list is ok
#
my($answer) = "y";
if ( ! $take_defaults )
   {
   print_and_log "\n";
   print_and_log "Proceed? [y]";
   $_ = getc;
   chomp;
   $answer = $_ if ($_);
   print LOGFILE "+$answer\n";
   }
if ($answer !~ /y/i)
   {
   print_and_log "\n";
   print_and_log "$progname aborted cleanly.\n";
   remove_logdir();
   &cli_usage_stats(0, %stats_data);
   exit (0);
   }

#
# Force the user to enter the checkin comment now if they
# haven't already done so.  This prevents the cvs that is forked
# in a subshell from needing to get input from the user.
# On a Unix system that invokes vi, the user wouldn't see the editor.
#
# This also forces checkin comments for all dirs involved in
# this commit to be identical.  This is our restriction,
# not cvs's, but it's a minor restriction that guarantees we get
# the right comment for the propagation.
#
if ( ! defined($comment_file_arg) && ! defined($message_string_arg))
   {
   $comment_file = get_checkin_comment_from_user();
   $comment_file_arg = "-F \"$comment_file\"";
   }

#
# If the user gave a message string, put it in a file for
# easier handling.
#
if ( defined($message_string_arg) )
   {
   $comment_file = "$LogDir/comment.orig";
   $comment_file_arg = "-F \"$comment_file\"";
   if (!open(COMMENT_FILE, ">$comment_file"))
      {
      print_and_log "\n";
      print_and_log "ERROR ($progname): Cannot open file $comment_file.\n";
      print_and_log "      $!\n";
      &cli_usage_stats(1, %stats_data);
      exit(1);
      }
   print COMMENT_FILE "$message_string\n";
   close COMMENT_FILE;

   undef $message_string;
   undef $message_string_arg;
   }

@original_files_to_commit = @files_to_commit;

#
# From this point on, these are the only files we care about.
# This new filelist will be needed for any merging to be done.
#
@files_to_commit = (@added_files, @removed_files, @modified_files);

#
# Determine if any files are binary (as designated by the
# -kb sticky option) and split @modified_files and @added_files
# accordingly (doesn't matter for removed files).
#
if (@added_files)
   {
   find_binary_files(\@added_files, \@added_binary_files, \@added_text_files);
   }
if (@modified_files)
   {
   find_binary_files(\@modified_files, \@modified_binary_files,
                     \@modified_text_files);
   }

#
# Set up some signal handling since if someone aborts now,
# we should try to delete the temporary tags
#
$SIG{HUP} = 'signal_handler';
$SIG{INT} = 'signal_handler';
$SIG{QUIT} = 'signal_handler';
$SIG{TERM} = 'signal_handler';

if ( "$nextrev" ne "NONE" )
   {
   apply_premerge_tag(@removed_files, @modified_files);
   }

#
# checkin files to initial branch
#
print_and_log "\nCheckin to $branch...\n";
print LOGFILE "+---------------------\n";

my($committime) = time;
$COMMITID = strftime("%Y%m%d%H%M%S", localtime($committime));
$COMMITID .= "_${branch}_${HOSTNAME}.$$";

$cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg $gzip_level_arg" .
       " $ignore_cvsrc_arg" .
       " -s DEBUG_LEVEL=$debug_level" .
       " -s BRANCH=$branch" .
       " -s MODULE=$module" .
       " -s BIRT_NO_ACCESS=$BIRT_NO_ACCESS" .
       " -s BIRT_NO_MAIL=$BIRT_NO_MAIL" .
       " -s BIRT_NO_STR=$BIRT_NO_STR" .
       " -s BIRT_CVSRECON=$BIRT_CVSRECON" .
       " -s CHECKINID=$CHECKINID" .
       " -s COMMITID=$COMMITID" .
       " -s HOSTNAME=$HOSTNAME" .
       " -s HOSTIP=$HOSTIP" .
       " -s USERID=\"$USERID\"" .
       " -s WORKDIR=\"$working_dir\"" .
       " commit $local_mode_arg $comment_file_arg ";

#
# If the user provides a list of files and/or dirs, use this list for the
# commit to initial branch. It is very reasonable that the user will not
# provide a long list. On the other hand, if the user does not provide a
# list, we can run 'cvs commit' without file list under the current working
# dir.
#
chdir "$working_dir";
my(@commit_output);
$status = 0;
if ($checkin_with_file_list)
   {
   $status = run_cmd($cmd, \@original_files_to_commit, \@commit_output);
   }
else
   {
   $status = run_cmd($cmd, undef, \@commit_output);
   }

display_commit_output(\@commit_output);
if ($status)
   {
   delete_tags(@removed_files, @modified_files);
   print_and_log "   ***** Please note: your checkin comment is saved in $LogDir/comment.orig \n";
   print_and_log "   If you want to reuse the comments you just entered, fix all errors that caused the checkin to fail, ";
   print_and_log "INCLUDING those in the comments, then ";
   print_and_log "   run checkin again with the following option: \n\n";
   print_and_log "   -F $LogDir/comment.orig \n\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   } # End of checking in files to initial branch


#
# If there are no propagations to do, exit here.
#
if ( "$nextrev" eq "NONE" )
   {
   remove_logdir();
   &cli_usage_stats(0, %stats_data);
   exit (0);
   }

#
# From this point on (assuming commit worked) keep careful track
# of what happens.  Any failure now means something failed to propagate!
# Also, any exits should first send email and delete tags.
#

apply_postmerge_tag(@files_to_commit);

#
# Create checkin comment to use for propagations
#
pause("About to put checkin comment in comment.prop");
copy("$comment_file", "$LogDir/comment.prop");
chmod 0666, "$LogDir/comment.prop";
$comment_file = "$LogDir/comment.prop";
$comment_file_arg = "-F \"$comment_file\"";
open( COMMENT_FILE, ">>$comment_file" );
print COMMENT_FILE "\nAUTOMATIC PROPAGATION FROM: $branch\n";
close COMMENT_FILE;

#
# Begin loop for propagations
#
while ( "$nextrev" ne "NONE" )
   {
   $branch = $nextrev;
   print_and_log "\nPropagating to $branch...\n";
   print LOGFILE "+-------------------------\n";

   $merge_dir = "$working_dir/Merge_to_${branch}.$$";

   pause("Creating $merge_dir");

   if ( -d "$merge_dir")
      {
      rmtree("$merge_dir");
      }
   if (! mkdir ("$merge_dir", 0777))
      {
      $error_msg = "\n";
      $error_msg .= "ERROR ($progname): Failed to create merge directory,\n";
      $error_msg .= "      $merge_dir.\n";
      $error_msg .= "      $!\n";
      $error_msg .= "\n";
      print_and_log $error_msg;
      send_alert($error_msg);
      print_and_log "   ***** Please note: your checkin comment is saved in $LogDir/comment.orig \n";
      print_and_log "   If you want to reuse the comments you just entered, first fix all errors,";
      print_and_log "   then run checkin again with the following option: \n\n";
      print_and_log "   -F $LogDir/comment.orig \n\n";
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }
   if (! chdir "$merge_dir")
      {
      $error_msg = "\n";
      $error_msg .= "ERROR ($progname): Failed to chdir to merge directory,\n";
      $error_msg .= "      $merge_dir.\n";
      $error_msg .= "      $!\n";
      $error_msg .= "\n";
      print_and_log $error_msg;
      send_alert($error_msg);
      print_and_log "   ***** lease note: your checkin comment is saved in $LogDir/comment.orig \n";
      print_and_log "   If you want to reuse the comments you just entered, first fix all errors, ";
      print_and_log "   then run checkin again with the following option: \n\n";
      print_and_log "   -F $LogDir/comment.orig \n\n";
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }
   print_and_log "merge_dir is $merge_dir\n" if ($debug);
   print LOGFILE "+Current dir is now " . &cwd() . "\n";

   #
   # Checkout files
   #
   if (@modified_files || @removed_files)
      {
      my(@files_to_checkout) = make_cvsroot_relative(@modified_files,
                                                     @removed_files);
      pause("About to checkout " . join(" ", (@modified_files, @removed_files)));
      $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
             " checkout -r $branch ";

      my(@checkout_output);
      $status = 0;
      $status = run_cmd($cmd, \@files_to_checkout, \@checkout_output);
      if ($status)
         {
         send_alert("Checkout of $branch files failed");
        print_and_log "   ***** Please note: your checkin comment is saved in $LogDir/comment.orig \n";
         print_and_log "   If you want to reuse the comments you just entered, first fix all errors, ";
         print_and_log "   then run checkin to $branch mannually with the following option: \n\n";
         print_and_log "   -F $LogDir/comment.orig \n\n";
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }

      #
      # Clean up the tree if necessary (workaround to samba bug)
      #
      pause("About to prune $merge_dir/$module");
      prune_cvs_tree("$merge_dir/$module");
      }

   #
   # Handle modified files
   #
   if (@modified_files)
      {
      #
      # For binary files, be sure not to disable keyword expansion (-kk)
      # since it will remove the -kb sticky option.
      #
      if (@modified_text_files)
         {
         my(@files) = make_cvsroot_relative(@modified_text_files);
         $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
                " update -kk -j $premerge_tag -j $postmerge_tag ";

         pause("About to update -kk -j pre -j post");
         undef (@update_output);
         $status = 0;
         $status = run_cmd($cmd, \@files, \@update_output);
         if ($status)
            {
            send_alert("Update -kk -j pre -j post failed for $branch");
            &cli_usage_stats(1, %stats_data);
            exit (1);
            }
         }
      if (@modified_binary_files)
         {
         my(@files) = make_cvsroot_relative(@modified_binary_files);
         $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
                " update -j $premerge_tag -j $postmerge_tag ";

         pause("About to update -j pre -j post");
         undef (@update_output);
         $status = 0;
         $status = run_cmd($cmd, \@files, \@update_output);
         if ($status)
            {
            send_alert("Update -j pre -j post failed for $branch");
            &cli_usage_stats(1, %stats_data);
            exit (1);
            }
         }
      } # end handling modified files

   #
   # Handle removed files
   #
   if (@removed_files)
      {
      my(@files_to_remove) = make_cvsroot_relative(@removed_files);
      pause("About to remove " . join(" ", (@files_to_remove)));
      $num_unlinks = unlink @files_to_remove;
      if ( $num_unlinks != @files_to_remove )
         {
         $error_msg = "\n";
         $error_msg .= "ERROR ($progname): Unable to remove files in merge area.\n";
         $error_msg .= "      $!\n";
         $error_msg .= "      Maybe checkout failed for $branch?\n";
         $error_msg .= "      File(s) to remove are:\n";
         for (@files_to_remove) { $error_msg .= "         $_\n"; }
         $error_msg .= "\n";
         print_and_log $error_msg;
         send_alert($error_msg);
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }

      $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
             " remove ";
      my(@remove_output);
      $status = 0;
      $status = run_cmd($cmd, \@files_to_remove, \@remove_output);
      if ($status)
         {
         send_alert("Unable to cvs remove files for $branch");
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }
      } # end handling removed files

   #
   # Handle added files
   #
   # Could apply *_root and *_start tags here as well, but so far
   # they aren't deemed necessary.  If we do, we should also do it
   # above for the initial branch.
   #
   if (@added_files)
      {
      my(@files_to_add) = make_cvsroot_relative(@added_files);
      pause("About to add " . join(" ", (@files_to_add)));

      #
      # Get the copy originally checked in
      # It would be more efficient to group files by dir
      #
      for (@files_to_add)
         {
         my($file) = $_;
         my($parent_dir) = dirname ($file);

         create_empty_dirs_for_added_files($file);

         #
         # Make sure that $parent_dir/CVS/Tag exists or the cvs add
         # operation will add the file to the trunk and then the
         # commit will abort due to different sticky tags (NSQA-56961).
         #
         my($tag_file) = "$parent_dir/CVS/Tag";
         if ( ! -r "$tag_file" )
            {
            print LOGFILE "+Creating CVS/Tag file for $branch\n";
            if (! open(CVS_TAG, ">$tag_file"))
               {
               $error_msg = "\n";
               $error_msg .= "ERROR ($progname): Failed to create CVS/Tag file,\n";
               $error_msg .= "      $tag_file.\n";
               $error_msg .= "      $!\n";
               $error_msg .= "\n";
               print_and_log $error_msg;
               send_alert($error_msg);
               &cli_usage_stats(1, %stats_data);
               exit (1);
               }
            print CVS_TAG "T${branch}\n";
            close CVS_TAG;
            }

         #
         # A CVS bug prevents a checkout or update with -p on
         # a freshly applied tag that has not already been used
         # (and thus already exists in CVSROOT/val-tags).  This
         # workaround runs rdiff on the file, throwing away the
         # result.  The side effect is the tag gets added to the
         # val-tags file, allowing the following checkout -p to work.
         # See https://ccvs.cvshome.org/issues/show_bug.cgi?id=186
         #
         $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -Q -f" .
                " rdiff -s -r $postmerge_tag \"$file\"";
         undef (@rdiff_output);
         $status = 0;
         $status = run_cmd($cmd, undef, \@rdiff_output);
         if ($status)
            {
            send_alert("Rdiff workaround for co -p -rtag failed");
            &cli_usage_stats(1, %stats_data);
            exit (1);
            }

         #
         # Checkout the postmerge tagged version to stdout and
         # put it in the parent_dir
         #
         $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -q -f" .
                " checkout -p -r $postmerge_tag \"$file\" > \"$file\"";
         pause("About to checkout -p -r post \"$file\"");
         undef (@checkout_output);
         $status = 0;
         $status = run_cmd_wo_redirect($cmd, \@checkout_output);
         if ($status)
            {
            send_alert("Add's checkout -p failed");
            &cli_usage_stats(1, %stats_data);
            exit (1);
            }
         } # end for @files_to_add

      #
      # Add it to this branch.
      # Add won't work outside of a checked-out copy, so chdir into
      # to module and then add; handle binary files separately.
      #
      if (@added_binary_files)
         {
         my(@files) = make_module_relative(@added_binary_files);
         chdir "$merge_dir/$module";
         print LOGFILE "+Current dir is now " . &cwd() . "\n";
         $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f " .
                " add -kb ";

         pause("About to add -kb " . join(" ", (@files)));
         undef (@add_output);
         $status = 0;
         $status = run_cmd($cmd, \@files, \@add_output);
         if ($status)
            {
            send_alert("Add -kb failed");
            &cli_usage_stats(1, %stats_data);
            exit (1);
            }
         }
      if (@added_text_files)
         {
         my(@files) = make_module_relative(@added_text_files);
         chdir "$merge_dir/$module";
         print LOGFILE "+Current dir is now " . &cwd() . "\n";
         $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f " .
                " add ";

         pause("About to add " . join(" ", (@files)));
         undef (@add_output);
         $status = 0;
         $status = run_cmd($cmd, \@files, \@add_output);
         if ($status)
            {
            send_alert("Add failed");
            &cli_usage_stats(1, %stats_data);
            exit (1);
            }
         }
      chdir "$merge_dir";
      print LOGFILE "+Current dir is now " . &cwd() . "\n";
      } # end handling added files

   #
   # cvs -n -q update
   #
   $cmd = "cvs $cvs_debug_arg $cvsroot_arg $gzip_level_arg" .
          " -f -n -q update";

   pause("About to -n -q update");
   undef (@update_output);
   $status = 0;
   $status = run_cmd($cmd, undef, \@update_output, 1);

   my(@merge_added_files, @merge_conflict_files, @merge_modified_files,
      @merge_removed_files, @merge_updated_files);
   parse_cvs_update_output(\@update_output, \@merge_added_files,
                           \@merge_conflict_files, \@merge_modified_files,
                           \@merge_removed_files, \@merge_updated_files);

   if (@merge_conflict_files)
      {
      $error_msg = "\n";
      $error_msg .= "ERROR ($progname): Some files in the merge directory have conflicts.\n";
      $error_msg .= "\n";
      $error_msg .= "      NONE of your files were propagated (see Checkin Summary below).\n";
      $error_msg .= "\n";
      $error_msg .= "      In the merge directory edit the file(s) and resolve the\n";
      $error_msg .= "      conflicts, then run checkin from the merge directory.\n";
      $error_msg .= "\n";
      $error_msg .= "      Merge dir: $merge_dir/$module\n";
      $error_msg .= "\n";
      $error_msg .= "      Files with conflicts:\n";
      for (@merge_conflict_files) { $error_msg .= "         $_\n"; }
      $error_msg .= "\n";
      print_and_log $error_msg;
      print_and_log "   ***** Please note: your checkin comment is saved in $LogDir/comment.orig \n";
      print_and_log "   If you want to reuse the comments you just entered, first fix all errors, ";
      print_and_log "   then run checkin again with the following option: \n\n";
      print_and_log "   -F $LogDir/comment.orig \n\n";
      delete_tags(@files_to_commit);
      send_reminder($error_msg);
      close LOGFILE;
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }

   #
   # Make sure there's something to checkin.
   #
   if ( !@merge_added_files && !@merge_removed_files && !@merge_modified_files )
      {
      if (grep /\S+/, @update_output)
         {
         $error_msg = "\n";
         $error_msg .= "ERROR ($progname): No files in your merge area have been modified.\n";
         $error_msg .= "\n";
         $error_msg .= "      Merge dir: $merge_dir\n";
         $error_msg .= "\n";
         $error_msg .= "      A 'cvs -n -q update' shows:\n";
         for (@update_output) { $error_msg .= "         $_\n"; }
         $error_msg .= "\n";
         print_and_log $error_msg;
         send_alert($error_msg);
         print_and_log "   ***** Please note: your checkin comment is saved in $LogDir/comment.orig \n";
         print_and_log "   If you want to reuse the comments you just entered, first fix all errors, ";
         print_and_log "   then run checkin again with the following option: \n\n";
         print_and_log "   -F $LogDir/comment.orig \n\n";
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }
      else
         {
         $error_msg = "\n";
         $error_msg .= "ERROR ($progname): No files in your merge area have been modified.\n";
         $error_msg .= "      Perhaps $branch already contains these changes?\n";
         $error_msg .= "      No further propagation will be attempted.\n";
         $error_msg .= "\n";
         $error_msg .= "      Merge dir: $merge_dir\n";
         $error_msg .= "\n";
         print_and_log $error_msg;
         send_alert($error_msg);
         print_and_log "   ***** Please note: your checkin comment is saved in $LogDir/comment.orig \n";
         print_and_log "   If you want to reuse the comments you just entered, first fix all errors, ";
         print_and_log "   then run checkin again with the following option: \n\n";
         print_and_log "   -F $LogDir/comment.orig \n\n";
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }
      }
   else
      {
      #
      # checkin files
      #
      my($committime) = time;
      $COMMITID = strftime("%Y%m%d%H%M%S", localtime($committime));
      $COMMITID .= "_${branch}_${HOSTNAME}.$$";
      $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg $gzip_level_arg" .
             " $ignore_cvsrc_arg" .
             " -s DEBUG_LEVEL=$debug_level" .
             " -s BRANCH=$branch" .
             " -s MODULE=$module" .
             " -s BIRT_NO_ACCESS=$BIRT_NO_ACCESS" .
             " -s BIRT_NO_MAIL=$BIRT_NO_MAIL" .
             " -s BIRT_NO_STR=$BIRT_NO_STR" .
             " -s BIRT_CVSRECON=$BIRT_CVSRECON" .
             " -s CHECKINID=$CHECKINID" .
             " -s COMMITID=$COMMITID" .
             " -s HOSTNAME=$HOSTNAME" .
             " -s HOSTIP=$HOSTIP" .
             " -s USERID=\"$USERID\"" .
             " -s WORKDIR=\"$merge_dir\"" .
             " commit $comment_file_arg ";

      pause("About to commit to $branch");
      my(@commit_output);
      $status = 0;
      $status = run_cmd($cmd, undef, \@commit_output);
      display_commit_output(\@commit_output);
      if ($status)
         {
         send_alert("Commit to $branch failed");
         print_and_log "   ***** Please note: your checkin comment is saved in $LogDir/comment.orig \n";
         print_and_log "   If you want to reuse the comments you just entered, first fix all errors, ";
         print_and_log "   then run checkin again with the following option: \n\n";
         print_and_log "   -F $LogDir/comment.orig \n";
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }
      }

   #
   # Remove the merge_dir; we're done with it and everything worked.
   #
   chdir "$working_dir";
   print LOGFILE "+Current dir is now " . &cwd() . "\n";
   if (!$debug)
      {
      rmtree("$merge_dir");
      }

   $nextrev = get_nextrev($branch);

   } # end while nextrev != NONE

delete_tags(@files_to_commit);

print_and_log checkin_summary();

close LOGFILE;

remove_logdir();

&cli_usage_stats(0, %stats_data);

exit (0);

#
# END MAIN
#

#======================================================================

#
# BEGIN SUBROUTINES
#

#------------------------------
# sub initialize_variables()
#------------------------------
sub initialize_variables
{
$USAGE = "
USAGE: checkin -H
       checkin [-D debug_level] [-F file] [-d root] [-f] [-l] [-m msg]
               [-n] [-p prop_chain] [-y] [-z gzip_level] [files...]
       where: -H    prints a help message
              -D    specifies a debugging level (default is 0)
                    use '-D ?' to get an explanation of debugging levels
              -F    specifies a file to read checkin comments from;
                    you will not be given a chance to edit this file
              -d    specifies the CVSROOT to use (overrides \$CVSROOT)
              -f    specifies to not use ~/.cvsrc
              -l    specifies local mode (run only in current directory)
              -m    specifies the comment string
              -n    specifies not to do any real action
              -p    specifies a propagation chain to use.  Branches are
                    separated by colons.  The propagation chain must
                    include the current revision.  If 'NONE' is specified,
                    no propagation is attempted.
              -y    specifies to take the defaults to all prompts
              -z    specifies the compression level to use during client-
                    server communication

       Checkin uses the first editor found in the following list of
       environment variables to obtain comments from the user.  The
       full path to the editor must be provided.
                   1) \$CVSEDITOR
                   2) \$VISUAL
                   3) \$EDITOR
                   4) Default of vi (Unix) or notepad.exe (Win)
";

#
# Define debugging levels.
#
$debug_level_map = "
DEBUG LEVEL MAP:  The debugging level is the decimal number represented
                  by a 3-bit binary sequence.  Each bit toggles a section
                  of debugging code.  Here is the map:

                  Level  CVS  *info  checkin
                  --------------------------
                    0     N     N       N    (default)
                    1     N     N       Y
                    2     N     Y       N
                    3     N     Y       Y
                    4     Y     N       N
                    5     Y     N       Y
                    6     Y     Y       N
                    7     Y     Y       Y

";

#
# Initialize exceptions
#
$BIRT_NO_ACCESS = defined($ENV{"BIRT_NO_ACCESS"}) &&
                  ($ENV{"BIRT_NO_ACCESS"} == 1);
$BIRT_NO_MAIL = defined($ENV{"BIRT_NO_MAIL"}) &&
                ($ENV{"BIRT_NO_MAIL"} == 1);
$BIRT_NO_STR = defined($ENV{"BIRT_NO_STR"}) &&
                ($ENV{"BIRT_NO_STR"} == 1);
$BIRT_CVSRECON = defined($ENV{"BIRT_CVSRECON"}) &&
                  ($ENV{"BIRT_CVSRECON"} == 1);

#
# Make sure $TOOLS_DIRECTORY/bin is on path
#
if ("$ENV{'PATH'}" =~ m/;/)
   {
   $ENV{'PATH'} .= ";$ENV{'TOOLS_DIRECTORY'}\\bin";
   }
else
   {
   $ENV{'PATH'} .= ":$ENV{'TOOLS_DIRECTORY'}/bin";
   }

#
# Define the maximum number of files that ONE cvs command should handle.
# see STR NSQA-57850.
#
$MAX_NUM_FILES = 40;     # 40 is chosen arbitrarily now. The real limitation
                         # is the dirname/filename list length in characters.

#
# Define a counter to capture each cvs command's output into separate files.
#
$run_cmd_counter = 1;

#
# Parse command line.
#
$command_line = "$0 " . join(" ", @ARGV);
$debug_level = 0;
$take_defaults = 0;

$options = "D:F:Hd:flm:np:yz:";
if ( ! Getopts($options) )
   {
   &cli_usage_stats(0, %stats_data);
   die "$USAGE";
   }

#
# References to defeat perl -w
#
$opt_H = $opt_H;
$opt_f = $opt_f;
$opt_l = $opt_l;
$opt_n = $opt_n;
$opt_y = $opt_y;
@files_to_commit = ();
$checkin_with_file_list = 0;

if ($opt_D)   { $debug_level = $opt_D; }
if ($opt_H)   { print $USAGE; &cli_usage_stats(0, %stats_data); exit (0); }
if ($opt_d)   { $cvsroot_arg = "-d $opt_d"; }
if ($opt_f)   { $ignore_cvsrc_arg = "-f"; }
if ($opt_l)   { $local_mode_arg = "-l"; }
if ($opt_m)   { $message_string = "$opt_m";
                $message_string_arg = "-m \"$opt_m\""; }
if ($opt_n)   { $no_action_arg = "-n"; }
if ($opt_p)   { $propagation_chain = "$opt_p"; }
if ($opt_y)   { $take_defaults = 1; }
if ($opt_z)   { $gzip_level_arg = "-z $opt_z"; }
if (@ARGV)    { @files_to_commit = @ARGV; $checkin_with_file_list = 1;}

#
# Simplify relative pathnames
#
if ($checkin_with_file_list)
   {
   @files_to_commit = simplify_relative_paths(@files_to_commit);
   }
}


#------------------------
# sub validate_options()
#------------------------
sub validate_options
{
#
# Validate debug_level
#
if ("$debug_level" eq "\?" )
   {
   print "$debug_level_map";
   &cli_usage_stats(0, %stats_data);
   exit (0);
   }
if ($debug_level > 7 || $debug_level < 0)
   {
   print "\n";
   print "ERROR ($progname): Illegal debugging level.  Valid levels are:\n";
   print "$debug_level_map";
   print "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# Setup debugging
#
$debug = 0;
$cvs_debug_arg = "";
if ( $debug_level & 1 )
   {
   print "Debugging of $progname enabled.\n";
   $debug = 1;
   }
if ( $debug_level & 2 )
   {
   print "Debugging of cvs \*info scripts enabled.\n";
   }
if ( $debug_level & 4 )
   {
   print "Debugging of cvs commands enabled.\n";
   }

print "\nRUNNING $progname\n\n" if ($debug);
print "PATH is $ENV{'PATH'}\n" if ($debug);

$working_dir = &cwd();
$LogDir = "$working_dir/Checkin.$$";
print "Working dir is $working_dir\n" if ($debug);

#
# Validate CVSROOT
#
if (defined($cvsroot_arg))
   {
   #
   # We're still going to pass along $cvsroot_arg to cvs commands,
   # but also set $CVSROOT for all child processes just to make sure
   # nothing is missed.
   #
   my($new_cvsroot) = "$cvsroot_arg";
   $new_cvsroot =~ s/^\s*-d\s+//;
   $ENV{CVSROOT} = "$new_cvsroot";
   }
else
   {
   #
   # Try to get CVS/Root from the working area.
   #
   # The CVS.pm routine will print an error and return undef if unable
   # to determine the module.
   #
   $ENV{CVSROOT} = get_cvsroot_from_workdir("$working_dir");
   if (! defined ($ENV{CVSROOT}) )
      {
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }
   }

if ("$ENV{CVSROOT}" !~ /:pserver:/)
   {
   print "\n";
   print "ERROR ($progname): pserver is the only supported access method.\n";
   print "      Your \$CVSROOT is $ENV{CVSROOT}\n";
   print "      but it should begin with :pserver:\n";
   print "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

#
# ENHANCE - NSQA-57141
#
# It would be a nice security restriction if we could verify that
# the user in CVSROOT is the same as the user invoking checkin.
# The problem here is that since we have remote CVS users that are
# not in our local RTP domain, they have non-standard CVS userid's
# that *do not* match their login ids.
#
# There is also the following problem:  Someone can make a checkin
# and it will use CVSROOT from CVS/Root, but the propagation(s)
# will use $CVSROOT from the environment (assuming -d wasn't used).
#
# I've seen two effects of this.  1) When one user checkins in
# another's code, the first checkin shows as from the developer
# that owned the working area, but the subsequent propagations show
# as being from the person that ran the checkin tool, and 2) If a
# user is logged in as Administrator (or anyone who doesn't have access),
# the first checkin will work, but the propagations will fail since
# Administrator doesn't have appropriate archive privilege.
#

print "CVSROOT is $ENV{CVSROOT}\n" if ($debug);

$user = ( split( /:/, $ENV{CVSROOT}) )[2];
$user = ( split(/@/, $user) )[0];
print "user is $user\n" if ($debug);

#
# Now that we know who this is, we might not want to allow them
# to use exceptions.  This whole exception mechanism was a quick-and-dirty
# scheme that needs to be rewritten to access an exceptions database.
#
if ( ! allow_exception($user) )
   {
   $BIRT_NO_ACCESS = 0;
   $BIRT_NO_MAIL = 0;
   $BIRT_NO_STR = 0;
   $BIRT_CVSRECON = 0;
   }

#
# Validate some other command line options.
#
if (defined($comment_file) && ! -r "$comment_file" )
   {
   print "\n";
   print "ERROR ($progname): Comment file is not readable.\n";
   print "      Cannot read $comment_file.\n";
   print "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }

}

#------------------------
# sub validate_prop_chain()
#------------------------
sub validate_prop_chain()
{
#
# Validate propagation chain; this is weak for now
#
# This would have to change to allow propagation into patch
# branches or foyers.
#
if (defined($propagation_chain))
   {
   if ( $propagation_chain =~ /[^-:\w]/ )
      {
      print "\n";
      print "ERROR ($progname): Invalid propagation chain, $propagation_chain\n";
      print "      Propagation chain should include branches separated by colons.\n";
      print "\n";
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }
   if ( ( $propagation_chain !~ /$branch$/ ) &&
        ( "$propagation_chain" ne "NONE" ) &&
        ( $propagation_chain !~ /$branch:([^:]+):?/ ) )
      {
      print "\n";
      print "ERROR ($progname): Invalid propagation chain, $propagation_chain\n";
      print "      Propagation chain must include the current branch, $branch.\n";
      print "\n";
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }
   #
   # Chop off prefix of propagation chain if irrelevant for this branch.
   # This way the propagation chain can be used to indicate all expected
   # commits.
   #
   if ($propagation_chain =~ /.*:$branch(:|$)/)
      {
      $propagation_chain =~ s/.*:($branch(:|$))/$1/;
      print "WARNING: Ignoring propagation chain before current branch.\n";
      print "WARNING: Propagation chain is now $propagation_chain.\n";
      print "\n";
      }

   #
   # Check additional auto-propagation restrictions.
   #
   if ( (get_focusinfo_field($focus, $branch, 'enforce_propagation_restrictions')) and
        ("$propagation_chain" ne "NONE") )
      {
      my($default_prop_chain) = get_propagation_chain($branch, $module);
      my($count) = 1;
      my(%default_prop_chain_map);
      for (split /:/, $default_prop_chain)
         {
         $default_prop_chain_map{$_} = $count++;
         }

      #
      # 1) $propagation_chain must be an ordered subset of the default chain.
      #    Allows for skipping of branches.
      # 2) For foyers and other unofficial branches the default chain will just be the branch itself,
      #    so this effectively disables auto-prop out of a foyer.
      # 3) Since no default chain for an official branch includes any foyers or unofficial branches,
      #    this effectively disables auto-prop into a foyer.
      #
      my($last_branch_number) = 0;
      for (split /:/, $propagation_chain)
         {
         my($branch_number) = $default_prop_chain_map{$_} || "0";
         if ($branch_number > $last_branch_number)
            {
            #
            # This branch appears later in the default chain than the previous one,
            # so things are good.  Update the last number and go to the next one.
            #
            $last_branch_number = $branch_number;
            next;
            }
         else
            {
            #
            # Other cases are errors.
            #
            # If $branch_number == 0, then
            # this is a branch not in the default chain.
            #
            # If $branch_number == $last_branch_number, then
            # the same branch appears twice consecutively in the chain.
            #
            # If $branch_number < $last_branch_number, then
            # these branches are out of order (backwards prop).
            #
            print "\n";
            print "ERROR ($progname): Invalid propagation chain, $propagation_chain\n";
            print "      Backwards automatic propagation, propagation into foyers, and\n";
            print "      propagation out of foyers is not allowed for this checkin.\n";
            print "\n";
            print "      Propagation chain must be an ordered subset of:\n";
            print "\n";
            print "      $default_prop_chain\n";
            print "\n";
            &cli_usage_stats(1, %stats_data);
            exit (1);
            }
         } #end foreach branch in propagation_chain
      } #endif backwards auto prop not allowed
   } #endif prop chain given on command line
else
   {
   #
   # Figure out the default to use for this checkin.
   #
   $propagation_chain = get_propagation_chain($branch, $module);
   }

}


#------------------------
# sub get_nextrev($currentrev)
#------------------------
sub get_nextrev
{
#
# Determine the next revision in the propagation chain.
#
my($currentrev) = @_;
my($nextrev);

if ( ( $propagation_chain =~ /$currentrev$/ ) ||
     ( "$propagation_chain" eq "NONE" ) ||
     ( "$current_rev" eq "trunk" ) )
   {
   $nextrev = "NONE";
   }
elsif ( $propagation_chain =~ /$currentrev:([^:]+):?/ )
   {
   $nextrev = "$1";
   }
else
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): Cannot determine the next revision in the\n";
   print_and_log "      propagation chain.  The propagation chain must include the\n";
   print_and_log "      current revision or be 'NONE'.\n";
   print_and_log "\n";
   print_and_log "      Current revision is $currentrev\n";
   print_and_log "      Propagation chain is $propagation_chain\n";
   print_and_log "\n";
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }
return ($nextrev);
}


#------------------------
# sub parse_cvs_update_output(\@update_output, \@added_files, \@conflict_files,
#                         \@modified_files, \@removed_files, \@updated_files)
#------------------------
sub parse_cvs_update_output
{
#
# Valid cvs update output lines are:
#
#   A file      file to be added
#   C file      file has/will have conflicts
#   M file      file is locally modified; or remotely and
#           locally modified, but merged w/o conflict
#   P file      file is remotely changed; will be patched
#   R file      file to be removed
#   U file      file is remotely changed; will be updated
#
my($update_output_ref, $a_ref, $c_ref, $m_ref, $r_ref, $u_ref) = @_;
@$update_output_ref = grep (s/\n$//, @$update_output_ref);
@$a_ref = grep (s/^A //, @$update_output_ref);
@$c_ref = grep (s/^C //, @$update_output_ref);
@$m_ref = grep (s/^M //, @$update_output_ref);
@$r_ref = grep (s/^R //, @$update_output_ref);
@$u_ref = grep (s/^(P|U) //, @$update_output_ref);
}


#------------------------
# sub apply_premerge_tag(@files_to_tag)
#------------------------
sub apply_premerge_tag
{
my(@files_to_tag) = @_;
return if (!@files_to_tag);
#
# cvs tag merge_jade_sharpe_2001-02-15_114900_pre files
# can't tag files to be added
#
my($now);
($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
       localtime(time);
$now = sprintf ("%4.4d-%2.2d-%2.2d_%2.2d%2.2d%2.2d",
       $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
$premerge_tag = "merge_${branch}_${user}_${now}_pre";

$cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
       " tag -F $premerge_tag ";

my(@tag_output);
my($status) = 0;
$status = run_cmd($cmd, \@files_to_tag,  \@tag_output);

if ($status)
   {
   #
   # Delete the tags which have been applied
   #
   delete_tags(@files_to_tag);
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }
}


#------------------------
# sub apply_postmerge_tag(@files_to_tag)
#------------------------
sub apply_postmerge_tag
{
my(@files_to_tag) = @_;
return if (!@files_to_tag);
#
# cvs tag merge_jade_sharpe_2001-02-15_1151_post files
#
my($now);
($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
$now = sprintf ("%4.4d-%2.2d-%2.2d_%2.2d%2.2d%2.2d",
             $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
$postmerge_tag = "merge_${branch}_${user}_${now}_post";

$cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
       " tag -F $postmerge_tag ";

my(@tag_output);
my($status) = 0;
$status = run_cmd($cmd, \@files_to_tag,  \@tag_output);

if ($status)
   {
   #
   # Delete the tags anyway since the premerge tags aren't needed
   #
   delete_tags(@files_to_tag);
   &cli_usage_stats(1, %stats_data);
   exit (1);
   }
}


#------------------------
# sub delete_tags(@files)
#------------------------
sub delete_tags
{
my($tag, $status);
my(@tags_to_delete, @tag_output);
@tags_to_delete = ($premerge_tag, $postmerge_tag);
my(@files) = @_;
return if (!@files);
@files = make_cvsroot_relative(@files);

for $tag (@tags_to_delete)
   {
   #
   # If we didn't apply the postmerge_tag yet, this could be null.
   #
   next if ($tag =~ /^\s*$/);

   $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
          " rtag -a -d $tag ";

   undef (@tag_output);
   $status = 0;
   $status = run_cmd($cmd, \@files, \@tag_output, 1);

   if ($status)
      {
      #
      # Continue even if tag deletion returned an error
      # but email the error to cvsadm for manual cleanup.
      #
      print LOGFILE "+Sending tag deletion failure email\n";
      my($to, $subject, $message);
      $to = $CVS_ADMIN_EMAIL;
      $subject = "checkin: failed to delete tags";
      $message = "Checkin failed to delete merge tags.  You should manually delete\n";
      $message .= "these tags to prevent tag-pollution in the archives.\n";
      $message .= "\n";
      $message .= "User:   $user\n";
      $message .= "LogDir: $LogDir\n";
      $message .= "\n";
      $message .= "$cmd\n";
      for (@files)
        {
        $message .= "     $_\n";
        }
      $message .= "\n";

      for (@tag_output)
        {
        $message .= $_;
        }
      if ( notify($to, $subject, $message) )
         {
         print LOGFILE "+Message sent OK to $to\n";
         }
      else
         {
         print LOGFILE "+Message send FAILED to $to\n";
         }
      }
   }
}


#------------------------
# sub make_cvsroot_relative(@files)
#------------------------
sub make_cvsroot_relative
{
my(@files) = @_;
my($cvs_repository_with_escapes);

$cvs_repository_with_escapes = quotemeta("$cvs_repository");
grep { if (! m/^$cvs_repository_with_escapes\// )
          {
          s/^/$cvs_repository\//;
          }
     } @files;
return (@files);
}


#------------------------
# sub make_module_relative(@files)
#------------------------
sub make_module_relative
{
my(@files) = @_;

@files = make_cvsroot_relative(@files);

grep { if (m/^$module\// )
          {
          s/^$module\///;
          }
     } @files;
return (@files);
}



#------------------------
# sub pause($message)
#------------------------
sub pause
{
#
# Pausing is enabled by turning on debug (and not using -y).
# Hit any key (preferably Enter to keep the output pretty) to continue.
#
return if (! $debug);
return if ($take_defaults);
my($msg) = @_;
print_and_log "Pausing: $msg";
$_ = getc;
print LOGFILE "\n";
}


#------------------------
# sub print_and_log LIST
#   Print the given list to STDOUT and to LOGFILE
#------------------------
sub print_and_log (@)
{
print STDOUT @_;
print LOGFILE @_;
}


#------------------------
# sub display_commit_output()
#------------------------
sub display_commit_output
{
my($output_ref) = @_;
my($file, $rev);
for (@$output_ref)
   {
   if (m!$ARCHIVE_ROOT/([^,]+),v\s+!)
      {
      $file = $1;
      $file =~ s!\/Attic!!;
      }
   if ((m!new revision:\s+([^;]+);!) || (m!initial revision:\s+([\d\.]+)\s*!))
      {
      $rev = $1;
      print_and_log "   $file ($rev)\n";

      #
      # Keep track of all commits done
      #
      $commits_done{$file} .= "${branch}:";

      undef ($file);
      undef ($rev);
      }
   }
}


#------------------------
# sub signal_handler
#------------------------
sub signal_handler
{
my($signal) = @_;
print_and_log "Caught a SIG$signal -- cleaning up.\n";
print_and_log "Contact $CVS_ADMIN_EMAIL if you require additional assistance.\n\n";
print_and_log "WorkDir: $working_dir.\n";
print_and_log "LogDir:  $LogDir\n";

delete_tags(@files_to_commit);
if ( -s "$LogDir/cmd${run_cmd_counter}.stdout")
   {
   print LOGFILE "Stdout from interrupted command:\n";
   open(CMDSTDOUT, "$LogDir/cmd${run_cmd_counter}.stdout");
   while (<CMDSTDOUT>)
      {
      print LOGFILE;
      }
   close CMDSTDOUT;
   }
if ( -s "$LogDir/cmd${run_cmd_counter}.stderr")
   {
   print LOGFILE "Stderr from interrupted command:\n";
   open(CMDSTDERR, "$LogDir/cmd${run_cmd_counter}.stderr");
   while (<CMDSTDERR>)
      {
      print LOGFILE;
      }
   close CMDSTDERR;
   }

close LOGFILE;
&cli_usage_stats(1, %stats_data);
exit (1);
}


#------------------------
# sub send_alert ("error text")
#     Send an alert error message to cvsadm including all debug output
#------------------------
sub send_alert
{
my($error) = @_;
my($to, $subject, $filename);

send_reminder($error);

$filename = "$LogDir/mailfile";
open(MAILFILE, ">$filename");

$to = $CVS_ADMIN_EMAIL;
$subject = "ALERT: Propagation Failure for $module from $user";

print LOGFILE "+Sending propagation failure alert to $to.\n";
close LOGFILE;

print MAILFILE "\n${user}'s checkin failed to propagate to $branch!\n\n";
print MAILFILE "$error\n";
print MAILFILE checkin_summary();
print MAILFILE "\n";

print MAILFILE "The following tags were used during this merge attempt.\n";
print MAILFILE "They should be manually deleted when no longer needed.\n";
print MAILFILE "   Premerge:  $premerge_tag\n";
print MAILFILE "   Postmerge: $postmerge_tag\n";
print MAILFILE "\n";

print MAILFILE "===============================================================\n";
print MAILFILE "Log:\n\n";
if ( -s "$LogDir/log" )
   {
   open(LOG, "$LogDir/log");
   while (<LOG>)
      {
      print MAILFILE;
      }
   close LOG;
   }
else
   {
   print MAILFILE "log file empty or does not exist.\n";
   }

print MAILFILE "===============================================================\n";
print MAILFILE "Environment:\n\n";
if ( -s "$LogDir/environment" )
   {
   open(ENVIRONMENT, "$LogDir/environment");
   while (<ENVIRONMENT>)
      {
      print MAILFILE;
      }
   close ENVIRONMENT;
   }
else
   {
   print MAILFILE "environment file empty or does not exist.\n";
   }

print MAILFILE "===============================================================\n";
close MAILFILE;

#
# Can't log results of this send since the log is closed because
# we are sending it.
#
notify_using_file($to, $subject, $filename);
}


#------------------------
# sub send_reminder
#     Send a reminder email to the user stating what propagations
#     are required
#------------------------
sub send_reminder
{
my($error) = @_;
my($to, $subject, $filename, $summary, $user_email);
$filename = "$LogDir/reminder";
my ($follow_up_by) = strftime("%a %b %e %H:%M:%S %Z %Y", localtime(time+86400)); # In 24 hours
open(REMINDER, ">$filename");

$user_email = cvsid_to_email($user);
$to = "$user_email $CVS_ADMIN_EMAIL";
$subject = "Propagation Failure for $module";

print REMINDER <<EOF;
All expected propagations were not completed.  It is the
responsibility of $user to arrange to merge these changes
into the appropriate branches as necessary.

$error

In the summary below, each file that was changed is listed
followed by the branches it was successfully checked-in to.
Compare this to the expected branch list.  Files with failures
are marked with '!'.

EOF
print REMINDER checkin_summary();
print REMINDER <<EOF;

WorkDir:  $working_dir
LogDir:   $LogDir
MergeDir: $merge_dir

EOF
if ( -r "$LogDir/comment.orig" )
   {
   print REMINDER "Checkin comment:\n";
   if ( -s "$LogDir/comment.orig" )
      {
      open(COMMENT, "$LogDir/comment.orig");
      while (<COMMENT>)
         {
         print REMINDER;
         }
      close COMMENT;
      }
   else
      {
      print REMINDER "comment.orig file empty or does not exist.\n";
      }
   }
close REMINDER;

print LOGFILE "+Sending propagation reminder email to $to.\n";
if ( notify_with_follow_up_using_file("$to", "$subject", "$follow_up_by", "$filename") )
   {
   print LOGFILE "+Message sent OK to $to\n";
   }
else
   {
   print LOGFILE "+Message send FAILED to $to\n";
   }
}


#------------------------
# sub checkin_summary
#     Return a summary of what files were committed where
#     Indicate failures with "!"
#------------------------
sub checkin_summary
{
#
# @files_to_commit is all files to commit
# $propagation_chain is all places to commit (with possibly extra
#   stuff at the front)
# %commits_done is an array keyed by cvsroot-relative filenames
#   where the value indicates what revs it was propagated to
#   eg. $commits_done{admin/adm/foo.c} = "opal:garnet:"
#

#
# If we only committed to one branch, there is really no need
# to summarize.
#
if (("$propagation_chain" eq "NONE") ||
    ("$propagation_chain" eq "$branch"))
   {
   return;
   }

my($branches_committed_to, $errors, $summary);
$errors = 0;
my(@files);
@files = make_cvsroot_relative(@files_to_commit);
$summary = "\nCheckin Summary (expected $propagation_chain)\n";
$summary .= "===============\n";
for (sort @files)
   {
   undef ($branches_committed_to);
   $branches_committed_to = $commits_done{$_};
   $branches_committed_to =~ s/:$//;
   if ("$branches_committed_to" eq "$propagation_chain" )
      {
      $summary .= "   $_ ($branches_committed_to)\n";
      }
   else
      {
      $summary .= " ! $_ ($branches_committed_to)\n";
      $errors++;
      }
   }
$summary .= "\n";
if ($errors == 1)
   {
   $summary .= "ERROR: $errors file commit error!  See above.\n";
   }
elsif ($errors > 1)
   {
   $summary .= "ERROR: $errors file commit errors!  See above.\n";
   }

return ($summary);
}


#------------------------
# sub find_binary_files(\@all_files, \@binary_files, \@text_files)
#     Separates @all_files into @binary_files and @text_files based
#     on whether or not the -kb sticky option is set.
#
#     Assumes @all_files contains pathnames relative to current dir
#     and current dir is a checkout area with CVS subdirs.
#------------------------
sub find_binary_files
{
my($all_files_ref, $binary_files_ref, $text_files_ref) = @_;
my(@all_dirs);
my(%is_binary);

#
# Get all directories
#
for $filepath (sort @$all_files_ref)
   {
   push(@all_dirs, dirname($filepath));
   }
@all_dirs = uniq(@all_dirs);

#
# Read in all data for all directories for given files
#
for $dir (@all_dirs)
   {
   if (! open(ENTRIES, "$dir/CVS/Entries") )
      {
      print "\n";
      print "ERROR ($progname): Cannot open $dir/CVS/Entries\n";
      print "      $!\n";
      print "\n";
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }
   while (<ENTRIES>)
      {
      chop($_);
      next if /^D/os;  # skip directories
      next if /^\s*$/os;  # skip whitespace
      if (m!\s*/(.*)/.*/.*/(.*)/.*\s*$!os)
         {
         my ($filename) = $1;
         my ($sticky_options) = $2;
         if ( "$dir" !~ m!^\.$! )
            {
            $filename = "$dir/$filename";
            }
         if ("$sticky_options" =~ /kb/)
            {
            $is_binary{"$filename"} = 1;
            }
         else
            {
            $is_binary{"$filename"} = 0;
            }
         }
      } #end while reading Entries
   close ENTRIES;
   } #end foreach dir

#
# Split the array
#
for (sort @$all_files_ref)
   {
   if ($is_binary{$_})
      {
      push(@$binary_files_ref, $_);
      }
   else
      {
      push(@$text_files_ref, $_);
      }
   }
}


#------------------------
# sub remove_logdir()
#       Removes $LogDir and all contents.
#------------------------
sub remove_logdir
{
close LOGFILE;

#
# If no debugging was enabled, delete the logs.
#
if ( $debug_level == 0 )
   {
   rmtree("$LogDir");
   }
}


#------------------------
# sub get_checkin_comment_from_user()
#       Provides the user with a template checkin comment in an editor
#       and allows them to enter a checkin comment.
#       Returns comment filename
#------------------------
sub get_checkin_comment_from_user
{
my($editor,$template,$comment_file);

#
# Use the same rules CVS uses to determine which editor to use.
# Also make sure the editor is executable.  If not, fallback to default.
#
if (defined($ENV{'CVSEDITOR'}))
   {
   print LOGFILE "+Checking user-defined editor (\$CVSEDITOR)...";
   if (-x "$ENV{'CVSEDITOR'}")
      {
      $editor = $ENV{'CVSEDITOR'};
      print LOGFILE "OK\n";
      }
   else
      {
      print_and_log "WARNING: Unable to execute \$CVSEDITOR, $ENV{'CVSEDITOR'}.\n";
      }
   }
elsif (defined($ENV{'VISUAL'}))
   {
   print LOGFILE "+Checking user-defined editor (\$VISUAL)...";
   if (-x "$ENV{'VISUAL'}")
      {
      $editor = $ENV{'VISUAL'};
      print LOGFILE "OK\n";
      }
   else
      {
      print_and_log "WARNING: Unable to execute \$VISUAL, $ENV{'VISUAL'}.\n";
      }
   }
elsif (defined($ENV{'EDITOR'}))
   {
   print LOGFILE "+Checking user-defined editor (\$EDITOR)...";
   if (-x "$ENV{'EDITOR'}")
      {
      $editor = $ENV{'EDITOR'};
      print LOGFILE "OK\n";
      }
   else
      {
      print_and_log "WARNING: Unable to execute \$EDITOR, $ENV{'EDITOR'}.\n";
      }
   }

if (! defined($editor))
   {
   print LOGFILE "+Using default editor\n";
   if ( "$^O" =~ /win/i )
      {
      $editor = "notepad.exe";
      }
   else
      {
      $editor = "vi";
      }
   }

#
# Get the template from Template.pm via FocusInfo.pm.
#
$comment_file = "$LogDir/comment.orig";
$template = get_checkin_template($branch, $module);
if (!open(COMMENT_FILE_ORIG, ">$comment_file"))
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): Cannot open file $comment_file for writing.\n";
   print_and_log "      $!\n";
   &cli_usage_stats(1, %stats_data);
   exit(1);
   }
print COMMENT_FILE_ORIG "$template";
close COMMENT_FILE_ORIG;
chmod 0666, "$comment_file";

print LOGFILE "+Invoking $editor \"$comment_file\"\n";

#
# Don't even look at the exit status since some versions of vi
# exit with the number of "errors" made while editing (like a
# failed regexp match).
#
system("$editor", "$comment_file");

#
# Now strip out lines that begin with CVS
#
if (!open(COMMENT_FILE_ORIG, "$comment_file"))
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): Cannot open file $comment_file.\n";
   print_and_log "      $!\n";
   &cli_usage_stats(1, %stats_data);
   exit(1);
   }
if (!open(COMMENT_FILE_TMP, ">$LogDir/comment.tmp"))
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): Cannot open file $LogDir/comment.tmp.\n";
   print_and_log "      $!\n";
   &cli_usage_stats(1, %stats_data);
   exit(1);
   }
while (<COMMENT_FILE_ORIG>)
   {
   unless (/^CVS:/)
      {
      print COMMENT_FILE_TMP $_;
      }
   }
close COMMENT_FILE_ORIG;
close COMMENT_FILE_TMP;
rename ("$LogDir/comment.tmp", "$comment_file");

return ("$comment_file");
}


#------------------------
# sub create_empty_dirs_for_added_files($file)
#       will do
#       1) check if $parent_dir exists, where $parent_dir = dirname($file).
#          return if it does exist.
#       2) use checkout if the parent dir does not exist.
#       3) After the checkout, check if $parent_dir exists again.
#          return if it exists.
#       4) Try to back up a directory by calling
#            create_empty_dirs_for_added_files($parent_dir)
#       5) create the parent dir and 'cvs add' it.
#
# This function is called in the "Handle added files" section (when
# processing new file propagations) and it is also called recursively
# to walk a tree.
#
#------------------------
sub create_empty_dirs_for_added_files
{
my($file) = @_;
my($parent_dir)  = dirname ($file);
my($status);

#
# Use checkout if parent dir does not exist
# We just need a directory with a branch tag so the
# add will be applied to the correct branch.
#
if (! -d "$parent_dir")
   {
   $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f" .
          " checkout -l -r $branch \"$parent_dir\"";
   pause("About to checkout -l -r $branch \"$parent_dir\"");
   undef (@checkout_output);
   $status = 0;
   $status = run_cmd($cmd, undef, \@checkout_output);
   if ($status)
      {
      send_alert("Add failed to checkout parent dir");
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }

   #
   # Clean up the tree if necessary (workaround to samba bug)
   #
   pause("About to prune $merge_dir/$module");
   prune_cvs_tree("$merge_dir/$module");

   #
   # If there were no files in $parent_dir on $branch branch,
   # then the checkout above would be like a noop (but still
   # return success).  This must be the first file for this
   # branch in that directory.  Try to back up a directory.
   #
   if ( (! -d "$parent_dir") && "$parent_dir" eq "$module" )
      {
      $error_msg = "\n";
      $error_msg .= "ERROR ($progname): Add failed to checkout any ancestor dir.\n";
      $error_msg .= "      Seek help from $CVS_ADMIN_EMAIL.\n";
      $error_msg .= "\n";
      print_and_log $error_msg;
      send_alert($error_msg);
      &cli_usage_stats(1, %stats_data);
      exit (1);
      }
   elsif ( (! -d "$parent_dir") && "$parent_dir" ne "$module" )
      {
      #
      # Try to back up a directory by calling
      #        create_empty_dirs_for_added_files($parent_dir)
      # If something goes wrong, it will exit during the call.
      #
      create_empty_dirs_for_added_files($parent_dir);

      #
      # Now create the parent dir and 'cvs add' it.
      #
      chdir "$merge_dir/$module";
      print  LOGFILE "+Current dir is now " . &cwd() . "\n";
      my($parent_dir_module_relative) = $parent_dir;
      $parent_dir_module_relative =~ s!^$module/!!;
      mkdir($parent_dir_module_relative, 0777);
      $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -f " .
             " add \"$parent_dir_module_relative\"";

      pause("About to add $parent_dir_module_relative");
      undef (@add_output);
      $status = 0;
      $status = run_cmd($cmd, undef, \@add_output);
      if ($status)
         {
         send_alert("Add failed to add parent dir");
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }
      chdir "$merge_dir";
      print LOGFILE "+Current dir is now " . &cwd() . "\n";

      #
      # If we still don't have a parent_dir, we have to exit.
      # But is this possible at this stage?
      #
      if ( ! -d "$parent_dir" )
         {
         $error_msg = "\n";
         $error_msg .= "ERROR ($progname): Add failed to checkout any ancestor dir.\n";
         $error_msg .= "      Seek help from $CVS_ADMIN_EMAIL.\n";
         $error_msg .= "\n";
         print_and_log $error_msg;
         send_alert($error_msg);
         &cli_usage_stats(1, %stats_data);
         exit (1);
         }
      }
   }
}


#------------------------
# sub run_cmd($cmd, \@files, \@output[, $quiet])
#      1) runs $cmd over @files. If @files is empty, then runs cvs command
#         in the current directory.
#      2) overwrites @output with output from command
#      3) returns $status
#
#      Uses and then increments global variable $run_cmd_counter
#      to keep output from multiple invocations separate.
#------------------------
sub run_cmd
{
my($cmd, $files_ref, $output_ref, $quiet) = @_;
my(@files) = @$files_ref;
my($status);

my($stdout_file) = "$LogDir/cmd${run_cmd_counter}.stdout";
my($stderr_file) = "$LogDir/cmd${run_cmd_counter}.stderr";

if ( ( -f "$stdout_file" ) or ( -f "$stderr_file" ) )
   {
   print_and_log "WARNING: Overwriting $LogDir/cmd${run_cmd_counter}.* files\n";
   unlink "$stdout_file";
   unlink "$stderr_file";
   }

#
# Run command and check exit status
# Redirect all output to a temporary file.
# We can't just use backticks here and capture the output
# because $cmd may invoke an editor which will require user
# input it can't get from the subshell.
#
$cmd =~ s/  / /g;
if ($#files > -1)
   {
   my($number_of_files_left) = $#files + 1;
   my($number_of_loops) = 0;
   while ( $number_of_files_left > 0 )
      {
      my($start_position, $end_position);
      if ($number_of_files_left >= $MAX_NUM_FILES)
         {
         $number_of_files_left -= $MAX_NUM_FILES;
         $start_position = $number_of_loops * $MAX_NUM_FILES;
         $end_position = $start_position + $MAX_NUM_FILES - 1;
         $number_of_loops += 1;
         }
      else
         {
         $number_of_files_left = 0;
         $start_position = $number_of_loops * $MAX_NUM_FILES;
         $end_position = $#files;
         }
      my(@one_group_of_files) = @files[${start_position}..${end_position}];

      #
      # Wrap each filename in quotes in case there are spaces
      #
      foreach (@one_group_of_files)
         {
         $_ = "\"$_\"";
         }

      my($cmd) = $cmd . join(" ", @one_group_of_files);

      print  LOGFILE "+Cmd${run_cmd_counter}: $cmd\n";
      $status = system("$cmd 2>>\"$stderr_file\" 1>>\"$stdout_file\" ") / 256;

      last if ($status);
      }
   }
else
   {
   print  LOGFILE "+Cmd${run_cmd_counter}: $cmd\n";
   $status = system("$cmd 2>>\"$stderr_file\" 1>>\"$stdout_file\" ") / 256;
   }

#
# Increment cmd counter
#
$run_cmd_counter++;

#
# Read the temp files back in to get the output in an array.
#
@$output_ref = "";
if ( open(CMD_STDERR, "$stderr_file") )
   {
   @$output_ref = <CMD_STDERR>;
   close CMD_STDERR;
   }
if ( open(CMD_STDOUT, "$stdout_file") )
   {
   push(@$output_ref, <CMD_STDOUT>);
   close CMD_STDOUT;
   }

if ($status && ! $quiet)
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): cvs returned exit status of '$status'.\n";
   print_and_log "Cmd: " . beautify_commit_cmd($cmd) . "\n";
   print LOGFILE "+Cmd: $cmd\n";
   print LOGFILE "+Stderr: \n";
   if ( open(CMD_STDERR, "$stderr_file") )
      {
      while ( <CMD_STDERR> )
         {
     print LOGFILE "   $_";
     print STDERR "   $_";
         }
      close CMD_STDERR;
      }
   print LOGFILE "+Stdout:\n";
   if ( open(CMD_STDOUT, "$stdout_file") )
      {
      while ( <CMD_STDOUT> )
         {
     print LOGFILE "   $_";
     print STDOUT "   $_";
         }
      close CMD_STDOUT;
      }
    print_and_log "\n";
   }
else
   {
   print LOGFILE "+Stderr:\n";
   if ( open(CMD_STDERR, "$stderr_file") )
      {
      while ( <CMD_STDERR> )
         {
     print LOGFILE "+   $_";
         }
      close CMD_STDERR;
      }
   print LOGFILE "+Stdout:\n";
   if ( open(CMD_STDOUT, "$stdout_file") )
      {
      while ( <CMD_STDOUT> )
         {
     print LOGFILE "+   $_";
         }
      close CMD_STDOUT;
      }
   print LOGFILE "\n";
   }

return ($status);
}



#------------------------
# sub run_cmd_wo_redirect($cmd, \@output[, $quiet])
#     Differs from run_cmd() in that it doesn't redirect stdout or
#     stderr.  This allows $cmd to contain its own redirection, but
#     at the potential cost of not capturing error text.
#      1) runs $cmd
#      2) overwrites @output with output from command
#      3) returns $status
#------------------------
#
# Note: It is not necessary to use the $MAX_NUM_FILES as run_cmd does
#       since this function is called to checkout ONE file, not a list
#       of files:
#
#         $cmd = "cvs $cvs_debug_arg $cvsroot_arg $no_action_arg -q -f" .
#                " checkout -p -r $postmerge_tag $file > $file";
#         ......
#         $status = run_cmd_wo_redirect($cmd, \@checkout_output);
#
sub run_cmd_wo_redirect
{
my($cmd, $output_ref, $quiet) = @_;
my($status);

#
# Run command and check exit status
#
$cmd =~ s/  / /g;
print LOGFILE "+Cmd: $cmd\n";
@$output_ref = `$cmd`;
$status = $? / 256;

if ($status && ! $quiet)
   {
   print_and_log "\n";
   print_and_log "ERROR ($progname): cvs returned exit status of '$status'.\n";
   print_and_log "Cmd: " . beautify_commit_cmd($cmd) . "\n";
   print LOGFILE "+Cmd: $cmd\n";
   print_and_log "Output:\n";
   for (@$output_ref) { print_and_log "   $_"; }
   print_and_log "\n";
   }
else
   {
   print LOGFILE "+Output:\n";
   for (@$output_ref) { print LOGFILE "+   $_"; }
   print LOGFILE "\n";
   }

return ($status);
}



#------------------------
# sub prune_cvs_tree(directory)
#
# Prune empty directories.  See nsqa-60117.  Basically if this
# filesystem is accessed through Samba, then cvs might not have been
# able to prune empty directories (like if you try to checkout a
# module on a branch that does not exist).  The working area would
# end up with a tree that only contains CVS admin files and empty
# directories.
#
# This should have no effect (other than extra time taken) on non-Samba
# filesystems, since CVS would have handled the pruning.
#
#------------------------
sub prune_cvs_tree
{
my($dir) = @_;

print LOGFILE "\n";
print LOGFILE "+Checking CVS tree $dir\n";

if ( -d "$dir" )
   {
   finddepth sub
      {
      if ( ! -l and -d _ and "$_" ne "CVS" )
         {
         #
         # This is a directory and we're processing from the bottom of
         # the tree so if this directory only contains the CVS admin
         # directory, prune it.
         #
         opendir(DIR, "$File::Find::name");
         my(@files) = grep { ! /^\.\.?$/ } readdir(DIR);
         closedir DIR;
         @files = grep { ! /^CVS$/ } @files;
         if (! @files)
            {
            #
            # NT won't let us remove the directory we're in, so back up.
            #
            if ( "$_" eq "\." )
               {
               chdir "..";
               }
            print LOGFILE "+Rmdir $File::Find::name\n";
            rmtree("$File::Find::name");
            }
         }
      }, $dir;
   }

print LOGFILE "\n";
}



#------------------------
# sub id
#
# Returns same output as 'id' shell command
#
#------------------------
sub id
{
my($rgid,@rgids,$egid,$nruid,$neuid,$nrgid,$negid);

($rgid,@rgids)=split(/\s+/,$();
$egid = (split(/\s+/,$)))[0];
$nruid = scalar getpwuid($<);
$neuid = scalar getpwuid($>);
$nrgid = scalar getgrgid($rgid);
$negid = scalar getgrgid($egid);

$tp=join("=","uid",($user)?$uid:$<);
$tp.=($nruid)?"($nruid) ":" ";

if ( !($user) && ($< != $>) )
   {
   $tp.="euid=$>";
   $tp.=($neuid)?"($neuid) ":" ";
   }

$tp.=join("=","gid",($user)?$gid:$rgid);
$tp.=($nrgid)?"($nrgid) ":" ";

if ( $rgid != $egid )
   {
   $tp.="egid=$egid";
   $tp.=($negid)?"($negid) ":" ";
   }

my(%done);
$tp.="groups=";
foreach ( @rgids )
   {
   my($i) = scalar getgrgid($_);
   my($i2) = "$_";
   $i2 .= "($i)" if ( $i );
   $done{$_} = "$i2";
   }

$tp.=join(",",values %done);

return "$tp\n";
}


#------------------------
# sub beautify_commit_cmd
#
# Cleans up a 'cvs commit' command line to make it more suitable
# for printing to the user
#
#------------------------
sub beautify_commit_cmd
{
my($cmd) = @_;

#
# Hide -s VAR=value from user
#
$cmd =~ s!\-s\s+\S+=.*\s+(commit\s+)!$1!;

return $cmd;
}


#------------------------
# sub simplify_relative_paths
#
# Removes '.' and '..' from relative path/filenames
# If the relative pathname goes above the current directory,
# an absolute pathname will be returned.  This shouldn't be
# the case for checkin since you cannot checkin files above you.
#------------------------
sub simplify_relative_paths
{
my(@objs) = @_;
my($obj, @new_objs);
my($current_dir) = &cwd();

foreach $obj (@objs)
   {
   #
   # Split the object into parts
   #
   my($dir) = dirname $obj;
   my($file) = basename $obj;

   #
   # Now simplify any relative references, creating an absolute path
   #
   $dir = abs_path($dir);

   #
   # Finally add back the filename and make it relative again
   # by stripping off the current directory.
   #
   $file = "$dir/$file";
   $file =~ s!^$current_dir/!!;

   push(@new_objs, $file);
   }

return @new_objs;
}

