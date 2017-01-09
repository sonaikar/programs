#!/usr/bin/perl

#
# Filename: make_disk_image.pl
#
# Script is used to make a software upgrade image from a FE+BE kernel
# +FW+BIOS.
# Example: make_disk_image -H
#          This command will show you how to use makeimage command.
# Example: make_disk_image -B /bios_firmware/1.22_3.05.97
# 	       This command will use vxWorks and vxWorks.build_ap kernels 
#          in the current directory and will append your specified  
#          BIOS and firmware image.  Two disk images will be created 
#          in your current directory; One with and one without the 
#          BIOS and firmware attached.
#
use lib "$ENV{'TOOLS_DIRECTORY'}/lib";

use Birt::Focus qw( get_focusinfo_field );

require "getopts.pl";
use File::Basename;
use File::Copy qw(copy);

#
# Set Defaults
#
$TOOLS_DIRECTORY=$ENV{'TOOLS_DIRECTORY'};
$FSPROJECT=$ENV{'FSPROJECT'};
$AP_KERNEL="vxWorks.build_ap";
$BP_KERNEL="vxWorks";

$OUTPUT_DIR=`pwd`;
chomp $OUTPUT_DIR;
$USER_ID=`logname`;
chomp $USER_ID;

$no_fw=0;

#
# Default BIOS_FW size.
#
%Image_Size = (
'bios_fw'       => '1048576',
'clfsbin_15mb'  => '15728640', # image_15mb size is '16777216'
'clfsbin_21mb'  => '22020096',
);

# Resolve default $BIOS_AND_FW as the latest one.
$bios_firmware_rev=get_focusinfo_field('dakota', $FSPROJECT, 'bios_firmware_revision');
($bios_rev, $firmware_rev)=split /_/, $bios_firmware_rev;
$BIOS_AND_FW="$TOOLS_DIRECTORY/bin/$bios_firmware_rev";

# Usage message
my($USAGE)=
"Usage: 
make_disk_image [-H] [-B bios_and_firmware] [-o output_dir] [-f frontend_kernel] [-b backend_kernel] [-n]
      where: -H prints a help message (including this usage)
             -B bios_and_firmware default: BIOS $bios_rev and Firmware $firmware_rev
             -o output_dir        default: current directory
             -f frontend_kernel   default: 'vxWorks' in current directory
             -b backend_kernel    default: 'vxWorks.build_ap' in current directory
             -n builds an image without firmware and bios
Note: By default, only image with bios and firmware is created.
";

# Get arguments
$options = "HB:o:f:b:n";
if (! do Getopts($options))
{
  die "$USAGE";
}

if ($opt_H) {print $USAGE; exit (0);}
if ($opt_o) {$OUTPUT_DIR=$opt_o;}
if ($opt_f) {$BP_KERNEL=$opt_f;}
if ($opt_b) {$AP_KERNEL=$opt_b;}
if ($opt_n) {$no_fw=1;}
if ( $no_fw == 0 ) {
   if ($opt_B) {
	  $BIOS_AND_FW=$opt_B;
      # If the user selected their own file here, the name may not
      # indicate the revisions, but it's all we've got.
      $bios_firmware_rev=&basename($BIOS_AND_FW);
   }

   # Get the size of the bios_fw file.
   $bios_fw_size=(stat($BIOS_AND_FW))[7];

   # Check if BIOS_AND_FW is correct size (1MB)
   if ( "$bios_fw_size" ne $Image_Size{'bios_fw'} )
   {
      die "ERROR - $BIOS_AND_FW not expected size (1MB)";
   }
}

#
# Output filenames
#
$no_fw_image="$OUTPUT_DIR/IP4700_image_${USER_ID}.nofw";
$fw_image="$OUTPUT_DIR/IP4700_image_${USER_ID}.${bios_firmware_rev}";

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$rev = sprintf "%2.2d%2.2d%2.2d", $mon + 1, $mday + 1, $year %100;

# Ripper
if ($FSPROJECT =~ m/^opal/ || $FSPROJECT =~ m/^garnet/ )
{
   $RIPPER="$TOOLS_DIRECTORY/bin/ripper.15mb.exe";
   $clfsbin_size=$Image_Size{'clfsbin_15mb'};
}
else
{
   $RIPPER="$TOOLS_DIRECTORY/bin/ripper.21mb.exe";
   $clfsbin_size=$Image_Size{'clfsbin_21mb'};
}

# Check for required files 
@filelist=($AP_KERNEL, $BP_KERNEL, $RIPPER, $BIOS_AND_FW);
foreach $file (@filelist) {
   if ( ! -r $file )  
   {
      die "ERROR - Can't find required file $file.";
   }
}

if ( ! -x "$RIPPER" )
{
   die "ERROR - Can't exec $RIPPER";
}

if ( ! -d "$OUTPUT_DIR" )
{
   die "ERROR - Can't find required directory $OUTPUT_DIR";
}

print "=================================================\n";
print "Using these settings\n";
print "   BIOS/Firmware:    $BIOS_AND_FW\n";
print "   Frontend Kernel:  $BP_KERNEL\n";
print "   Backend Kernel:   $AP_KERNEL\n";
print "   Output files are: \n";
if ( $no_fw == 0 )
{
   print "                     $fw_image\n";
}
else 
{
   print "                     $no_fw_image\n";
}

print "\n";
print "=================================================\n";
print "Ripping kernel...\n";
system ("$RIPPER -rev $rev -debug $BP_KERNEL $AP_KERNEL 2>&1 > make_disk_image.out.$$");
print "=================================================\n";
print "\n";

if ( ! -r "clfs.bin" )
{ 
   print "ERROR - ripper failed to produce clfs.bin\n";
   print "        See make_disk_image.out.$$\n";
   exit 1;
}

if ( $no_fw != 0 )
{
   # Create no bios and firmware image.
   print "Creating image without BIOS and firmware...\n\n";
   copy ( "clfs.bin", "$no_fw_image");

   # Verify image's size is correct
   $no_fw_image_size=(stat($no_fw_image))[7];  
   if ("$no_fw_image_size" ne "$clfsbin_size" )
   {
      print "ERROR - Images not expected size. \n";
      print "        $no_fw_image_size  $no_fw_image\n";
	  exit 1;
   }
}
else 
{
   # Create image with bios and firmware.  
   print "Creating image with BIOS and firmware...\n\n";

   open( OUTFILE, ">$fw_image" ) or die "open outfile:$!";
   binmode OUTFILE;
   copy( "clfs.bin",  \*OUTFILE ) or die "copy infile:$!"; 
   copy( $BIOS_AND_FW, \*OUTFILE ) or die "copy infile:$!";
   close OUTFILE or die "close outfile:$!";

   # Verify image's size is correct 
   $no_fw_image_size=(stat("clfs.bin"))[7];
   $no_fw_image="clfs.bin";
   $fw_image_size=(stat($fw_image))[7];

   $expected_fw_image_size=eval( $no_fw_image_size + $bios_fw_size);
   if ( "$expected_fw_image_size" ne "$fw_image_size" )
   {
     print "ERROR - Images not expected size.\n";
     print "        $no_fw_image_size  $no_fw_image\n";
     print "        $bios_fw_size  $BIOS_AND_FW\n"; 
     print "        $fw_image_size  $fw_image\n";
     print "        Expected size: $expected_fw_image_size\n";
     print "\n";
     exit 1;
   } 
}


print "Cleaning temp files...\n\n";
unlink "make_disk_image.out.$$", "clfs.bin";
print "=================================================\n";
