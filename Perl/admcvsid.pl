#!/usr/bin/perl

#-------------------------------------------------------------------------------
#
# File:         tools/admcvsid.pl
#
# Description:  Provides a command line based tool to add, retire, and edit
#               user CVSid information.
#
# Input:        Target options will vary based upon the desired action of
#           adding, retiring, or editing a user. Information on what
#           input is required is available in the "usage" routine.
#
#
# Output:       Error messages
#       E-Mail to the following people:
#                   Birt::CVS::$CVS_ADMIN_EMAIL
#           User being added
#
# Libraries:    tools/lib, Birt::CVS, Birt::Win32, Birt::Array, File::Path
#
# Dependencies: No additional dependencies.
#
# Side Effects: None.
#
#-------------------------------------------------------------------------------

BEGIN {
   $ENV{'TOOLS_DIRECTORY'} = "/pdd/cvs" if ! defined $ENV{'TOOLS_DIRECTORY'};
}

use strict;

use lib "$ENV{'TOOLS_DIRECTORY'}/lib";

require "getopts.pl";

use Birt::CVS qw (
   $CVS_ADMIN_EMAIL
   get_cvsid_lists
   get_all_groups
   notify
   checkout_module
   checkin_module
   is_member_of_birt
   get_cvsidinfo
   edit_cvsidinfo
   edit_passwd
   edit_group
   remove_users_from_branch
   set_module_access
   cvsid_to_email
   get_file_access
   set_env_for_os
   );

use Birt::CGI   qw ( $BIRT_HOME_URL );
use Birt::Win32 qw ( is_cygwin );
use Birt::Array qw ( uniq is_element subtract_array );
use Birt::Stats qw( cli_usage_stats );
use Cwd;
use FileHandle;
use File::Path  qw ( rmtree );
use Getopt::Std qw ( getopts );
use POSIX "sys_wait_h";

#
# We must have a CVSROOT; it will be used for checkins.
#
if ( ! defined $ENV{'CVSROOT'} )
   {
   print "\n" .
         "ERROR: Environment variable \$CVSROOT is not defined.\n" .
         "       Maybe you forgot to do the setup for BIRT tools?\n";

   niceExit(1);
   }

#
# Deny access to non-BIRT users.
#
my($cvsid) = (split(/@/, (split(/:/, $ENV{'CVSROOT'}))[2]))[0];
if ( ! is_member_of_birt($cvsid) )
   {
   print "\n" .
         "ERROR: You, $cvsid, are not authorized to use this tool.\n" .
         "       Contact $CVS_ADMIN_EMAIL for all CVSid requests.\n";

   niceExit(1);
   }

#
# Variables local to "main".
#
my(@finds);
my(@users);
my($errors);
my($msg);
my($dir);
my($accessFile);
my(%results);
my($adminEmail) = &cvsid_to_email($cvsid) . ",$CVS_ADMIN_EMAIL";
my($cliString) = join(" ", $0, @ARGV);
my($hostname) = `hostname`;
chomp ($hostname);
# Usage stats variables.
my ($VERSION) = sprintf "%d.%d", q$Revision: 1.9 $ =~ /: (\d+)\.(\d+)/;
my (%stats_data); $stats_data{'tool_version'} = $VERSION;
$stats_data{'UsageID'} = &cli_usage_stats("", %stats_data);

#
# Global variables internal to this script.
#
my($MODULE) = "CVSROOT";
my($TEMPDIR) = cwd() . "/admcvsid_${cvsid}_" . time();
my($LOGFILE) = "${TEMPDIR}.txt";

my($EDITING_ERROR) = "\n" .
                     "Some errors have occurred; skipping checkin.\n" .
                     "You can either correct the problems and re-execute\n" .
                     "or go into the checkout on $hostname at\n" .
                     "\n" .
                     "   $TEMPDIR/$MODULE\n" .
                     "\n" .
                     "and finish the editing and checkins manually.\n" .
                     "Errors are specified in the following indented list:\n";

my($CHECKIN_ERROR) = "\n" .
                     "An error occurred while performing the checkin.\n" .
                     "You can either correct the problems and re-execute\n" .
                     "or go into the checkout on $hostname at\n" .
                     "\n" .
                     "   $TEMPDIR/$MODULE\n\n" .
                     "and finish the checkins manually.\n";

#
# Validate and acquire command line options.
#
my(%opts) = parseOpts();

#
# No changes; report the groups to which the given user belongs and exit.
#
if ( $opts{'action'} eq "groups" )
   {
   print "\n" .
         "User $opts{cvsid} belongs to the following groups:\n" .
         "\n" .
         join("\n", @{$opts{'groups'}}, "");

   niceExit(0);
   }

#
# Any file work should be done under this temporary tree.
#
if ( ! mkdir($TEMPDIR, 0777) or ! chmod (0777, $TEMPDIR) )
   {
   print "\n" .
         "ERROR: Could not create temporary directory\n" .
         "       $TEMPDIR\n";

   niceExit(1);
   }

#
# Split STDOUT and STDERR to both STDOUT and $LOGFILE; autoflush both.
# Save the originals; we must restore them later.
#
if ( ! open(STDOUT_SAVED, ">&STDOUT") or ! open(STDERR_SAVED, ">&STDERR") )
   {
   print "\n" .
         "ERROR: Could not open storage handles for STDOUT and STDERR.\n";

   niceExit(1);
   }

my($TEE_PID) = open(ADMCVSIDLOG, "| tee $LOGFILE");

if ( 0 != waitpid($TEE_PID, &WNOHANG) )
   {
   print "\n" .
         "ERROR: Could not set up split output for STDOUT and STDERR.\n" .
         "       using tee and the following log file:\n" .
         "\n" .
         "$LOGFILE\n" .
         "\n" .
         "       The error given was:\n" .
         "\n" .
         "$!\n";

   niceExit(1);
   }

*STDERR = *ADMCVSIDLOG;
*STDOUT = *ADMCVSIDLOG;
ADMCVSIDLOG->autoflush(1);
STDERR->autoflush(1);
STDOUT->autoflush(1);

#
# We already have some email information.
#
my(%adminNotify) = (
   to      => "$adminEmail",
   subject => "",
   message => ""
   );

my(%CVSidNotify) = (
   to      => "",
   subject => "",
   message => ""
   );

if ( defined $opts{'cvsidinfo'} and
     defined $opts{'cvsidinfo'}{$opts{'cvsid'}} and
     defined $opts{'cvsidinfo'}{$opts{'cvsid'}}{'email'} )
   {
   $CVSidNotify{'to'} = $opts{'cvsidinfo'}{$opts{'cvsid'}}{'email'};
   }
else
   {
   my(%info) = get_cvsidinfo($opts{'cvsid'});
   $CVSidNotify{'to'} = $info{$opts{'cvsid'}}{'email'};
   }

#
# Print general debug information if requested.
#
if ($opts{'debug'})
   {
   print "\n";
   print "DEBUG: $_ = $opts{$_}\n" foreach (keys %opts);
   }

#
# Get the checkout of CVSROOT.
#
print "\n" .
      "Command: $cliString\n" .
      "\n" .
      "Checking out $MODULE to $TEMPDIR... ";

if ( checkout_module("trunk", $MODULE, $TEMPDIR, $cvsid) )
   {
   print "checkout complete.\n" .
         "\n";
   }
else
   {
   print "FAILED.\n" .
         "\n" .
         "ERROR: Could not checkout module $MODULE to\n" .
         "\n" .
         "       $TEMPDIR\n";

   niceExit(1);
   }

################################################################################
#
# CREATE: BEGIN
#
################################################################################
if ( $opts{'action'} eq "create" )
   {
   #############################################################################
   #
   # CREATE: Add to passwd
   #
   #############################################################################
   $accessFile = "$TEMPDIR/$MODULE/passwd";
   print "ADDING $opts{cvsid} to $accessFile... ";
   undef %results;
   %results = edit_passwd("$accessFile",
                          $cvsid,
                          "",
                          %{$opts{'passwd'}},
                          ! $opts{'debug'});

   if ( defined $results{'add'} )
      {
      print "SUCCESS\n";
      }
   else
      {
      print "FAILURE\n";
      $errors = 1;
      }

   #############################################################################
   #
   # CREATE: Add to cvsidinfo
   #
   #############################################################################
   $accessFile = "$TEMPDIR/$MODULE/cvsidinfo";
   print "ADDING $opts{cvsid} to $accessFile... ";
   undef %results;
   %results = edit_cvsidinfo("$accessFile",
                             $cvsid,
                             "",
                             %{$opts{'cvsidinfo'}},
                             ! $opts{'debug'});

   if ( defined $results{'add'} )
      {
      print "SUCCESS\n";
      }
   else
      {
      print "FAILURE\n";
      $errors = 1;
      }

   #############################################################################
   #
   # CREATE: Add group inclusions if any were indicated
   #
   #############################################################################
   if ( defined $opts{'groups'} )
      {
      $accessFile = "$TEMPDIR/$MODULE/group";
      print "ADDING $opts{cvsid} to $accessFile... ";
      undef %results;
      %results = edit_group("$accessFile",
                            $cvsid,
                            "",
                            %{$opts{'groups'}},
                            ! $opts{'debug'});

      if ( defined $results{'add'} )
         {
         print "SUCCESS\n";
         }
      else
         {
         print "FAILURE\n";
         $errors = 1;
         }
      }

   #############################################################################
   #
   # CREATE: If we had any errors, add these to the report and do NOT checkin.
   #
   #############################################################################
   my($todo) = "*** !!!NEW!!! Please run the following command on FORTKNOX to add \n" .
               "    the newly created cvsid to the viewcvs password file,\n" .
               "    otherwise user will NOT be able to use the online repository. \n" .
               "    /usr/local/apache2/bin/htpasswd -b /usr/local/apache2/passwd/viewcvsUsers $opts{cvsid} $opts{cvsid} \n" .
               "\n" .
               "*** If the user requires special tagging priveleges,\n" .
               "    you ($cvsid) must update tools/lib/Birt/TagInfo.pm\n" .
               "\n" .
               "*** If the user will be administering checkin access,\n" .
               "    you ($cvsid) must update tools/lib/Birt/FocusInfo.pm\n";

   my($help) = "You should request checkin privileges from Program Management\n" .
               "for your project.  Please provide your new CVSid and the\n" .
               "branches you need access to.\n" .
               "\n" .
               "For information on getting started with the BIRT CVS \n" .
               "archive and tools, please refer to the information\n" .
               "found on the BIRT website at $BIRT_HOME_URL .\n";

   if ( $errors )
      {
      print "$EDITING_ERROR" .
            "\n" .
            "After checkins are complete:\n" .
            "\n" .
            "$todo";

      $adminNotify{'subject'} = "ERROR creating $opts{cvsid}";
      niceExit(1, (\%adminNotify));
      }
   else
      {
      $msg = "\n" .
             "CVSid $opts{cvsid} has been created as follows:\n" .
             "\n";

      foreach ( keys %{$opts{'cvsidinfo'}{$opts{'cvsid'}}} )
         {
         $msg .= sprintf("%21.21s ", "$_:");

         if ( $opts{'cvsidinfo'}{$opts{'cvsid'}}{"$_"} =~ /^\s*$/ )
            {
            $msg .= "?\n";
            }
         else
            {
            $msg .= sprintf("%s\n", $opts{'cvsidinfo'}{$opts{'cvsid'}}{"$_"});
            }
         }

      if ( defined $opts{'groups'} )
         {
         $msg .= sprintf("%21.21s ", "added to groups:");
         $msg .= sprintf("%s\n", join(", ", keys %{$opts{'groups'}{'add'}}));
         }

      if ( checkin_module($MODULE, $TEMPDIR, $cvsid, "$msg") )
         {
         print "$msg" . "\n" . "$todo";
         $adminNotify{'subject'} = "CVSid $opts{cvsid} has been created, one more manual step to complete";
         $adminNotify{'message'} = "$msg" . "\n" . "$todo";
         $CVSidNotify{'subject'} = "Your CVSid ($opts{cvsid}) has been created";
         $CVSidNotify{'message'} = "$msg" . "\n" . "$help";
         niceExit(0, (\%adminNotify, \%CVSidNotify));
         }
      else
         {
         print "$CHECKIN_ERROR" .
               "\n" .
               "After checkins are complete:\n" .
               "\n" .
               "$todo";

         $adminNotify{'subject'} = "ERROR creating $opts{cvsid}";
         niceExit(1, (\%adminNotify));
         }
      }
   }
################################################################################
#
# MODIFY: BEGIN
#
################################################################################
elsif ( $opts{'action'} eq "modify" )
   {
   #############################################################################
   #
   # MODIFY: Change cvsidinfo if any changes were indicated
   #
   #############################################################################
   if ( exists $opts{'cvsidinfo'} )
      {
      $accessFile = "$TEMPDIR/$MODULE/cvsidinfo";
      print "MODIFYING $opts{cvsid} in $accessFile... ";
      undef %results;
      %results = edit_cvsidinfo("$accessFile",
                                $cvsid,
                                "",
                                %{$opts{'cvsidinfo'}},
                                ! $opts{'debug'});

      if ( defined $results{'modify'} )
         {
         print "SUCCESS\n";
         }
      else
         {
         print "FAILURE\n";
         $errors = 1;
         }
      }

   #############################################################################
   #
   # MODIFY: Change group inclusions if any were indicated
   #
   #############################################################################
   if ( defined $opts{'groups'} )
      {
      $accessFile = "$TEMPDIR/$MODULE/group";
      print "MODIFYING $opts{cvsid} in $accessFile... ";
      undef %results;
      %results = edit_group("$accessFile",
                            $cvsid,
                            "",
                            %{$opts{'groups'}},
                            ! $opts{'debug'});

      if ( %results )
         {
         print "SUCCESS\n";
         }
      else
         {
         print "FAILURE\n";
         $errors = 1;
         }
      }

   #############################################################################
   #
   # MODIFY: If we had any errors, add these to the report and do NOT checkin.
   #
   #############################################################################
   if ( $errors )
      {
      print "$EDITING_ERROR";
      $adminNotify{'subject'} = "ERROR updating $opts{cvsid}";
      niceExit(1, (\%adminNotify));
      }
   else
      {
      $msg = "\n" .
             "CVSid $opts{cvsid} has been updated as follows:\n" .
             "\n";

      foreach ( keys %{$opts{'cvsidinfo'}{$opts{'cvsid'}}} )
         {
         $msg .= sprintf("%21.21s ", "$_:");

         if ( $opts{'cvsidinfo'}{$opts{'cvsid'}}{"$_"} =~ /^\s*$/ )
            {
            $msg .= "?\n";
            }
         else
            {
            $msg .= sprintf("%s\n", $opts{'cvsidinfo'}{$opts{'cvsid'}}{"$_"});
            }
         }

      if ( defined $opts{'groups'} and
           defined $opts{'groups'}{'remove'} )
         {
         $msg = "$msg" .
                sprintf("%21.21s ", "removed from groups:") .
                join(", ", keys %{$opts{'groups'}{'remove'}}) .
                "\n";
         }

      if ( defined $opts{'groups'} and
           defined $opts{'groups'}{'add'} )
         {
         $msg = "$msg" .
                sprintf("%21.21s ", "added to groups:") .
                join(", ", keys %{$opts{'groups'}{'add'}}) .
                "\n";
         }

      if ( checkin_module($MODULE, $TEMPDIR, $cvsid, "$msg") )
         {
         print "$msg";
         $adminNotify{'subject'} = "CVSid $opts{cvsid} has been updated";
         $CVSidNotify{'subject'} = "Your CVSid has been updated";
         $CVSidNotify{'message'} = "$msg";
         niceExit(0, (\%adminNotify, \%CVSidNotify));
         }
      else
         {
         print "$CHECKIN_ERROR";
         $adminNotify{'subject'} = "ERROR updating $opts{cvsid}";
         niceExit(1, (\%adminNotify));
         }
      }
   }
################################################################################
#
# RETIRE: BEGIN
#
################################################################################
elsif ( $opts{'action'} eq "retire" )
   {
   #############################################################################
   #
   # RETIRE: Edit passwd
   #
   #############################################################################
   $accessFile = "$TEMPDIR/$MODULE/passwd";
   print "REMOVING $opts{cvsid} from $accessFile... ";
   undef %results;
   %results = edit_passwd("$accessFile",
                          $cvsid,
                          "",
                          %{$opts{'passwd'}},
                          ! $opts{'debug'});

   if ( defined $results{'remove'} )
      {
      print "SUCCESS\n";
      }
   else
      {
      print "FAILURE\n";
      $errors = 1;
      }

   #############################################################################
   #
   # RETIRE: Edit cvsidinfo
   #
   #############################################################################
   $accessFile = "$TEMPDIR/$MODULE/cvsidinfo";
   print "REMOVING $opts{cvsid} from $accessFile... ";
   undef %results;
   %results = edit_cvsidinfo("$accessFile",
                             $cvsid,
                             "",
                             %{$opts{'cvsidinfo'}},
                             ! $opts{'debug'});

   if ( defined $results{'remove'} )
      {
      print "SUCCESS\n";
      }
   else
      {
      print "FAILURE\n";
      $errors = 1;
      }

   #############################################################################
   #
   # RETIRE: Remove CVSid from all group access
   #
   #############################################################################
   $accessFile = "$TEMPDIR/$MODULE/group";
   print "REMOVING $opts{cvsid} from $accessFile... ";
   undef %results;
   %results = edit_group("$accessFile",
                         $cvsid,
                         "",
                         %{$opts{'groups'}},
                         ! $opts{'debug'});

   if ( defined $results{'remove'} )
      {
      print "SUCCESS\n";
      }
   else
      {
      print "FAILURE\n";
      $errors = 1;
      }

   #############################################################################
   #
   # RETIRE: Remove CVSid from all file_access (module expressions)
   #
   #############################################################################
   $accessFile = "$TEMPDIR/$MODULE/file_access";
   undef %results;
   my(%allLists) = get_file_access("", $accessFile);
   %results = get_file_access($opts{'cvsid'}, $accessFile);

   if ( %results )
      {
      foreach ( keys %results )
         {
         #
         # Don't change module access matches that have no CVSids listed.
         # While technically these are open to all, a fully retired CVSid
         # cannot checkout or checkin anyway -- we just want to remove
         # printed occurrences of the retiring CVSid.  Otherwise, we would
         # have to list every active user for every "open" module.  That
         # might be a possibility if we don't have to manually modify this
         # file in the future, but for now, let's keep it somewhat readable.
         #
         my(@users) =  @{$allLists{"$_"}};

         if ( defined $results{"$_"} and @users )
            {
            print "\n" .
                  "REMOVING $opts{cvsid} from $accessFile...\n";

            @users = subtract_array(\@users, [($opts{'cvsid'})]);
            if ( set_module_access("$_", "$accessFile", $cvsid, "", @users) )
               {
               print "   SUCCESS removing $opts{cvsid} from $_\n";
               }
            else
               {
               print "   FAILURE removing $opts{cvsid} from $_\n";
               $errors = 1;
               }
            }
         }
      }

   #############################################################################
   #
   # RETIRE: Remove CVSid from */project_access (focus-branches)
   #
   #############################################################################
   $dir = "$TEMPDIR/$MODULE";

   my($command) = "find $dir -name project_access -print | " .
                  "xargs grep $opts{cvsid}";

   @finds = `$command`;
   chomp(@finds);
   my($previousFile) = "";

   foreach ( @finds )
      {
      if ( m!^($dir/(.*)/.*):([A-Za-z0-9_-]*):! )
         {
         $accessFile = "$1";
         my($focus) = "$2";
         my($branch) = "$3";

         if ( $accessFile !~ m/^$previousFile$/ )
            {
            print "\n" .
                  "REMOVING $opts{cvsid} from $accessFile...\n";
            }

         $previousFile = "$accessFile";
         my($status) = remove_users_from_branch($branch,
                                                $accessFile,
                                                $cvsid,
                                                "",
                                                ($opts{'cvsid'}));
         if ( $status )
            {
            print "   SUCCESS removing $opts{cvsid} from $focus:$branch\n";
            }
         else
            {
            print "   FAILURE removing $opts{cvsid} from $focus:$branch\n";
            $errors = 1;
            }
         }
      }

   #############################################################################
   #
   # RETIRE: Remove CVSid from */commit_notify_list (focus-branch-module-regexp)
   #
   #############################################################################
   $dir = "$TEMPDIR/$MODULE";

   my($command) = "find $dir -name commit_notify_list -print | " .
                  "xargs grep $opts{cvsid}";

   @finds = `$command`;
   chomp(@finds);
   my($previousFile) = "";

   foreach ( @finds )
      {
      my($accessList, $focus, $branch, $regexp);

      if ( m!^($dir/(.*)/(.*)/.*):\s*((\S+\s+)*(\S+)*)\s*$! )
         {
         $accessFile = "$1";
         $focus = "$2";
         $branch = "$3";
         $accessList = "$4";
         $accessList =~ s/\s+/ /g;
         $accessList =~ s/^\s+//g;
         $accessList =~ s/\s+$/ /g;

         if ( $accessList =~ m!^(\S+) (.*)$! )
            {
            $regexp = "$1";
            $accessList = "$2";
            my(@userlist) = split(/ /, $accessList);

            if ( is_element($opts{cvsid}, @userlist) )
               {
               if ( $accessFile !~ m/^$previousFile$/ )
                  {
                  print "\n" .
                        "REMOVING $opts{cvsid} from $accessFile...\n";
                  }

               @userlist = subtract_array(\@userlist, [($opts{cvsid})]);
               $previousFile = "$accessFile";
               my($status) = set_module_access($regexp,
                                               $accessFile,
                                               $cvsid,
                                               "",
                                               @userlist);
               if ( $status )
                  {
                  print "   SUCCESS removing $opts{cvsid} from " .
                        "$focus:$branch:$regexp\n";
                  }
               else
                  {
                  print "   FAILURE removing $opts{cvsid} from " .
                        "$focus:$branch:$regexp\n";
                  $errors = 1;
                  }
               }
            }
         }
      }

   #############################################################################
   #
   # RETIRE: Check tools/lib/Birt modules, which must be updated manually
   #
   #############################################################################
   my($tools) = "tools/lib/Birt";
   my($cvsroot) = $ENV{'CVSROOT'};
   my($checkout) = "cvs -q -d \"$cvsroot\" checkout -p";
   my(%errors);
   my(%pmFinds);
   my($subject);
   my($todo);
   my(@pmFiles) = ("$tools/FocusInfo.pm", "$tools/FoyerInfo.pm", "$tools/TagInfo.pm");

   set_env_for_os();

   foreach ( @pmFiles )
      {
      if ( is_cygwin() )
         {
         $pmFinds{"$_"} = `$checkout $_ | grep $opts{cvsid} 2>&1`;
         }
      else
         {
         $pmFinds{"$_"} = `sh -c '$checkout $_ | grep $opts{cvsid} 2>&1'`;
         }

      if ( $? )
         {
         if ( $pmFinds{"$_"} =~ /^\s*$/ )
            {
            delete $pmFinds{"$_"};
            delete $errors{"$_"};
            }
         else
            {
            $errors{"$_"} = $pmFinds{"$_"};
            delete $pmFinds{"$_"};
            }
         }
      }

   #############################################################################
   #
   # RETIRE: If we had any errors, add these to the report and do NOT checkin.
   #
   #############################################################################
   if ( %pmFinds )
      {
      $subject = "MANUAL WORK NEEDED retiring $opts{cvsid}";
      $todo = "\n" .
              "Matches were found for $opts{cvsid} in the following\n" .
              "files which you ($cvsid) need to remove manually\n" .
              "(unless they are simply grep coincidences):\n" .
              "\n" .
              sprintf("   %s\n", join("\n   ", keys %pmFinds));
      }
   else
      {
      $subject  = "SUCCESS retiring $opts{cvsid}, one more manual step to complete";
      $todo = "\n" .
              "No matches were found for $opts{cvsid} in any\n" .
              "of the following tools:\n" .
              "\n" .
              join("\n", @pmFiles, "");
      }

   if ( %errors )
      {
      print "$EDITING_ERROR" .
            sprintf("\n   %s\n", join("\n   ", keys %errors)) .
            "\n" .
            "After checkins are complete:\n" .
            "\n" .
            "$todo\n";

      $adminNotify{'subject'} = "ERROR retiring $opts{cvsid}";
      niceExit(1, (\%adminNotify));
      }
   else
      {
      $msg = "Retiring $opts{cvsid}";
      if ( checkin_module($MODULE, $TEMPDIR, $cvsid, "$msg") )
         {
         $todo = "\n *** !!!NEW!!! Please manually edit the viewcvs password file on FORTKNOX \n" .
               "    to remove cvs user $opts{cvsid}. \n" .
               "    The password file is located in \n" .
               "    /usr/local/apache2/passwd/viewcvsUsers" .
               "\n" . $todo . "\n";
         print "$todo\n";
         $adminNotify{'subject'} = "$subject";
         niceExit(0, (\%adminNotify));
         }
      else
         {
         print "$CHECKIN_ERROR" .
               "\n" .
               "After checkins are complete:\n" .
               "\n" .
               "$todo\n";

         $adminNotify{'subject'} = "ERROR retiring $opts{cvsid}";
         niceExit(1, (\%adminNotify));
         }
      }
   }
else
   {
   print "\n" .
         "ERROR: You are asking me to do something that I\n" .
         "       know nothing about.  Inspect my code; the\n" .
         "       action requested was $opts{action}.\n" .
         "\n";

   niceExit(1);
   }

print "\n" .
      "ERROR: I don't think I should have gotten to this\n" .
      "       point in the script.  Inspect my code.\n" .
      "\n";

niceExit(1);


#-------------------------------------------------------------------------------
#  Procedure   : parseOpts
#
#  Description : Validate command line options, give usage information
#                and exit if there are any problems.
#
#  Input       : None
#
#  Output      : Exits with success (0) and prints usage if requested,
#                with failure (1) if a usage error is encountered.
#                Does not exit or print if parsing is successful.
#
#  Globals     : None
#
#  Returns     : %opt hash of parsed and processed inputs.
#-------------------------------------------------------------------------------
sub parseOpts {

my($usage) = "

 USAGE:

 --------------------------------------------------
 Adding a new user:
 --------------------------------------------------
 admcvsid -a -u CVSid
          -n Lastname,Firstname
          -e email_address
          -s site_location
          [-p phone_number]
          [-o office_location]
          [-g group1[,group2,...]]
          [-g+group1[,group2,...]]

 --------------------------------------------------
 Changing information for an existing user:
 --------------------------------------------------
 admcvsid -c -u CVSid
          [-n Lastname,Firstname]
          [-e email_address]
          [-s site_location]
          [-p phone_number]
          [-o office_location]
          [-g group1[,group2,...]]
          [-g+group1[,group2,...]]
          [-g-group1[,group2,...]]

 --------------------------------------------------
 Retiring a user:
 --------------------------------------------------
 admcvsid -r -u CVSid

 --------------------------------------------------
 Examples:
 --------------------------------------------------

 1. View this usage message again:
 admcvsid -H

 2. Add new user Jane Doe as jdoe (puts her in the UNASSIGNED group):
 admcvsid -a -u jdoe -n Doe,Jane -e Doe_Jane\@emc.com -s RTP -p 919.248.1234

 3. Change jdoe's site and add an office location:
 admcvsid -c -u jdoe -s SOBO -o'SOBO 5-21'

 4. Put jdoe in groups QES and DART (also removes her from any other group):
 admcvsid -c -u jdoe -g QES,DART

 5. Remove jdoe from the QES group only:
 admcvsid -c -u jdoe -g-QES

 6. Remove jdoe from all groups:
 admcvsid -c -u jdoe -g UNASSIGNED

 7. Add jdoe back to the QES group (she remains in any other group she is in):
 admcvsid -c -u jdoe -g+QES

 8. Find out what groups jdoe belongs to:
 admcvsid -g? -u jdoe

 9. Retire jdoe's CVSid:
 admcvsid -r -u jdoe

";

#
# Get the options and validate syntax.
#
my(%opt);

if ( ! getopts("DacrHhu:s:p:o:n:g:e:", \%opt) )
   {
   print "$usage";
   niceExit(1);
   }

if ( $opt{H} or $opt{h} )
   {
   print "$usage";
   niceExit(0);
   }

my($optionCount) = scalar (keys %opt);
$opt{n} =~ s/\s+//g;
$opt{e} =~ s/\s+//g;

#
# Debug information anyone?
#
if ( $opt{D} )
   {
   $opt{'debug'} = 1;
   }
else
   {
   $opt{'debug'} = 0;
   }

#
# All actions require a valid CVSid.
#
if ( $opt{u} )
   {
   #
   # 1. CVSids must be valid and active in order to be modified
   # 2. New CVSids must uniquely differ from any existing ids
   # 3. New CVSids must contain only alphanumerics and underscores
   #    with a minimum size of three characters
   #
   if ( $opt{a} and $opt{u} !~ /[A-Za-z0-9_]{3,}?/ )
      {
      print "\n" .
            "ERROR: $opt{u} does not follow CVSid syntax:\n" .
            "\n" .
            "       1. Alpha-numerics and underscores only\n" .
            "       2. Must be at least three characters\n" .
            "\n";

      niceExit(1);
      }

   my(%cvsids) = get_cvsid_lists();
   delete $cvsids{all};

   foreach (keys %cvsids)
      {
      if ( is_element($opt{u}, @{$cvsids{"$_"}}) )
         {
         if ( $opt{a} )
            {
            print "\n" .
                  "ERROR: CVSid $opt{u} already exists with status $_.\n" .
                  "\n";

            niceExit(1);
            }
         else
            {
            if ( "$_" ne "active" )
               {
               print "\n" .
                     "ERROR: CVSid $opt{u} is not active; status is $_.\n" .
                     "\n";

               niceExit(1);
               }
            else
               {
               $opt{'cvsid'} = $opt{u};
               last;
               }
            }
         }
      }

   if ( ! $opt{a} and ! $opt{'cvsid'} )
      {
      print "\n" .
            "ERROR: CVSid $opt{u} does not exist.\n" .
            "\n";

      niceExit(1);
      }
   else
      {
      $opt{'cvsid'} = $opt{u};
      }
   }
else
   {
   print "\n" .
         " USAGE ERROR: You must specifiy a CVSid." .
         "$usage";

   niceExit(1);
   }

#
# You've got three choices; retire, change, or create.
#
if ( $opt{r} )
   {
   if ( 2 < $optionCount )
      {
      print "\n" .
            " USAGE ERROR: -r is used with -u and nothing else" .
            $usage;

      niceExit(1);
      }
   else
      {
      $opt{'passwd'}{'remove'} = [($opt{'cvsid'})];
      $opt{'cvsidinfo'}{$opt{'cvsid'}}{'site'} = "";
      $opt{'groups'}{'remove'}{'ALL'} = [($opt{'cvsid'})];
      $opt{'action'} = "retire";
      return (%opt);
      }
   }
elsif ( $opt{c} )
   {
   if ( $opt{a} )
      {
      print "\n" .
            " USAGE ERROR: You must specify only one action per command:\n" .
            "$usage";

      niceExit(1);
      }

   if ( 3 > $optionCount )
      {
      print "\n" .
            " USAGE ERROR: You are modifying CVSid information\n" .
            "              but you have not specified any changes." .
            "$usage";

      niceExit(1);
      }

   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'name'} = "$opt{n}" if ( $opt{n} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'email'} = "$opt{e}" if ( $opt{e} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'site'} = "$opt{s}" if ( $opt{s} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'phone'} = "$opt{p}" if ( $opt{p} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'office'} = "$opt{o}" if ( $opt{o} );
   $opt{'action'} = "modify";
   }
elsif ( $opt{a} )
   {
   if ( ! ($opt{n} and $opt{e} and $opt{s}) )
      {
      print "\n" .
            " USAGE ERROR: New CVSids require the following:\n" .
            "\n" .
            "              -n Lastname,Firstname\n" .
            "              -e email_address\n" .
            "              -s site_location" .
            "$usage";

      niceExit(1);
      }

   $opt{'passwd'}{'add'} = [($opt{'cvsid'})];
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'name'} = "$opt{n}" if ( $opt{n} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'email'} = "$opt{e}" if ( $opt{e} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'site'} = "$opt{s}" if ( $opt{s} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'phone'} = "$opt{p}" if ( $opt{p} );
   $opt{'cvsidinfo'}{$opt{'cvsid'}}{'office'} = "$opt{o}" if ( $opt{o} );
   $opt{'action'} = "create";
   }
else
   {
   # We have one more possibile action (-g?) to validate seperately
   }

#
# 1. -g-  = remove CVSid from given groups
# 2. -g+  = add CVSid to given groups
# 3. -g?  = list group inclusion of given CVSid and exit
# 4  -g   = reset CVSid to the given groups, remove from all others
# 5. UNASSIGNED cannot be specified with anything else
# 6. creating new users with no groups specified defaults to UNASSIGNED
#
if ( $opt{g} )
   {
   #############################################################################
   #
   # GROUPS: VALIDATE group inputs, acquire non-input based group information
   #
   #############################################################################
   my(%allGroups) = get_all_groups();
   delete $allGroups{'ALL'};
   my($groupOp) = $opt{g};
   $groupOp =~ s/\s+//g;
   $groupOp =~ s/,,/,/g;
   $groupOp =~ s/^,//;
   $groupOp =~ s/,$//;
   my(@inputGroups);

   if ( $groupOp =~ m/^([\?+-])?([A-Za-z0-9_\-,]*)$/ )
      {
      $groupOp = "$1";
      @inputGroups = split(/,/, "$2");
      }
   else
      {
      print "\n" .
            " USAGE ERROR: Unrecognized operation for -g." .
            "$usage";

      niceExit(1);
      }

   my(@errGroups) = subtract_array(\@inputGroups, [(keys %allGroups)]);

   if ( @errGroups )
      {
      print "\n" .
            "ERROR: Some of the groups specified do not exist:\n" .
            "\n" .
            "       " . join("\n       ", @errGroups) . "\n";

      niceExit(1);
      }
   else
      {
      if ( scalar(@inputGroups) > 1 and is_element('UNASSIGNED', @inputGroups) )
         {
         print "\n" .
               "ERROR: An UNASSIGNED CVSid cannot exist in other groups.\n";

         niceExit(1);
         }
      }

   my(@currentGroups);

   if ( ! $opt{a} )
      {
      foreach ( sort keys %allGroups )
         {
         if ( is_element($opt{'cvsid'}, @{$allGroups{"$_"}}) )
            {
            push(@currentGroups, "$_");
            }
         }
      }

   #############################################################################
   #
   # GROUPS: REMOVE CVSid from groups
   #
   #############################################################################
   if ( $groupOp =~ /^-$/ )
      {
      if ( $opt{a} )
         {
         print "\n" .
               " USAGE ERROR: Huh? Using -g- with a new CVSid request?" .
               "$usage";

         niceExit(1);
         }

      if ( ! @inputGroups )
         {
         print "\n" .
               " USAGE ERROR: Option -g- was specified without any groups." .
               "$usage";

         niceExit(1);
         }

      foreach ( @inputGroups )
         {
         $opt{'groups'}{'remove'}{"$_"} = [($opt{'cvsid'})];
         }

      my(@leftovers) = subtract_array(\@currentGroups, \@inputGroups);

      if ( ! @leftovers )
         {
         $opt{'groups'}{'add'}{'UNASSIGNED'} = [($opt{'cvsid'})];
         }
      }
   #############################################################################
   #
   # GROUPS: ADD CVSid to groups
   #
   #############################################################################
   elsif ( $groupOp =~ /^\+$/ )
      {
      if ( ! @inputGroups )
         {
         print "\n" .
               " USAGE ERROR: Option -g+ was specified without any groups." .
               "$usage";

         niceExit(1);
         }

      foreach ( @inputGroups )
         {
         $opt{'groups'}{'add'}{"$_"} = [($opt{'cvsid'})];
         }
      }
   #############################################################################
   #
   # GROUPS: REPORT groups to which CVSid belongs
   #
   #############################################################################
   elsif ( $groupOp =~ /^\?$/ )
      {
      if ( @inputGroups )
         {
         print "\n" .
               " USAGE ERROR: Option -g? does not take group names for input." .
               "$usage";

         niceExit(1);
         }

      if ( 2 < $optionCount )
         {
         print "\n" .
               " USAGE ERROR: -g? is used with -u and nothing else" .
               "$usage";

         niceExit(1);
         }

      $opt{'action'} = "groups";
      $opt{'groups'} = \@currentGroups;
      }
   #############################################################################
   #
   # GROUPS: RESET CVSid groups (add to specified, remove from all others)
   #
   #############################################################################
   else
      {
      if ( ! @inputGroups )
         {
         print "\n" .
               " USAGE ERROR: A group change was requested with -g,\n" .
               "              however no groups have been specified." .
               "$usage";

         niceExit(1);
         }

      foreach ( &subtract_array(\@inputGroups, \@currentGroups) )
         {
         $opt{'groups'}{'add'}{"$_"} = [($opt{'cvsid'})];
         }

      foreach ( &subtract_array(\@currentGroups, \@inputGroups) )
         {
         $opt{'groups'}{'remove'}{"$_"} = [($opt{'cvsid'})];
         }
      }
   }
else
   {
   if ( $opt{a} )
      {
      $opt{'groups'}{'add'}{'UNASSIGNED'} = [($opt{'cvsid'})];
      }
   }

if ( ! $opt{'action'} )
   {
   print "\n" .
         " USAGE ERROR: You must specify an action (e.g. -c):\n" .
         "$usage";

   niceExit(1);
   }

return (%opt);
}


#-------------------------------------------------------------------------------
#  Procedure   : niceExit ($error, @emails)
#
#  Description : Exit politely; clean up where possible and desirable.
#
#  Input       : $error         zero: exit success
#                           non-zero: exit failure
#
#                @emails    array of email notifications to make; each
#                           array element is a hash keyed as follows:
#
#                           subject = subject line
#                           to      = comma seperated "to" addresses
#                           message = string message (if empty, the
#                                     info in $LOGFILE is used)
#
#                The remainder of @_ is printed to STDOUT
#
#  Output      : Printed messages, email notifications
#
#  Globals     : $TEMPDIR, $LOGFILE, $TEE_PID, ADMCVSID, STDOUT, STDERR
#
#  Returns     : Exits with the specified error
#-------------------------------------------------------------------------------
sub niceExit($, @) {

my($error, @emails) = @_;
my($hostname) = `hostname`;
chomp($hostname);
my(@loginfo);
my($warning) = "\n" .
               "Due to the following error, you will need to manually\n" .
               "remove the directories and/or files listed below.\n";

my($path) = "$TEMPDIR";
$path =~ s/^\s+//;
$path =~ s/\s+$//;
$path =~ s!\\!/!g;

if ( ! $error and -d "$path" )
   {
   if ( $path =~ m!^[A-Za-z]+:/*$! or  # Windows drive letter roots
        $path =~ m!^/+$! or            # Unix root filesystem
        $path =~ m!^//.*$! or          # Windows UNC paths
        $path =~ m!^\.+/*! or          # Relative path with leading '.'
        $path =~ m!\.+/*$! or          # Relative path with ending '.'
        $path =~ m!/+\.+/+! )          # Relative path with internal '.'
      {
      print "$warning" .
            "\n" .
            "ERROR: Removing trees rooted at\n" .
            "\n" .
            "       $TEMPDIR\n" .
            "\n" .
            "is dissallowed.  Positional references using '.' are not\n" .
            "allowed, as well as any common filesystem root paths and\n" .
            "Windows UNC paths.  This error occurred on $hostname.\n";
      }
   else
      {
      if ( ! chdir("$path/../") )
         {
         print "$warning" .
               "\n" .
               "ERROR: Could not change to a directory\n" .
               "       outside of the temporary directory\n" .
               "\n" .
               "       $TEMPDIR\n" .
               "\n" .
               "       on host $hostname.\n";
         }
      else
         {
         if ( ! rmtree("$path") or -d "$path" )
            {
            print "$warning" .
                  "\n" .
                  "ERROR: Could not remove all or some of\n" .
                  "       the temporary directory rooted at\n" .
                  "\n" .
                  "       $TEMPDIR\n" .
                  "\n" .
                  "       on host $hostname.\n";
            }
         else
            {
            print "\n" .
                  "$TEMPDIR was removed successfully.\n";
            }
         }
      }
   }

if ( defined $TEE_PID and -f "$LOGFILE" )
   {
   close ADMCVSIDLOG;
   close STDOUT;
   close STDERR;
   open(STDERR, ">&STDERR_SAVED");
   open(STDOUT, ">&STDOUT_SAVED");
   close STDOUT_SAVED;
   close STDERR_SAVED;
   STDERR->autoflush(1);
   STDOUT->autoflush(1);
   open(ADMCVSIDLOGINFO, "<$LOGFILE");
   @loginfo = <ADMCVSIDLOGINFO>;
   close(ADMCVSIDLOGINFO);
   my($final_message);

   if ( ! $error )
      {
      if ( ! unlink("$LOGFILE") or -f "$LOGFILE" )
         {
         $final_message = "$warning" .
                          "\n" .
                          "ERROR: Could not remove the temporary log file\n" .
                          "\n" .
                          "       $LOGFILE\n" .
                          "\n" .
                          "       on host $hostname.\n";
         }
      else
         {
         $final_message = "\n" .
                          "$LOGFILE was removed successfully.\n";
         }

      print "$final_message";
      push(@loginfo, $final_message);
      }
   }

foreach ( @emails )
   {
   my(%email) = %{$_};

   if ( $email{'message'} )
      {
      notify($email{'to'}, $email{'subject'}, $email{'message'});
      }
   else
      {
      if ( ! @loginfo )
         {
         notify($email{'to'},
                $email{'subject'},
                "ERROR (admcvsid): No message was specified and no\n" .
                "                  log information could be acquired.\n" .
                "                  The temporary directory is/was on\n" .
                "                  $hostname at:\n" .
                "\n" .
                "                  $TEMPDIR\n" .
                "\n" .
                "                  The temporary log file is/was at:\n" .
                "\n" .
                "                  $LOGFILE\n");
         }
      else
         {
         notify($email{'to'}, $email{'subject'}, join("", @loginfo));
         }
      }
   }

print "\n";
&cli_usage_stats($error, %stats_data);
exit $error;
}


