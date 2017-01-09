package buildf;

use Cwd;
use File::Basename;
use File::Copy;


if ( $^O eq "MSWin32" ) {
    $CP="copy /y";
    $PWD="cd";
    $RM="del /f /q";
    $dospath=~ s/\//\\/g;
    $MOVE="move /y ";
    $RW="attrib -R";
} else {
    $PWD="pwd";
    $RM="rm";
    $MOVE="mv -f";
    $CP="cp";
    $RW="/usr/local/bin/chmod 777";
}


sub devstudio_version
{
    my $rc ;
    # the process here is move the orginal file away to ${file).bak
    # use this file.bak for reading
    # recreate the orginal file with the changes
    my $versionfile = $_[0];
    my $newdate     = $_[1];
    my $versionfile_bak = "${versionfile}.bak";

    # add to debug the script 
    print "\$RW: $RW\n";
    print "\$RM: $RM\n";
    print "\$MOVE: $MOVE\n";
	
    if ( -e "$versionfile" ) {

	$rc = system("$RW $versionfile");	# before moving, need to change its permission 
	print "\n$RW $versionfile return:\n";
	print "$rc\n";

	# by default, read only mode when pulling source in the build_work_area
	if ( -e $versionfile_bak ) {
	    print "There is back up file: $versionfile_bak\n";
	    $rc = system("$RW $versionfile_bak");
	    print "\n$RW $versionfile_bak return:\n";
	    print "$rc\n";
	    $rc = system("$RM  $versionfile");
	    print "\n$RM $versionfile_bak return:\n";
	    print "$rc\n";
	}
	else { 
	    $rc = system("$MOVE $versionfile $versionfile_bak");
	    print "\n$MOVE $versionfile $versionfile_bak return:\n";
	    print "$rc\n";
	}

	# create the new version file with update version changes
	open(FHI, "< ${versionfile_bak}") || die "failed to open file for reading ${versionfile_bak} $!";
	open(FHO, "> ${versionfile}") || die "failed to open file for writing ${versionfile} $!";
	while ( $line = <FHI> ) {
	    $line =~ s/\@\@BUILD_DATE.*/${newdate}/;
	    print FHO $line;
	}
	close FHI;
	close FHO;
    }
    else {
	$rc = system("$PWD");
	print "ERROR: $versionfile does not exist at the from this current directory. \$PWD return: $rc\n";
    }
}

sub msdevbuild {
      ## Build dsp or mak file directly
      my $msbasedir=$_[0];
      my $msprojdir=$_[1];
      my $msprojname=$_[2];
      my $msprojtarget=$_[3];
      my $msprojdirfull=pathconv("$msbasedir/$msprojdir");
      chdir "$msprojdirfull" ;
#      print " msprojtarget=$msprojtarget\n";
      if ( -e  "$msprojname.dsp" ) {
#      print  "msdev $msprojname.dsp /MAKE \"$msprojtarget\"  /REBUILD /NORECURSE\n";
            systemcmd ("msdev $msprojname.dsp /MAKE \"$msprojtarget\"  /REBUILD /NORECURSE") ;
      } elsif  ( -e  "$msprojname.mak" ) {
            systemcmd ("nmake /s /nologo /f $msprojname.mak CFG=\"$msprojtarget\"  /REBUILD /NORECURSE") ;
      }
}
sub msdevbuildlist {
      ## Build nt files from build list
      my $msbasedir=$_[0];
      my $msprojlist=$_[1];
      open (MSPROJLIST,"$msprojlist");
            while ($pline = <MSPROJLIST>) {
                   my $msprojdir=$pline;
                      $msprojdir=~ s/\t.*$//o;
                      chop($msprojdir);
                   my $msprojname=$pline;
                      $msprojname=~ s/^\S*\t*//o;
                     $msprojname=~ s/\t.*$//o;
                     $msprojname=~ s/\W//g;
                   my $msprojtarget=$pline;
                      $msprojtarget=~ s/^.*\t//o;
                      $msprojtarget=~ s/\"//g;
                      chop($msprojtarget);


            msdevbuild("$msbasedir","$msprojdir", "$msprojname", "$msprojtarget");

            }
      close (MSPROJLIST);

}


sub pathconv {

    $dospath= $_[0];
    if ( $^O eq "MSWin32" ) {
    $dospath=~ s/\//\\/g;
    }
    return $dospath;
}

#------------------------------------------------------------------
# systemcmd
# pass a list (array) with the command and parameters you need to run
# This subroutine runs a native system command
# return code is 0 - good
#                1 - bad
#------------------------------------------------------------------
sub systemcmd {

     my $cmd=$_[0];
     $rcode = 0;
     my $cal_output=`$cmd` or $rcode = 1;
     print LOGHANDLE "$cal_output\n";
     #$rcode = system("$cmd");
     $TS = TimeStamp();
     if ($rcode == 0) {
          DisplayandLog("$TS>SUCCEEDED: $cmd\n");
#         print "$TS>$cmd\n";
#         print LOGHANDLE "$TS>SUCCEEDED: $cmd\n";
     }
     else {
           DisplayandLog("$TS>FAILED: $cmd\n");
#         print "$TS>FAIL: $cmd\n";
#         print LOGHANDLE "$TS>FAIL: $cmd\n";
         $rcode = 1;
         }
     return $rcode;

} #end systemcmd


#------------------------------------------------------------------
# TimeStamp
# pass back the date and time
# if you pass an argument to this function it will return unformated
# date and time.
#------------------------------------------------------------------
sub TimeStamp {

    my $ts_flag = $_[0];       #might want to check the argument
    ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    if ($year == 0) {
        $year = 2000;
        }
        else
        {
            $year = $year + 1900;
            }
    ++$mon;                                   #$mon is an array so it starts with 0
    $arg_cnt = $numberOfElements = @_;
    if ( $sec < 10 ) { $sec = "0$sec" ;}
    if ( $min < 10 ) { $min = "0$min" ;}
    if ( $hour < 10 ) { $hour = "0$hour" ;}
    if ( $mday < 10 ) { $mday = "0$mday" ;}
    if ( $mon < 10 ) { $mon = "0$mon" ;}
    if  ($arg_cnt > 0) {
        return "$mon$mday$year$hour$min$sec";
        }
    return "$mon/$mday/$year $hour:$min:$sec";


} #end TimeStamp


#------------------------------------------------------------------
# DisplayandLog
# This subroutine prints a message to stdout (your display) and
# if LOGGING is set also prints the message to the log file
#------------------------------------------------------------------
sub DisplayandLog {
    my $msg = $_[0];
    my $TS = TimeStamp();
    print $msg . "\n";
    print LOGHANDLE "$TS>$msg\n";
} #end DisplayandLog

#------------------------------------------------------------------
# StartLog
# Initializes the log file
#------------------------------------------------------------------
sub StartLog {
    my $LOGFILE = $_[0];
    my $TS = TimeStamp();
    open (LOGHANDLE, ">$LOGFILE") or die "can't open $LOGFILE";
    print LOGHANDLE "$TS>Log started\n\n";
} #end StartLog
sub EndLog {
    print LOGHANDLE "$TS>Log end\n";
    close (LOGHANDLE);
} #end StartLog
#------------------------------------------------------------------
# LogError
# log error to $LOGFILE
#------------------------------------------------------------------
sub LogError {
    $TS = TimeStamp();
    print LOGHANDLE "$TS>cmd fail: @_\n";
}

sub sendemail {

    my $tolist= $_[0];
    my $email_subject= $_[1];
    my $sendfile= $_[2];
    my $mail_attach= $_[3];

    print " tolist= $tolist\n esubject=$esubject\n sendfile=$sendfile\n attachfile=$attachfile\n";
    my $email_rec="";
    open (EMAILLIST,"$tolist");
             while ($pline = <EMAILLIST>) {
                    my $recipient=$pline;
                    chop($recipient);
                    if ( $email_rec eq "" ) { $email_rec="$recipient";
                    }  elsif ( ! $recipient eq "" ){
                    $email_rec="$email_rec,$recipient";
                    }
             }  #while
    close (EMAILLIST);
    print " email_rec=$email_rec\n";
    if ( $^O eq "MSWin32" ) {
           print "blat $sendfile -s \"$email_subject\" -t $email_rec $mail_attach\n";
          system ("blat $sendfile -s \"$email_subject\" -t $email_rec $mail_attach");
    } else {
          system ("mailx -s \"$email_subject\"  \"$rec_list\" < $sendfile");
    }
    print "Email Sent.\n";
}

sub swapversion_helpabout {
   my $versionfile=$_[0];
   my $build_type=$_[1];
   my $build_version=$_[2];
   my $build_timestamp=$_[3];
   
   $versionfile_bak="$versionfile.bak";
   print "   versionfile\=$versionfile  build_type\=$build_type build_version\=$build_version build_timestamp\=$build_timestamp \n";

   system("$RW $versionfile");
   
   if ( -e $versionfile_bak ) {
	system("$RW $versionfile_bak");
        system("$RM  $versionfile");
     }
   else { system("$MOVE $versionfile $versionfile_bak");
   }

   if ( $build_type eq "b" ) { $build_or_patch="Build";}
   elsif ( $build_type eq "p" ) { $build_or_patch="Patch";}
   elsif ( $build_type eq "sp" ) { $build_or_patch="SP";}
   elsif ( $build_type eq "bt" ) { $build_or_patch="Beta";}
   elsif ( $build_type eq "d" ) { $build_or_patch="Build";}
  
   open(VERFILE,"$versionfile_bak");
   open(VERFILE2,">$versionfile");
   while ($pline = <VERFILE>) {
          if ( $pline =~ /strBuildBase = / )
		  {
            if ( ( $build_type eq "b" ) || ( $build_type eq "d" ) ) 
			 { $pline = "   strBuildBase = \"\";\n"; }
            elsif ( $build_type eq "bt" )
               { $pline = "   strBuildBase = \"$build_or_patch $build_version\";\n"; }
            else { $pline = "   strBuildBase = \"$build_or_patch\";\n"; }
          }
           print VERFILE2 "$pline";
   }
   close(VERFILE);
   close(VERFILE2);
}

sub swapversion_native {
   my $versionfile=$_[0];
   my $build_type=$_[1];
   my $build_version=$_[2];
   my $build_timestamp=$_[3];
   $versionfile_bak="$versionfile.bak";
   
   print "   versionfile\=$versionfile  build_type\=$build_type build_version\=$build_version build_timestamp\=$build_timestamp \n";

   my $sp=substr($build_version,0,2);
   my $patch=substr($build_version,2,3);

   
   system("$RW $versionfile");
   
   if ( -e $versionfile_bak ) {
	system("$RW $versionfile_bak");
        system("$RM  $versionfile");
   }
   else { system("$MOVE $versionfile $versionfile_bak");
   }

   if ( $build_type eq "b" ) { $build_or_patch="Build";}
   elsif ( $build_type eq "p" ) { $build_or_patch="Patch";}
   elsif ( $build_type eq "sp" ) { $build_or_patch="SP";}
   elsif ( $build_type eq "bt" ) { $build_or_patch="Beta";}
   elsif ( $build_type eq "d" ) { $build_or_patch="Build";}
  
   open(VERFILE,"$versionfile_bak");
   open(VERFILE2,">$versionfile");
   while ($pline = <VERFILE>) {

          if ( $pline =~ /\043define AR_VERSION_BUILD_TIME/ ) {
                $pline = "\043define AR_VERSION_BUILD_TIME   \"$build_timestamp\"\n";
          }
          
          if ( $pline =~ /\043define AR_VERSION_ARS_WIN / ) {
            if ( ( $build_type eq "bt" ) || ( $build_type eq "d" ) )
            {
                $pline = "\043define AR_VERSION_ARS_WIN      \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp \"\n";
            }
            else {$pline = "\043define AR_VERSION_ARS_WIN      \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$build_version\"\n";};
          }

          if ( $pline =~ /\043define AR_VERSION_ARS_SHORT / ) {
            if ( ( $build_type eq "bt" ) || ( $build_type eq "d" ) )
            {
                $pline = "\043define AR_VERSION_ARS_SHORT    \"$ENV{VER_MAJOR}.$ENV{VER_MINOR} $build_or_patch $build_version\"\n";
            }
            else {$pline = "\043define AR_VERSION_ARS_SHORT    \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}\"\n";}
          }
          
          if ( $pline =~ /\043define AR_VER_DROP_OR_PATCH / ) {
            if ( ( $build_type eq "bt" ) || ( $build_type eq "d" ) )
            {
                $pline = "\043define AR_VER_DROP_OR_PATCH    00\n";
            }
            else {$pline = "\043define AR_VER_DROP_OR_PATCH    $build_version\n";};
          }

          if ( $pline =~ /\043define AR_VERSION_ARS / ) {
                  $tempstr=$pline;          
	              @array=split(" ", $tempstr);
	              if ( $array[0] ne '/*' ) 
				  {
                    if ( ( "$sp" eq "00") && ( "$patch" eq "000" ) ) 
					  {
                           $pline = "\043define AR_VERSION_ARS          \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp \" AR_VERSION_BUILD_TIME\n";
                      }
					elsif ( ( "$sp" ne "00") && ( "$patch" eq "000" ) ) 
  				   	 {
                          $pline = "\043define AR_VERSION_ARS          \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp \" AR_VERSION_BUILD_TIME\n";
                     }
					elsif ( ( "$sp" eq "00") && ( "$patch" ne "000" ) ) 
  				   	 {
                          $pline = "\043define AR_VERSION_ARS          \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp.$patch \" AR_VERSION_BUILD_TIME\n";
                     }  
					elsif ( ( "$sp" ne "00") && ( "$patch" ne "000" ) ) 
  				   	 {
                          $pline = "\043define AR_VERSION_ARS          \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp.$patch \" AR_VERSION_BUILD_TIME\n";
                     } 
                  }
          }
           print VERFILE2 "$pline";
   }
   close(VERFILE);
   close(VERFILE2);
}

sub swapversion_emaild {
   my $versionfile=$_[0];
   my $build_type=$_[1];
   my $build_version=$_[2];
   my $build_timestamp=$_[3];
   
   $myconst = "\t\tpublic final String clientVersion=";
   $myclient = "clientVersion=";   
   $versionfile_bak="$versionfile.bak";
   
   print "   versionfile\=$versionfile  build_type\=$build_type build_version\=$build_version build_timestamp\=$build_timestamp \n";

   my $sp=substr($build_version,0,2);
   my $patch=substr($build_version,2,3);   
	 
   system("$RW $versionfile");
   
   if ( -e $versionfile_bak ) {
	      system("$RW $versionfile_bak");
        system("$RM  $versionfile");
     }
   else { system("$MOVE $versionfile $versionfile_bak");
   }

   if ( $build_type eq "b" ) { $build_or_patch="Build";}
   elsif ( $build_type eq "p" ) { $build_or_patch="Patch";}
   elsif ( $build_type eq "sp" ) { $build_or_patch="SP";}
   elsif ( $build_type eq "bt" ) { $build_or_patch="Beta";}
   elsif ( $build_type eq "d" ) { $build_or_patch="Build";}
  
	open(VERFILE,"$versionfile\.bak");
	open(VERFILE2,">$versionfile");
	while ($pline = <VERFILE>) {		
			$tempstr=$pline; 
			if ($tempstr =~ /$myclient/) {
					@array=split(" ", $tempstr);
					chop $array[6];
					chop $array[6];

  	      if( ( "$sp" eq "00") && ( "$patch" eq "000" ) )
		    {
              $mystr="$myconst\" $array[4] $build_or_patch$sp $build_timestamp\";";
            }
		  elsif ( ( "$sp" ne "00") && ( "$patch" eq "000" ) ) 
  			{
               $mystr="$myconst\" $array[4] $build_or_patch$sp $build_timestamp\";";
            }
		  elsif ( ( "$sp" eq "00") && ( "$patch" ne "000" ) ) 
  			{
              $mystr="$myconst\" $array[4] $build_or_patch$sp $build_timestamp\";";
            }  
			elsif ( ( "$sp" ne "00") && ( "$patch" ne "000" ) ) 
  			{
              $mystr="$myconst\" $array[4] $build_or_patch$sp Patch $patch $build_timestamp\";";
            } 
          
					print VERFILE2 "$mystr\n";
			}
			else {
					print VERFILE2 "$pline";
			}
	}
	close(VERFILE);
	close(VERFILE2);
}

sub swapversion_buildpatchnumber
{
   my $versionfile=$_[0];
   my $build_type=$_[1];
   my $build_version=$_[2];
   my $build_timestamp=$_[3];
   my $versionfileP=$_[4];

   my $sp=substr($build_version,0,2);
   my $patch=substr($build_version,2,3);  

   system("$RW $versionfile");
   system("$RW $versionfileP");
      
   if ( $build_type eq "b" ) { $build_or_patch="Build";}
   elsif ( $build_type eq "p" ) { $build_or_patch="Patch";}
   elsif ( $build_type eq "sp" ) { $build_or_patch="SP";}
   elsif ( $build_type eq "bt" ) { $build_or_patch="Beta";}
   elsif ( $build_type eq "d" ) { $build_or_patch="Build";}

 if ( ( $build_type eq "b" ) || ( $build_type eq "bt" ) || ( $build_type eq "d" ) ) {

     if ( -e $versionfile) { system("$RM  $versionfile");}
     print "   versionfile\=$versionfile  build_type\=$build_type build_version\=$build_version build_timestamp\=$build_timestamp \n";   
     open(VERFILE, ">$versionfile");    
     if ( ( "$sp" eq "0" ) || ( "$sp" eq "00") ) {
        $mystr="$sp $build_timestamp";
     }else{
        $mystr="$build_timestamp";
     }

     print VERFILE $mystr;
     close(VERFILE);
     print "++ Version file '$versionfile' changed to '$mystr'\n";
   }
   else {
     # Change patchnumber file 
     if ( -e $versionfileP) { system("$RM  $versionfileP");}
     print "   versionfile\=$versionfileP  build_type\=$build_type build_version\=$build_version build_timestamp\=$build_timestamp \n";   
	 open(VERFILEP, ">$versionfileP");     

		  if ( ( "$sp" ne "00") && ( "$patch" eq "000" ) ) 
  			{
               $mystr="$sp $build_timestamp";
            }
		  elsif ( ( "$sp" eq "00") && ( "$patch" ne "000" ) ) 
  			{
              $mystr="$patch $build_timestamp";
            }  
			elsif ( ( "$sp" ne "00") && ( "$patch" ne "000" ) ) 
  			{
              $mystr="$sp.$patch $build_timestamp";
            } 
	 
     print VERFILEP $mystr;
     close(VERFILEP);
     print "++ Version file '$versionfileP' changed to '$mystr'\n";
   }
}

sub swapversion_driver
{
   my $versionfile=$_[0];
   my $build_type=$_[1];
   my $build_version=$_[2];
   my $build_timestamp=$_[3];

   if ( $build_type eq "b" ) { $build_or_patch="Build";}
   elsif ( $build_type eq "p" ) { $build_or_patch="Patch";}
   elsif ( $build_type eq "sp" ) { $build_or_patch="SP";}
   elsif ( $build_type eq "bt" ) { $build_or_patch="Beta";}
   elsif ( $build_type eq "d" ) { $build_or_patch="Build";}
      
   $versionfile_bak="$versionfile.bak";
   print "   versionfile\=$versionfile  build_type\=$build_type build_version\=$build_version build_timestamp\=$build_timestamp \n";

   my $sp=substr($build_version,0,2);
   my $patch=substr($build_version,2,3);   
   

   system("$RW $versionfile");
   
   if ( -e $versionfile_bak ) {
	      system("$RW $versionfile_bak");
        system("$RM  $versionfile");
   }
   else { system("$MOVE $versionfile $versionfile_bak");
   }
  
   open(VERFILE,"$versionfile_bak");
   open(VERFILE2,">$versionfile");
   while ($pline = <VERFILE>) {

          # Search for #define AR_VERSION_DRIVER
          if ( $pline =~ /\043define AR_VERSION_DRIVER/ ) {
			if( ( "$sp" eq "00") && ( "$patch" eq "000" ) )
		     {
                $pline = "\043define AR_VERSION_DRIVER \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp $build_timestamp\"\n";
             }
		     elsif ( ( "$sp" ne "00") && ( "$patch" eq "000" ) ) 
  			 {
               $pline = "\043define AR_VERSION_DRIVER \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp $build_timestamp\"\n";
             }
		     elsif ( ( "$sp" eq "00") && ( "$patch" ne "000" ) ) 
  			 {
              $pline = "\043define AR_VERSION_DRIVER \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp.$patch $build_timestamp\"\n";
             }  
			 elsif ( ( "$sp" ne "00") && ( "$patch" ne "000" ) ) 
  			 {
              $pline = "\043define AR_VERSION_DRIVER \"$ENV{VER_MAJOR}.$ENV{VER_MINOR}.$sp.$patch $build_timestamp\"\n";
             } 
          }
          print VERFILE2 "$pline";
   }
   close(VERFILE);
   close(VERFILE2);
}

# Migrator 7.1 and above
sub swapversion_migrator
{
   my $versionfile=$_[0];
   my $build_type=$_[1];
   my $build_version=$_[2];
   my $build_timestamp=$_[3];
   my $buildtimeinseconds = time() - (8 * 3600);   # seconds since jan 01 1970 - 8 hr
   
   if ( $build_type eq "b" ) { $build_or_patch="Build";}
   elsif ( $build_type eq "p" ) { $build_or_patch="Patch";}
   elsif ( $build_type eq "sp" ) { $build_or_patch="SP";}
   elsif ( $build_type eq "bt" ) { $build_or_patch="Beta";}
   elsif ( $build_type eq "d" ) { $build_or_patch="Build";}
   
   $versionfile_bak="$versionfile.bak";
   print "   versionfile\=$versionfile  build_type\=$build_type build_version\=$build_version build_timestamp\=$build_timestamp \n";

   my $sp=substr($build_version,0,2);
   my $patch=substr($build_version,2,3);  

   chmod 0644, ( $versionfile );
#   system("$RW $versionfile");
   
   if ( -e $versionfile_bak ) {
       chmod 0644, ( $versionfile_bak );
#       system("$RW $versionfile_bak");
       if (unlink "$versionfile") {
	   print "Successful remove the old $versionfile\n";
	   print "Use $versionfile_bak to generate a new $versionfile\n";
       }
       else {
	   print "Failed to remove the old $versionfile\n";
       }
#        system("$RM  $versionfile");
   }
   else { 
       print "rename $versionfile -> $versionfile_bak\n";
       move("$versionfile", "$versionfile_bak") or die "move failed: $!\n";
#       system("$MOVE $versionfile $versionfile_bak");
   }
  
   open(VERFILE,"$versionfile_bak");
   open(VERFILE2,">$versionfile");
   while ($pline = <VERFILE>) {
       if ( $pline =~ /\043define CREATEDATE/ ) {
	   $tempstr=$pline;          
	   @array=split(" ", $tempstr);
	   if ( $array[1] eq "CREATEDATE" ) {
	       $array[2] = $buildtimeinseconds;
	       $pline = join(" ", @array);
	   }
	   print "$pline\n";
       }
     
     # Normal build or API versioning
     if ( ( $build_type eq "b" ) || ( $build_type eq "d" ) ) {
          if ( $pline =~ /\043define TAG/ ) {
             $tempstr=$pline;          
	     @array=split(" ", $tempstr);
	     if ( $array[0] eq "#define" ) {
		 $pline = "//$tempstr";
		 print "$pline\n";
             }
          }
          elsif ( $pline =~ /\043define TAGVER/ ) {
             $tempstr=$pline;          
	     @array=split(" ", $tempstr);
	     if ( $array[0] eq "#define" ) {
		 $pline = "//$tempstr";
		 print "$pline\n";
             }
          }
          elsif ( $pline =~ /\043define EXTRA/ ) {
             $tempstr=$pline;          
	     @array=split(" ", $tempstr);
	     if ( $array[0] eq "#define" ) {
		 $pline = "//$tempstr";
		 print "$pline\n";
             }
          }      
      }
      # Patch or Service Pack
      else {
          if ( $pline =~ /\043define TAG/ ) {
             $tempstr=$pline;
             @array=split(" ", $tempstr);
             # Search for #define TAG or TAGVER
             if ( $array[1] eq "TAG" ) {
                $pline = "\043define TAG         \"$build_or_patch\"\n";
             }
             elsif ( $array[1] eq "TAGVER" ) {
			   if ( ( $sp ne "00" )  && ( "$patch" eq "000" ) ) {
                $pline = "\043define TAGVER      \"$sp\"\n";
				}
			 elsif ( ( "$sp" eq "00") && ( "$patch" ne "000" ) ) {
			    $pline = "\043define TAGVER      \"$patch\"\n";
				}
			 elsif ( ( "$sp" ne "00") && ( "$patch" ne "000" ) ) {
				$pline = "\043define TAGVER      \"$sp.$patch\"\n";
				}	
             }
             print "   Version file '$versionfile' changed to '$pline'";
          }
		  
		 ## Commenting out below lines since FILEVER does not need to change by build scripts. 
		 ## -- Requested by Amol Dixit Sept, 18 2012.
         # elsif ( $pline =~ /\043define FILEVER/ ) {
	     # $tempstr=$pline;
	     # @array=split(",", $tempstr);
	     ## Just place it there	      
          #if ($array[3] == 0) {
		 # $array[3] = sprintf("%d\n", $build_version);
		 # $pline = join(",",@array);
	     # }
	     #}
      }
      print VERFILE2 "$pline";
   }
   close(VERFILE);
   close(VERFILE2);
}

1;
