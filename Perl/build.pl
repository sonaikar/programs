#!/usr/local/bin/perl
#
# Usage: build.pl [-hbvsm] 
#          -h help
#          -b buildType
#          -v buildVersion
#          -s buildTimeStamp
#          -m module
#

push (@INC,"../ar_admin/buildf.pm");
use lib '../ar_admin';
use Cwd;
use File::Basename;
use File::Copy;
use buildf;
require "build_settings.pl";

use Getopt::Std;

# Parse command line

getopts('b:v:s:m:h');
$usage = "Usage: build.pl [-hbvsm] \n-h help\n-b buildType\n-v buildVersion\n-s buildTimeStamp\n-m module\n";

if ($opt_h) {
    print $usage;
    exit 0;
}
if ($opt_b) {
    $build_type=$opt_b;
}
if ($opt_v) {
    $build_version=$opt_v;
}
if ($opt_s) {
    $build_timestamp= $opt_s;
}
if ($opt_m) {
    $build_module= $opt_m;
}

$base_dir=(`$PWD`);

print "base_dir = $base_dir \n";
$base_dir=~ s/\n//o;
$LOGFILE = buildf::pathconv("$base_dir/build.log");

if ( -e $LOGFILE ) {system ("$RM  $LOGFILE");}
buildf::StartLog($LOGFILE);

# Versioning

print "++ Version Change for Module: $build_module\n";

if ( $build_type eq "b" ) { $build_or_patch="Build"; }
elsif ( $build_type eq "p" ) { $build_or_patch="Patch"; }
elsif ( $build_type eq "sp" ) { $build_or_patch="SP"; }
elsif ( $build_type eq "bt" ) { $build_or_patch="Beta"; }
elsif ( $build_type eq "d" ) { $build_or_patch="Build"; }

if ($build_module eq "server") { version_server(); version_driver(); version_server_ux(); version_bp();}
elsif ($build_module eq "email") { version_emaild(); version_bp();}
elsif ($build_module eq "admin") { version_clients();}
elsif ($build_module eq "user") { version_clients();}
elsif ($build_module eq "approval") { version_server();}
elsif ($build_module eq "assignment") { version_assignment();}
elsif ($build_module eq "midtier") { version_bp();}
elsif ($build_module eq "migrator") { version_migrator();}
elsif ($build_module eq "fbserver") { version_bp();}
elsif ($build_module eq "devstudio") { version_devstudio();}
else
{
  print "Invalid Module used: $build_module\n";
  exit(1);
}

# Originally, the version_devstudio is identical like the other
# versioning changes for other component. Somehow, it did not 
# work due to Windows cmd like attrib, move return error code.
# 
# Due to the error, it forces me to write the following. To avoid,
# using windows cmd, I use perl library to achive the same functionalites.
sub version_devstudio
{
    # convert date format from <mm/dd/yyyy> to <month dd, yyyy> 
    my $datef = $build_timestamp;
    my @olddate = split(/\//, $datef);
    # 
    if ( $olddate[0] eq "01" || $olddate[0] eq "1") {
	$olddate[0] = "January";
    }
    elsif ($olddate[0] eq "02" || $olddate[0] eq "2") {
	$olddate[0] = "February";
    }
    elsif ($olddate[0] eq "03" || $olddate[0] eq "3") {
	$olddate[0] = "March";
    }
    elsif ($olddate[0] eq "04" || $olddate[0] eq "4") {
	$olddate[0] = "April";
    }
    elsif ($olddate[0] eq "05" || $olddate[0] eq "5") {
	$olddate[0] = "May";
    }
    elsif ($olddate[0] eq "06" || $olddate[0] eq "6") {
	$olddate[0] = "June";
    }
    elsif ($olddate[0] eq "07" || $olddate[0] eq "7") {
	$olddate[0] = "July";
    }
    elsif ($olddate[0] eq "08" || $olddate[0] eq "8") {
	$olddate[0] = "August";
    }
    elsif ($olddate[0] eq "09" || $olddate[0] eq "9") {
	$olddate[0] = "September";
    }
    elsif ($olddate[0] eq "10") {
	$olddate[0] = "October";
    }
    elsif ($olddate[0] eq "11") {
	$olddate[0] = "November";
    }
    elsif ($olddate[0] eq "12") {
	$olddate[0] = "December";
    }

    # form a new date format
    my $newdate = sprintf("%s %s, %s", @olddate);


    # form the patch versioning
    #if ( ( $build_type eq "p" ) || ( $build_type eq "d" ) ){

    my $sp=substr($build_version,0,2);

    if ( ( $build_type eq "p" ) || ( $build_type eq "sp" ) ){
	     $patchString = "$build_or_patch$sp";
    }
    else {
	     $patchString = "";
    }

    # modify versioning for the following 2 files
    # plugins/com.bmc.arsys.studio.ui/about.mappings and
    # plugins/com.bmc.arsys.dataimport/about.mappings
    
    my $pwd = getcwd;		# i should be at the top devstudio directory
    my @files = ("$pwd/plugins/com.bmc.arsys.studio.ui/about.mappings", "$pwd/plugins/com.bmc.arsys.dataimport/about.mappings");
    my $versionfile;
    foreach $versionfile ( @files ) {
	($filename, $dir, undef) = fileparse($versionfile);
	chdir $dir || die "fail to change to base directory: $dir $!\n";
	chmod 0644, ( $filename );
	move("$filename", "${filename}.bak") or die "move failed: $!\n";
	open(README, "$filename.bak") || die "failed to open to read $!\n";
	open(WRITEME, "> $filename") || die "failed to open to write $!\n";
	while ($line = <README> ) {
	    $line =~ s/\@\@BUILD_DATE.*/$newdate/;
	    $line =~ s/3=00/3=$sp/;
	    print WRITEME $line;
	}
	close README;
	close WRITEME;
    }
    chdir($pwd);
}

# Server and Approval Server
sub version_server
{
  $versionfile=buildf::pathconv("common/include/arvers.h");
  buildf::swapversion_native($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";
}

# Server UNIX 
sub version_server_ux
{
  print "   Version Change for unix\n";
  $versionfile=buildf::pathconv("clients_unix/include/buildversion.h");
  buildf::swapversion_native($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";

  $versionfile=buildf::pathconv("clients_unix/import/util/osutil/osBuildVersion.cpp");
  buildf::swapversion_helpabout($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";

  $versionfile=buildf::pathconv("clients_unix/util/osutil/osBuildVersion.cpp");
  buildf::swapversion_helpabout($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";  
}

# server/common
sub version_driver
{
     print "   Version Change for AR System Driver\n";
     $versionfile=buildf::pathconv("common/driver/main.c");
     buildf::swapversion_driver($versionfile,$build_type,$build_version,$build_timestamp);
     print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";
     
     $versionfile=buildf::pathconv("common/driver/WFD/main.c");
     buildf::swapversion_driver($versionfile,$build_type,$build_version,$build_timestamp);
     print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";     
}

# Used by Midtier, Emaild, Flashboards, and Plug-in Servers
sub version_bp
{
  $versionfile="buildnumber";
  $versionfileP="patchnumber";
  buildf::swapversion_buildpatchnumber($versionfile,$build_type,$build_version,$build_timestamp,$versionfileP);
}

# Emaild arvers.h and Version.java
sub version_emaild
{
  $versionfile=buildf::pathconv("include/arvers.h");
  buildf::swapversion_native($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";

  $versionfile=buildf::pathconv("src/com/bmc/arsys/emaildaemon/Version.java");
  buildf::swapversion_emaild($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";
}

# Admin Tool and User Tool
sub version_clients
{
  $versionfile=buildf::pathconv("include/buildversion.h");
  buildf::swapversion_native($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";
  
  $versionfile=buildf::pathconv("util/osutil/osBuildVersion.cpp");
  buildf::swapversion_helpabout($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";
  
  if ($build_module eq "admin") {
    $versionfile=buildf::pathconv("import/util/osutil/osBuildVersion.cpp");
    buildf::swapversion_helpabout($versionfile,$build_type,$build_version,$build_timestamp);
    print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";
  }
}

# Assignment
sub version_assignment
{
  $versionfile=buildf::pathconv("asn/assignmentengine/svcd/apsvcae/arvers.h");
  buildf::swapversion_native($versionfile,$build_type,$build_version,$build_timestamp);
  print "   Version file '$versionfile' changed to $build_or_patch '$build_version'\n";
}

# Migrator version.h for release 7.1 and above.
sub version_migrator
{
  my $pwd = getcwd;		# i should be at the top devstudio directory
  $versionfile="${pwd}/version.h";
  buildf::swapversion_migrator($versionfile,$build_type,$build_version,$build_timestamp);
}

buildf::EndLog();
