#
# File: remote_copy.pl
#
# Description:  Script to copy the Dakota toolset to the following remote facilities:
#		Colorado Springs, New Jersey and South Carolina nightly from SOBO.  The 
#		script calls robocopy that compares the files before copying them to the
#		remote destination.  Only new or changed files will be copied.   
# 
#	
# Valid Arguments:  COS - Colorado Springs
#		    NJ - New Jersey
#		    SC - South Carolina
#
#	    Usage:  remote_copy.pl [COS | NJ | SC]
#		    remote_copy.pl "COS NJ SC"
#		    remote_copy.pl COS
#
# NOTES:  To copy to multiple sites at once, list the locations in double quotes (" ").
#	  This script must be ran using ActivePerl.
#

$|=1;

BEGIN {
   if (! defined ($ENV{'TOOLS_DIRECTORY'}) ) {
	$ENV{'TOOLS_DIRECTORY'} = "d:/tools";
   }
}

# Check for TOOLS_DIRECTORY, if not set hard code it

use lib "$ENV{'TOOLS_DIRECTORY'}/lib";

if ( "$^O" !~ /win/i )
   {
   die "This tool is designed to run only on Windows NT!!\n";
   }

use Birt::CVS qw( $CVS_ADMIN_EMAIL
                  notify
                );
use File::Basename;

#
# Declare variables
#
$source_dir="d:/tools";   # the source directory lives on lngag069
$name = &basename($0);

($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
$day=(Sun,Mon,Tue,Wed,Thu,Fri,Sat)[(localtime)[6]];

$to = "$CVS_ADMIN_EMAIL";
#$to = "hermosilla_carlos\@emc.com";

$location=$ARGV[0];

     if ( ! -d "$source_dir" )
      {
       print "ERROR: $source_dir does not exist.\n";

       $subject = "$name - FAILED!!"; 
       $message = "The source directory:  $source_dir does not exist.";

       notify($to, $subject, $message);

       exit;
      }

get_location($location);

sub get_location {
   my($location)=@_;
   @sites = split ' ', $location;

 foreach $remote_site (@sites) {
   if (! $remote_site) {
      die "You must give a location\n";
   }
   elsif(($remote_site eq "COS") || ($remote_site eq "cos")) {
      my($dest_dir)="//cos1.us.dg.com/sys/mirrors/cvstools";
      $cos_logfile="d:/RemoteCopyLogs/COS_remote_copy_output_$day";
      copy_tools($dest_dir, $cos_logfile);
   }
   elsif(($remote_site eq "NJ") || ($remote_site eq "nj")) {
      my($dest_dir)="//cheetah-s2.corp.emc.com/home/home2/tools";
      $nj_logfile="d:/RemoteCopyLogs/NJ_remote_copy_output_$day";
      copy_tools($dest_dir, $nj_logfile);
   }
   elsif(($remote_site eq "SC") || ($remote_site eq "sc")) {
      my($dest_dir)="//caetoolbox/tools";
      $sc_logfile="d:/RemoteCopyLogs/SC_remote_copy_output_$day";
      copy_tools($dest_dir, $sc_logfile);
   }
   else {
      print "$remote_site is not a valid location: COS, NJ and SC are valid values.\n";
   }
 } # foreach

 create_message("$cos_logfile $nj_logfile $sc_logfile");

}


sub copy_tools {

# Robocopy is a Microsoft console-mode application designed to simplify the task of 
# maintaining an identical copy of a directory tree in multiple locations.
# Documentation for Robocopy can be found in the /tools directory in the CVS Archive.
# robocopy does the copying of tools from the source: //lngag069.lss.emc.com/tools to
# destination: //thiin-cos/tools
# 
# Options Used:  /E : copy subdirectories, including empty ones
#		 /R:3 : number of retries on failed copies
#		 /NP : No Progress - don't display % copied
#		 /PURGE : delete destination files/dirs that no longer exist in source
#		 /XD : eXclude Directories matching given names/paths

     my($dest_dir, $logfile) = @_;
     if (! (-e "$ENV{'TOOLS_DIRECTORY'}/bin/robocopy.exe")) {
	print "Robocopy doesn't exist\n";
	exit;
     } else {
        system("$ENV{'TOOLS_DIRECTORY'}/bin/robocopy.exe $source_dir $dest_dir /E /R:3 /NP /PURGE /XD erv > $logfile 2>&1");

     }
}

sub create_message {
  my($logs)=@_;
  @files = split ' ', $logs;

  foreach $logfile (@files) {
	$exist = `C:/cygwin/bin/grep.exe  "^ERROR" $logfile`; 
	$dirs = `C:/cygwin/bin/grep.exe "Dirs :" $logfile`;
	$files = `C:/cygwin/bin/grep.exe "Files : " $logfile`;
        $end = `C:/cygwin/bin/grep.exe "Ended :" $logfile`;
	$total = `C:/cygwin/bin/grep.exe "Total  " $logfile`;
	$start = `C:/cygwin/bin/grep.exe "Started :" $logfile`;
	$newer = `C:/cygwin/bin/grep.exe "Newer" $logfile`;
	$new_file = `C:/cygwin/bin/grep.exe "New File" $logfile`;
	$source = `C:/cygwin/bin/grep.exe "Source :" $logfile`;
	$dest = `C:/cygwin/bin/grep.exe "Dest :" $logfile`;

        if ($end eq "") {
           print "Robocopy ended abnormal!!\n";

           $output .= "$name ended abnormal for: \n\n $dest";
           $output .= "\nFor more details, view the log file at $logfile on lngag069\n\n";
        } 
	elsif ($exist) {
	   print "Copy FAILED for\n $dest";

	   $output = "Copy FAILED for\n $dest\n";
	   $output .= "The following error(s) was encountered: \n\n$exist";
	   $output .= "\n* For more details, view the log file at $logfile on lngag069\n\n";
	}
	else {
	   $output = "$source";
	   $output .= "$dest\n";
	   $output .= "* Files That Were Copied:\n\n";
	   $output .= "$newer";
	   $output .= "$new_file\n";
	   $output .= "* Information About the Copy:\n\n";
	   $output .= "$start\n";
	   $output .= "$total";
	   $output .= "$dirs";
	   $output .= "$files\n";
	   $output .= "$end\n";
	   $output .= "* For more details, view the log file at $logfile on lngag069\n\n";
	}

   	$email_msg .= "\n==================================================================================\n\n";
   	$email_msg .= $output;
  }  # end foreach
}

 send_msg($email_msg);


sub send_msg {

my($email_msg) = @_;
	   $subject = "$name - COMPLETED!!";
	   $message = "$email_msg\n";

	   notify($to, $subject, $message);
}
