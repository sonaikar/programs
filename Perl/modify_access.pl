#!/usr/bin/perl

#--------------------------------------------------------------------------------
#
# File:         tools/sbin/modify_access.pl
#
# Description:  This Perl script provides a command line interface for the
#               manipulation of BIRT CVS repository branch level access by
#               authorized persons, including performing the authorization check.
#
# Input:        modify_access [-H] [-r reason] {-o|-c|-a|-d} {-b branch|-m module}
#                              -f focus [-u users]
#       
#               -H         Displays this usage message.
#               -o         Open the access list.  Can be used with -u.
#               -c         Close the access list.
#               -a         Add user(s) to the access list. Use with -u.
#               -d         Delete user(s) from the access list. Use with -u.
#               -b branch  Specifies the branch.
#               -m module  Specifies the module.
#               -f focus   Specifies the focus in which to make the changes.
#               -r reason  Specifies the reason for modifying.
#               -u userid  Space seperated list of CVS usernames. Default is all.
#
# Output:       May be error or progress message output.
#
# Libraries:    //$ENV{'TOOLS_DIRECTORY'}/lib
#
#               From package Birt:  CVS, Focus, Array.
#
# Dependencies: No additional dependencies.
#
# Side Effects: Files checked out into a temp area on local drive or local
#               directory.  The files are cleaned up, but in the case of
#               certain interruptions or errors they may be left behind.
#
# Functions:    None
#
#--------------------------------------------------------------------------------


#--------------------------------------------------------------------------------
#
# PRE-PROCESSED CODE BLOCK:
#
#    Make sure we have a tools directory defined; if not, attempt defaults.
#
#--------------------------------------------------------------------------------
BEGIN {
if (! defined($ENV{'TOOLS_DIRECTORY'}))
   {
   if ( "$^O" =~ /win/i )
      {
      $ENV{'TOOLS_DIRECTORY'} = "//lego.rtp.dg.com/tools";
      }
   else
      {
      $ENV{'TOOLS_DIRECTORY'} = "/pdd/cvs";
      }
   }
}


#--------------------------------------------------------------------------------
#
# INCLUDED LIBRARIES:
#
#    Birt::CVS   = Various CVS repository specific functions
#    Birt::Array = Generic array manipulation functions
#    Birt::Focus = Focus functions for acquiring FocusInfo data
#    getopts.pl  = Perl pre-canned command line option acquisition routines
#
#--------------------------------------------------------------------------------
use lib "$ENV{'TOOLS_DIRECTORY'}/lib";

require "getopts.pl";

use Birt::CVS   qw ( open_branch
                     close_branch
                     add_users_to_branch
                     remove_users_from_branch
                     open_module
                     close_module
                     add_users_to_module
                     remove_users_from_module
                     user_is_authorized_to_change_access
                   );

use Birt::Focus qw ( get_focusinfo_field 
                     get_all_focuses
                     get_focus_branches
                     get_focus_modules
                   );

use Birt::Array qw ( uniq
                     is_element
                   );


#--------------------------------------------------------------------------------
#
# BEGIN MAIN EXECUTION BLOCK:
#
#    $options       = Command line option syntax list for Getopts().
#
#    $admin_user    = CVS user attempting to make the access modification.  This
#                     is based on Windows domain\username, where username is the
#                     portion assumed to be the user's CVS username.
#
#    @valid_focuses = List of all currently valid focuses.
#
#    $status        = Execution status of this script.
#
#    @users         = List of usernames to be added/removed to/from access.
#
#    $branch        = Branch out of which we are working.  If branch access is
#                     being manipulated, that value is used.  If module access is
#                     being manipulated, 'DEFAULT' is used.
#
#    $object        = One of two values:  'branch' or 'module', indicating what
#                     type of access to manipulate.
#
#    $object_value  = The actual branch or module to modify.
#
#    $access_file   = Derived based on focus and branch, this is the CVSROOT-
#                     relative path to the relevant access file.
#
#    $USAGE         = Command line usage message.    
#
#--------------------------------------------------------------------------------
my ($options)       = "Hr:ocadf:b:m:u:";
my ($admin_user)    = $ENV{'USERNAME'};
my (@valid_focuses) = &get_all_focuses();
my ($status)        = 0;
my (@users)         = ();
my ($branch)        = "";
my ($object)        = "";
my ($object_value)  = "";
my ($access_file)   = "";
my ($USAGE)         = "
Usage: modify_access [-H] [-r reason] {-o|-c|-a|-d} {-b branch|-m module} -f focus [-u users]
       
       -H          Displays this usage message.
       -o          Open the access list.  Can be used with -u.
       -c          Close the access list.
       -a          Add user(s) to the access list.  Must be used with -u.
       -d          Delete user(s) from the access list.  Must be used with -u.
       -b branch   Specifies the branch (eg. '-f amber').
       -m module   Specifies the module (eg. '-m nasui').
       -f focus    Specifies the focus in which to make the changes (eg. '-f c2').
       -r reason   Specifies the reason for modifying (eg. '-r \"closing to cut pass 1.2\"').
       -u userid   Space seperated list of CVS usernames.  Default is all active CVS users.
       
       \$CVSROOT must be set to a valid and authorized user.
       ";

#
# We are dealing with two sets of actions here:  one for branch
# manipulation, and one for module manipulation.  However, they
# all have the same input structure in common, making this an
# elegant method of delivering to the appropriate function.
#
my (%map_to_function)   = (

   #
   # Branch manipulation functions.
   #
   "open:branch"   => \&open_branch,
   "close:branch"  => \&close_branch,
   "add:branch"    => \&add_users_to_branch,
   "delete:branch" => \&remove_users_from_branch,

   #
   # Module manipulation functions.
   #
   "open:module"   => \&open_module,
   "close:module"  => \&close_module,
   "add:module"    => \&add_users_to_module,
   "delete:module" => \&remove_users_from_module,
);

#
# Get the command line arguments; Getopts parses basic usage as well.
#
if ( ! Getopts($options) || $opt_H)
   {
   die "$USAGE\n";
   }

#
# $CVSROOT must be set
#
if (!defined($ENV{'CVSROOT'}))
   {
   die "\n".
       "ERROR:  Your \$CVSROOT environment variable must be set to a valid, authorized user.\n".
       "\n";
   }

#
# We must have a valid focus.
#
if (! $opt_f || ! &is_element ($opt_f, @valid_focuses))
   {
   die "\n".
       "ERROR:  You must specify a valid focus.  See modify_access -H\n".
       "        for usage.  Valid focuses are:  \n".
       "\n".
       join ("\n", @valid_focuses).
       "\n".
       "\n";
   }

#
# We must act on either a branch or module.  The branch
# or module must be valid (found in FocusInfo.pm).
#
if ($opt_b)
   {
   $object = 'branch';
   $object_value = $opt_b;
   $branch = $object_value;
   my (@valid_branches) = &get_focus_branches ($opt_f);
   
   if (! &is_element ($object_value, @valid_branches))
      {
      die "\n".
          "ERROR:  You must specify a valid branch.  See modify_access -H\n".
          "        for usage.  Valid branches for focus $opt_f are:  \n".
          "\n".
          join ("\n", @valid_branches).
          "\n".
          "\n";
      }
   }
elsif ($opt_m)
   {
   $object = 'module';
   $object_value = $opt_m;
   $branch = 'DEFAULT';
   my (@valid_modules) = &get_focus_modules ($opt_f);
   
   if (! &is_element ($object_value, @valid_modules))
      {
      die "\n".
          "ERROR:  You must specify a valid module.  See modify_access -H\n".
          "        for usage.  Valid modules for focus $opt_f are:  \n".
          "\n".
          join ("\n", @valid_modules).
          "\n".
          "\n";
      }
   }
else
   {
   die "\n".
       "ERROR:  You must specify either a branch or a module.  See\n".
       "        modify_access -H for usage.\n".
       "\n";
   }

#
# Authorize the user's right to change access.
#
if (! &user_is_authorized_to_change_access ($opt_f, $branch, "$ENV{'USERDOMAIN'}\\$admin_user"))
   {
   die "\n".
       "ERROR:  $ENV{'USERDOMAIN'}\\$admin_user does not have the right to\n".
       "        change access for focus $opt_f, $object $object_value.\n".
       "\n";
   }

#
# We must have one and only one action specified.
#
if ($opt_o + $opt_c + $opt_a + $opt_d != 1)
   {
   die "\n".
       "ERROR:  You must specify an action.  Only one action can be\n".
       "        specified at any one time.  Valid actions are open,\n".
       "        close, add, or delete.  See modify_access -H for usage.\n".
       "\n";
   }

#
# Add and delete require at least one username input from -u.
#
@users = split (" ", $opt_u);
if (($opt_a || $opt_d) && ! @users)
   {
   die "\n".
       "ERROR:  You must specify at least one username with -u.\n".
       "See modify_access -H for usage.\n".
       "\n";
   }

#
# Map action and object to the relevant function, then exit with
# the appropriate status.
#
$action = 'open'   if ($opt_o);
$action = 'close'  if ($opt_c);
$action = 'add'    if ($opt_a);
$action = 'delete' if ($opt_d);
$opt_r  = "Performing $action on $object $object_value" if (! $opt_r);
$access_file = &get_focusinfo_field ($opt_f, $opt_m ? 'DEFAULT' : $opt_b, $object."_access_file");

print "\nPerforming $action on $object $object_value...\n";
$status = $map_to_function{"$action:$object"}->($object_value, $access_file, $admin_user, $opt_r, @users);

if ($status != 0)
   {
   print "Successfully completed.\n\n";
   exit (0);
   }
else
   {
   print "An error occurred during execution of the $action;\n";
   print "see the above messages for details.\n\n";
   exit (1);
   }

