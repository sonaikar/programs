#!/bin/sh

#   %full_name: wildlife#1/shsrc/ars_unix_build.sh/28 %
#   %version: 28 %
#   %date_modified: %

umask 002

##set -xv

while [ ! -z "$1" ]
do
  case "$1" in
  -s) shift; ARS_BUILD_ID="$1"; export ARS_BUILD_ID;;
  -m) shift; ARS_BUILD_OPT="$1"; export ARS_BUILD_OPT;;
  -c) shift; ARS_BUILD_COMP="$1"; export ARS_BUILD_COMP;;
  -t) shift; ARS_BUILD_TYPE="$1"; export ARS_BUILD_TYPE;;
  -r) shift; RELEASEAREA="$1"; export RELEASEAREA ;;
  *)  error Wrong argument && echo $Usage && exit 1;;
  esac
  shift
done

[ -z "$ARS_BUILD_ID" ] && echo '[ERROR] ARS_BUILD_ID is not defined' && exit 1

[ -z "$ARS_BUILD_OPT" ] && echo '[ERROR] ARS_BUILD_OPT is not defined' && exit 1

[ -z "$ARS_BUILD_COMP" ] && echo '[ERROR] ARS_BUILD_COMP is not defined' && exit 1

[ -z "$ARS_BUILD_TYPE" ] && echo '[ERROR] ARS_BUILD_TYPE is not defined' && exit 1

[ ! -z "$BLD_DEBUG" ] && set -xv && echo "FILE: $0"

[ -z "$BLDADMIN" ] && echo '[ERROR] BLDADMIN is not defined' && exit 1

export BLDADMIN         # TBD: consider sourcing setvar.sh instead

[ -f "$BLDLOC/buildcontrol.sh" ] && . $BLDLOC/buildcontrol.sh
[ -f "$BLDADMIN/lib.sh" ] && . $BLDADMIN/lib.sh
[ -f "$BLDADMIN/cpaths.sh" ] && . $BLDADMIN/cpaths.sh
[ -f "$BLDADMIN/version.sh" ] && . $BLDADMIN/version.sh

## Below variables introduced to copy entire devkits for windows builds. It will be run from build controller box. 
ARS_API_SERVER_UNIX_SRC_DIR=$cfg_root/$buildid/$app/src/unix/ars/server; export ARS_SERVER_SRC_DIR
ARS_API_SERVER_SRC_DIR=$cfg_root/$buildid/$app/src/win32/ars/server; export ARS_SERVER_SRC_DIR
ARS_MIDTIER_SRC_UNIX_DIR=$cfg_root/$buildid/$app/src/unix/ars/midtier; export ARS_MIDTIER_SRC_UNIX_DIR
ARS_MIDTIER_SRC_DIR=$BUILD_BASE/src/unix/ars/midtier; export ARS_MIDTIER_SRC_DIR
ARS_ARMigrate_SRC_DIR=$BUILD_BASE/src/unix/ars/ARMigrate; export ARS_ARMigrate_SRC_DIR
ARS_PENTAHO6_SRC_DIR=$BUILD_BASE/src/unix/ars/pentaho_6.0.1.0; export ARS_PENTAHO6_SRC_DIR
ARS_COMMON_PERIPHERALS_SRC_DIR=$BUILD_BASE/src/unix/ars/Common_peripherals; export ARS_COMMON_PERIPHERALS_SRC_DIR

build_env_out() {
  env
}

update_build_version() {

  if [ $ARCH = "linux" ]; then

    if [ $ARS_BUILD_TYPE = "Release" ]; then

      info "Updating build version for Server"
      cd $BUILD_BASE/src/unix/ars/server
      [ -f buildnumber ] && chmod 777 buildnumber
      perl $BUILD_BASE/src/unix/ars/ar_admin/build.pl -b ${VER_BUILD_TYPE} -v ${VER_PATCH} -s ${ARS_BUILD_ID} -m server 

#     info "Updating build version for Approval"
#     cd $BUILD_BASE/src/unix/ars/Approval
#     perl $BUILD_BASE/src/unix/ars/ar_admin/build.pl -b ${VER_BUILD_TYPE} -v ${VER_PATCH} -s ${ARS_BUILD_ID} -m approval

#      info "Updating build version for Assignment"
#      cd $BUILD_BASE/src/unix/ars/AssignmentEngine
#      perl $BUILD_BASE/src/unix/ars/ar_admin/build.pl -b ${VER_BUILD_TYPE} -v ${VER_PATCH} -s ${ARS_BUILD_ID} -m assignment
    elif [ $ARS_BUILD_TYPE = "Debug" ]; then

      info "Updating build version for Server"
      cd $BUILD_BASE/src/unix/ars/server_debug
      [ -f buildnumber ] && chmod 777 buildnumber
      perl $BUILD_BASE/src/unix/ars/ar_admin/build.pl -b ${VER_BUILD_TYPE} -v ${VER_PATCH} -s ${ARS_BUILD_ID} -m server 
    fi
  else
    info "[$ARCH] - Waiting for 1mins - Build Version update"
    sleep 60
  fi

}

build_ars_api() {

  if [ $ARCH = "solaris" -o \
       $ARCH = "aix" -o \
       $ARCH = "linux" -o \
       $ARCH = "hpia32" ]; then

    info "Building AR Server API"

    if [ $ARS_BUILD_TYPE = "Release" ]; then
      NONDEBUG=1
      LOGFILE_NAME=$sys.$host.api.log
      LOG_STATUS_PASS_FILE=api.$sys.succeeded
      LOG_STATUS_FAIL_FILE=api.$sys.failed
      cd $BUILD_BASE/src/unix/ars/server
    elif [ $ARS_BUILD_TYPE = "Debug" ]; then
      NONDEBUG=;
      LOGFILE_NAME=$sys.$host.api.debug.log
      LOG_STATUS_PASS_FILE=api.debug.$sys.succeeded
      LOG_STATUS_FAIL_FILE=api.debug.$sys.failed
      cd $BUILD_BASE/src/unix/ars/server_debug
    fi
    export NONDEBUG LOGFILE_NAME LOG_STATUS_PASS_FILE LOG_STATUS_FAIL_FILE


    if [ "$bit_type" -eq "32" ]; then
      $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$LOGFILE_NAME SUBSET_PROD=devkit all
    elif [ "$bit_type" =  "ia32" ]; then
      $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$LOGFILE_NAME SUBSET_PROD=devkit
    fi

    if [ $? -eq 0 ]; then
      touch $LOGDIR/$LOG_STATUS_PASS_FILE
    else
      touch $LOGDIR/$LOG_STATUS_FAIL_FILE
    fi
#######
  else
    info "API build not supported for platform -> '$ARCH'"
  fi

}

build_ars_server() {

  info "Building AR Server"

  if [ $ARS_BUILD_TYPE = "Release" ]; then
    NONDEBUG=1
    LOGFILE_NAME=$sys.$host.server.log
    CLEAN_LOGFILE_NAME=$sys.$host.server.clean.log
    LOG_STATUS_PASS_FILE=server.$sys.succeeded
    LOG_STATUS_FAIL_FILE=server.$sys.failed

    cd $BUILD_BASE/src/unix/ars/server

  elif [ $ARS_BUILD_TYPE = "Debug" ]; then
    NONDEBUG=
    LOGFILE_NAME=$sys.$host.server.debug.log
    CLEAN_LOGFILE_NAME=$sys.$host.server.debug.clean.log
    LOG_STATUS_PASS_FILE=server.debug.$sys.succeeded
    LOG_STATUS_FAIL_FILE=server.debug.$sys.failed

    cd $BUILD_BASE/src/unix/ars/server_debug
  fi
  export NONDEBUG LOGFILE_NAME CLEAN_LOGFILE_NAME LOG_STATUS_PASS_FILE LOG_STATUS_FAIL_FILE


  ## for incremental builds.
  if [ $cfg_build_type = "incremental" ]; then

    if [ $cfg_unix_build_clean = "true" ]; then

      if [ "$bit_type" -eq "32" ]; then
        $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$CLEAN_LOGFILE_NAME clean
      elif [ "$bit_type" -eq "64" ]; then
        $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$CLEAN_LOGFILE_NAME SUBSET_PROD=server_overlay clean
      elif [ "$bit_type" =  "ia32" ]; then
        $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$CLEAN_LOGFILE_NAME clean
      fi
    fi
  fi

  if [ "$bit_type" -eq "32" ]; then
    $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$LOGFILE_NAME all
  elif [ "$bit_type" -eq "64" ]; then
    $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$LOGFILE_NAME SUBSET_PROD=server_overlay
  elif [ "$bit_type" =  "ia32" ]; then
    $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$LOGFILE_NAME
  fi


  if [ $? -eq 0 ]; then
    touch $LOGDIR/$LOG_STATUS_PASS_FILE
  else
    touch $LOGDIR/$LOG_STATUS_FAIL_FILE
  fi

}

copy_api_devkits() {

  cd $BUILD_BASE/src/unix/ars/server/common/devkit 

  info "Updating AR API devkit bom file for '$ARCH'"
  if [ -f api_devkit.bom.$ARCH ]; then 
    rm -f api_devkit.bom.$ARCH
    cat api_devkit.bom | sed -e 's/ar_ux\/\$DROPNAME\///g' > api_devkit.bom.$ARCH
  else
    cat api_devkit.bom | sed -e 's/ar_ux\/\$DROPNAME\///g' > api_devkit.bom.$ARCH
  fi

  info "Updating ars devkit area -> '${DEVKITS_DIR}/$app/$version/$ARS_BUILD_ID/$ARCH'"
  perl $BUILD_BASE/src/unix/ars/server/common/devkit/mkapi.pl -d ${ARS_BUILD_ID} -c $version -a $ARCH -b $BUILD_BASE/src/unix/ars/server/common/devkit/api_devkit.bom.$ARCH -S $BUILD_BASE/src/unix/ars -D ${DEVKITS_DIR}/$app/$version > $LOGDIR/$sys.$host.api_devkits.log 2>&1

  egrep 'devkit status: GOOD' $LOGDIR/$sys.$host.api_devkits.log
  if [ $? -eq 0 ]; then
    touch $cfg_root/$buildid/$app/log/api_devkits.$sys.succeeded
  else
    touch $cfg_root/$buildid/$app/log/api_devkits.$sys.failed
  fi

}

copy_rik_devkits() {

  if [ $ARCH = "solaris" -o \
       $ARCH = "aix" -o \
       $ARCH = "linux" -o \
       $ARCH = "hpia32" ]; then

    info "Updating AR RIK devkit bom file for '$ARCH'"

    cd $BUILD_BASE/src/unix/ars/server/common/rik 

    [ -f rik_devkits.bom.$ARCH ] && rm -f rik_devkits.bom.$ARCH
    cat rik_devkits.bom | sed -e 's/ar_ux\/\$DROPNAME\///g' > rik_devkits.bom.$ARCH
	
	## In San Jose populating RIK devkits for aix fails with error "aix is a file and not a directory". Proactively checking and removing a file if exists may resolve this issue. 
	if [ $ARCH = "aix" -o $ARCH = "solaris" ]; then
	[ -f ${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID}/$ARCH ] && rm -f ${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID}/$ARCH; 
    fi
	 
    info "Updating rik devkit area -> '${DEVKITS_DIR}/rik/$version/$ARS_BUILD_ID/$ARCH'"
    perl $BUILD_BASE/src/unix/ars/server/common/rik/mkapi.pl -d ${ARS_BUILD_ID} -c $version -a $ARCH -b $BUILD_BASE/src/unix/ars/server/common/rik/rik_devkits.bom.$ARCH -S $BUILD_BASE/src/unix/ars -D ${DEVKITS_DIR}/rik/$version > $LOGDIR/$sys.$host.rik_devkits.log 2>&1

    egrep 'devkit status: GOOD' $LOGDIR/$sys.$host.rik_devkits.log
    if [ $? -eq 0 ]; then
      touch $cfg_root/$buildid/$app/log/rik_devkits.$sys.succeeded
    else
      touch $cfg_root/$buildid/$app/log/rik_devkits.$sys.failed
    fi
  else
    error "RIK devkit update for '$ARCH' is not supported."
  fi
}

copy_api_complete_devkits() {

  info "Start - Copy API Devkits - win32"

  [ -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/tmp.win32 ] && rm -rf $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/tmp.win32

  cd ${ARS_API_SERVER_UNIX_SRC_DIR}/common/devkit 

   [ -f api_devkit.bom.winnt ] && rm -f api_devkit.bom.winnt

    cat api_devkit.bom | sed -e 's/ar_nt\/\$DROPNAME\///g' > api_devkit.bom_windows1
    cat api_devkit.bom_windows1 | sed -e 's/\$DROPNAME\/\$ARCH\///g' > api_devkit.bom_windows

  perl mkapi_win.pl -d ${ARS_BUILD_ID} -c $version -a winnt -S ${ARS_API_SERVER_SRC_DIR} -b api_devkit.bom_windows -D $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/tmp.win32 

  echo "Move AR win32 Devkits"
  echo "From: $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/tmp.win32/$ARS_BUILD_ID/winnt"
  echo "To: $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}"

   sleep 180

  # Rename the existing folder and delete it at clean up step to avoid devkits renaming error
  [ -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/winnt ] && mv $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/winnt $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/winnt.temp
  mv $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/tmp.win32 $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/winnt

  [ -d  $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/winnt/${ARS_BUILD_ID} ] && rm -rf $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/winnt/${ARS_BUILD_ID}

  #[ -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/tmp.win32 ] && rm -rf $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/tmp.win32

  info "End - Copy API Devkits - win32"
}


build_ars_client_unix() {


  if [ $ARS_BUILD_TYPE = "Release" ]; then
    NONDEBUG=1
    LOGFILE_NAME=$sys.$host.client.log
    CLEAN_LOGFILE_NAME=$sys.$host.client.clean.log
    LOG_STATUS_PASS_FILE=client.$sys.succeeded
    LOG_STATUS_FAIL_FILE=client.$sys.failed
  elif [ $ARS_BUILD_TYPE = "Debug" ]; then
    NONDEBUG=
    LOGFILE_NAME=$sys.$host.client.debug.log
    CLEAN_LOGFILE_NAME=$sys.$host.client.debug.clean.log
    LOG_STATUS_PASS_FILE=client.debug.$sys.succeeded
    LOG_STATUS_FAIL_FILE=client.debug.$sys.failed
  fi
  export NONDEBUG LOGFILE_NAME CLEAN_LOGFILE_NAME LOG_STATUS_PASS_FILE LOG_STATUS_FAIL_FILE

  cd $BUILD_BASE/src/unix/ars/server/common/devkit 

  [ -d $BUILD_BASE/src/unix/ars/server/clients_unix/apidrop/$ARCH ] && rm -rf $BUILD_BASE/src/unix/ars/server/clients_unix/apidrop/$ARCH

  info "Updating AR API devkit (client_unix) bom file for '$ARCH'"
  if [ -f api_devkit.bom.client_unix.$ARCH ]; then
    rm -f api_devkit.bom.client_unix.$ARCH
    cat api_devkit.bom | sed -e 's/ar_ux\/\$DROPNAME\///g' > api_devkit.bom.client_unix.$ARCH
  else
    cat api_devkit.bom | sed -e 's/ar_ux\/\$DROPNAME\///g' > api_devkit.bom.client_unix.$ARCH
  fi

  info "Updating ars devkit (client_unix) area -> '$BUILD_BASE/src/unix/ars/server/clients_unix/${ARS_BUILD_ID}/$ARCH'"
  perl $BUILD_BASE/src/unix/ars/server/common/devkit/mkapi.pl -d ${ARS_BUILD_ID} -c $version -a $ARCH -b $BUILD_BASE/src/unix/ars/server/common/devkit/api_devkit.bom.client_unix.$ARCH -S $BUILD_BASE/src/unix/ars -D $BUILD_BASE/src/unix/ars/server/clients_unix > $LOGDIR/$sys.$host.client_unix_devkit.log 2>&1

  [ ! -d $BUILD_BASE/src/unix/ars/server/clients_unix/apidrop ] && mkdir -p $BUILD_BASE/src/unix/ars/server/clients_unix/apidrop
  mv $BUILD_BASE/src/unix/ars/server/clients_unix/${ARS_BUILD_ID}/$ARCH $BUILD_BASE/src/unix/ars/server/clients_unix/apidrop

  cd $BUILD_BASE/src/unix/ars/server/clients_unix 

  ## for incremental builds.
  if [ $cfg_build_type = "incremental" ]; then
    if [ $cfg_unix_build_clean = "true" ]; then

      if [ $bit_type -eq 64 ]; then
        $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$CLEAN_LOGFILE_NAME SUBSET_PROD=util clean
      else
        $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$CLEAN_LOGFILE_NAME clean
      fi
    fi
  fi

  if [ $bit_type -eq 64 ]; then
    $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$LOGFILE_NAME SUBSET_PROD=util clients
  else
    $GMAKE -f Makefile.unix LOGFILE=$LOGDIR/$LOGFILE_NAME clients
  fi

  if [ $? -eq 0 ]; then
    touch $LOGDIR/$LOG_STATUS_PASS_FILE
  else
    touch $LOGDIR/$LOG_STATUS_FAIL_FILE
  fi
}

build_ars_approval () {

  if [ $ARS_BUILD_TYPE = "Release" ]; then
    NONDEBUG=1;
    LOGFILE_NAME=$sys.$host.approval.log
    LOG_STATUS_PASS_FILE=approval.$sys.succeeded
    LOG_STATUS_FAIL_FILE=approval.$sys.failed
  elif [ $ARS_BUILD_TYPE = "Debug" ]; then
    NONDEBUG=; 
    LOGFILE_NAME=$sys.$host.approval.debug.log
    LOG_STATUS_PASS_FILE=approval.debug.$sys.succeeded
    LOG_STATUS_FAIL_FILE=approval.debug.$sys.failed
  fi
  export NONDEBUG LOGFILE_NAME LOG_STATUS_PASS_FILE LOG_STATUS_FAIL_FILE

  if [ $sys = "solaris" -o \
       $sys = "aix" -o \
       $sys = "linux" -o \
       $sys = "hpia32" ]; then

    AR_API_DIR=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}; export AR_API_DIR

    cnt=0
    while :
    do
      [ -f $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn ] && break

      cnt=`expr 1 + $cnt`
      if [ $cnt -gt 60 ]; then
        error "Have been waiting for more than an hour for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn'"
        break;
      fi
      sleep 120
      info "Waiting for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn'"
    done

	if [ $sys = "solaris" ]; then
	  echo "Create build.properties file for solaris"
	  cd $BUILD_BASE/src/unix/ars/Approval/common/java_components 
      echo "build.platform=$sys" > build.properties
	else 
	  sleep 60
      echo "Create blank property for other unix platforms"
      cd $BUILD_BASE/src/unix/ars/Approval/common/java_components 
      echo "build.platform=" > build.properties	   
	fi   
#######
    cd $BUILD_BASE/src/unix/ars/Approval/common 
    $GMAKE -f Makefile.unix AR_API_DIR=${DEVKITS_DIR}/$app/$version/${ARS_BUILD_ID} RIK_BASE_DIR=${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID} LOGFILE=$LOGDIR/$LOGFILE_NAME all

    if [ $? -eq 0 ]; then
      touch $LOGDIR/$LOG_STATUS_PASS_FILE
    else
      touch $LOGDIR/$LOG_STATUS_FAIL_FILE
    fi

  else
    warn "Platform '$sys' is not yet supported for Approval"
  fi

}

build_ars_assignment () {

  if [ $ARS_BUILD_TYPE = "Release" ]; then
    NONDEBUG=1;
    LOGFILE_NAME=$sys.$host.assignment.log
    LOG_STATUS_PASS_FILE=assignment.$sys.succeeded
    LOG_STATUS_FAIL_FILE=assignment.$sys.failed
  elif [ $ARS_BUILD_TYPE = "Debug" ]; then
    NONDEBUG=;
    LOGFILE_NAME=$sys.$host.assignment.debug.log
    LOG_STATUS_PASS_FILE=assignment.debug.$sys.succeeded
    LOG_STATUS_FAIL_FILE=assignment.debug.$sys.failed
  fi
  export NONDEBUG LOGFILE_NAME LOG_STATUS_PASS_FILE LOG_STATUS_FAIL_FILE

  if [ $sys = "solaris" -o \
       $sys = "aix" -o \
       $sys = "linux" -o \
       $sys = "hpia32" ]; then

    AR_API_DIR=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}; export AR_API_DIR

    cnt=0
    while :
    do
      [ -f $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn ] && break

      cnt=`expr 1 + $cnt`
      if [ $cnt -gt 60 ]; then
        error "Have been waiting for more than an hour for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn'"
        break;
      fi
      sleep 120
      info "Waiting for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn'"
    done

    cd $BUILD_BASE/src/unix/ars/AssignmentEngine/asn/assignmentengine
    $GMAKE -f Makefile.unix AR_API_DIR=${DEVKITS_DIR}/$app/$version/${ARS_BUILD_ID} RIK_BASE_DIR=${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID} LOGFILE=$LOGDIR/$LOGFILE_NAME all

    if [ $? -eq 0 ]; then
      touch $LOGDIR/$LOG_STATUS_PASS_FILE
    else
      touch $LOGDIR/$LOG_STATUS_FAIL_FILE
    fi
  else
    warn "Platform '$sys' is not yet supported for Assignment"
  fi

}


build_ars_install() {


    ##BASE_DIR=$BUILD_BASE/src/unix/ars/server; export BASE_DIR

    [ ! -d $RELEASEAREA ] && error "Can not access '$RELEASEAREA'"

    ##mkdir -p $BASE_DIR/../logs
    mkdir -p $BUILD_BASE/src/unix/ars/server/../logs

    ##cd $BASE_DIR
    cd $BUILD_BASE/src/unix/ars/server

    if [ "$bit_type" -eq "32" ]; then
      $GMAKE -f Makefile.unix RELEASE_AREA=$RELEASEAREA LOGFILE=$LOGDIR/$sys.$host.install.log install
    elif [ "$bit_type" =  "ia32" ]; then
      $GMAKE -f Makefile.unix RELEASE_AREA=$RELEASEAREA LOGFILE=$LOGDIR/$sys.$host.install.log install
    else
      $GMAKE -f Makefile.unix RELEASE_AREA=$RELEASEAREA LOGFILE=$LOGDIR/$sys.$host.install.log SUBSET_PROD=server_overlay install
    fi

    if [ $? -eq 0 ]; then
      touch $cfg_root/$buildid/$app/log/install.$sys.succeeded
    else
      touch $cfg_root/$buildid/$app/log/install.$sys.failed
    fi
#######
    ##touch $BASE_DIR/../logs/$sys.install.done
    touch $BUILD_BASE/src/unix/ars/server/../logs/$sys.install.done

}

build_approval_install() {

    [ ! -d $RELEASEAREA ] && error "Can not access '$RELEASEAREA'"

    if [ $sys = "solaris" -o \
         $sys = "aix" -o \
         $sys = "linux" -o \
         $sys = "hpia32" ]; then

      cd $BUILD_BASE/src/unix/ars/Approval/common 

      $GMAKE -f Makefile.unix AR_API_DIR=${DEVKITS_DIR}/$app/$version/${ARS_BUILD_ID} RIK_BASE_DIR=${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID} RELEASE_AREA=$RELEASEAREA LOGFILE=$LOGDIR/$sys.$host.approvalinstall.log install

      if [ $? -eq 0 ]; then
        touch $cfg_root/$buildid/$app/log/approvalinstall.$sys.succeeded
      else
        touch $cfg_root/$buildid/$app/log/approvalinstall.$sys.failed
      fi
    else
      error "Platform '$sys' is not yet supported for Approval install"
    fi
}

build_assignment_install() {

    [ ! -d $RELEASEAREA ] && error "Can not access '$RELEASEAREA'"

    if [ $sys = "solaris" -o \
         $sys = "aix" -o \
         $sys = "linux" -o \
         $sys = "hpia32" ]; then

      cd $BUILD_BASE/src/unix/ars/AssignmentEngine/asn/assignmentengine

      $GMAKE -f Makefile.unix AR_API_DIR=${DEVKITS_DIR}/$app/$version/${ARS_BUILD_ID} RIK_BASE_DIR=${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID} RELEASE_AREA=$RELEASEAREA LOGFILE=$LOGDIR/$sys.$host.assignmentinstall.log install

      if [ $? -eq 0 ]; then
        touch $cfg_root/$buildid/$app/log/assignmentinstall.$sys.succeeded
      else
        touch $cfg_root/$buildid/$app/log/assignmentinstall.$sys.failed
      fi
    else
      error "Platform '$sys' is not yet supported for Assignment install"
    fi
}

build_appsignal () {
#######
   ##Build Appsignal required for ASJ and DSOJ
#######
   echo "Started Appsignal build for $sys"
#######
  if [ $ARS_BUILD_TYPE = "Release" ]; then
    NONDEBUG=1;
    LOGFILE_NAME=$sys.$host.appsignal.log
    LOG_STATUS_PASS_FILE=appsignal.$sys.succeeded
    LOG_STATUS_FAIL_FILE=appsignal.$sys.failed
  elif [ $ARS_BUILD_TYPE = "Debug" ]; then
    NONDEBUG=; 
    LOGFILE_NAME=$sys.$host.appsignal.debug.log
    LOG_STATUS_PASS_FILE=appsignal.debug.$sys.succeeded
    LOG_STATUS_FAIL_FILE=appsignal.debug.$sys.failed
  fi
  export NONDEBUG LOGFILE_NAME LOG_STATUS_PASS_FILE LOG_STATUS_FAIL_FILE

  if [ $sys = "solaris" -o \
	   $sys = "solsp64" -o \
       $sys = "aix" -o \
	   $sys = "aixp64" -o \
       $sys = "linux" -o \
	   $sys = "lx64" -o \
       $sys = "hpia32" -o \
	   $sys = "hpia64" ]; then

    AR_API_DIR=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}; export AR_API_DIR

	cnt=0
    while :
    do
      [ -f $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/linux/src/Makefile.cmn ] && break

      cnt=`expr 1 + $cnt`
      if [ $cnt -gt 60 ]; then
        error "Have been waiting for more than an hour for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/linux/src/Makefile.cmn'"
        break;
      fi
      sleep 120
      info "Waiting for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/linux/src/Makefile.cmn'"
    done
#######
    cd $BUILD_BASE/src/unix/ars/Common_peripherals/native/appsignal 
    $GMAKE -f Makefile.unix AR_API_DIR=${DEVKITS_DIR}/$app/$version/${ARS_BUILD_ID} RIK_BASE_DIR=${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID} LOGFILE=$LOGDIR/$LOGFILE_NAME all

    if [ $? -eq 0 ]; then
      touch $LOGDIR/$LOG_STATUS_PASS_FILE
    else
      touch $LOGDIR/$LOG_STATUS_FAIL_FILE
    fi

  else
    warn "Platform '$sys' is not yet supported for Appsignal"
  fi
#######
  echo "End Appsignal build for $sys"
}  

build_sigmask () {
#######
   ##Build sigmask required for ASJ and DSOJ
#######
   echo "Started Appsignal build for $sys"
#######
  if [ $ARS_BUILD_TYPE = "Release" ]; then
    NONDEBUG=1;
    LOGFILE_NAME=$sys.$host.sigmask.log
    LOG_STATUS_PASS_FILE=sigmask.$sys.succeeded
    LOG_STATUS_FAIL_FILE=sigmask.$sys.failed
  elif [ $ARS_BUILD_TYPE = "Debug" ]; then
    NONDEBUG=; 
    LOGFILE_NAME=$sys.$host.sigmask.debug.log
    LOG_STATUS_PASS_FILE=sigmask.debug.$sys.succeeded
    LOG_STATUS_FAIL_FILE=sigmask.debug.$sys.failed
  fi
  export NONDEBUG LOGFILE_NAME LOG_STATUS_PASS_FILE LOG_STATUS_FAIL_FILE

  if [ $sys = "solaris" -o \
	   $sys = "solsp64" ]; then

    AR_API_DIR=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}; export AR_API_DIR

	cnt=0
    while :
    do
      [ -f $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn ] && break

      cnt=`expr 1 + $cnt`
      if [ $cnt -gt 60 ]; then
        error "Have been waiting for more than an hour for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn'"
        break;
      fi
      sleep 120
      info "Waiting for '$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/solaris/src/Makefile.cmn'"
    done
#######
    cd $BUILD_BASE/src/unix/ars/Common_peripherals/native/sigmask 
    $GMAKE -f Makefile.unix AR_API_DIR=${DEVKITS_DIR}/$app/$version/${ARS_BUILD_ID} RIK_BASE_DIR=${DEVKITS_DIR}/rik/$version/${ARS_BUILD_ID} LOGFILE=$LOGDIR/$LOGFILE_NAME all

    if [ $? -eq 0 ]; then
      touch $LOGDIR/$LOG_STATUS_PASS_FILE
    else
      touch $LOGDIR/$LOG_STATUS_FAIL_FILE
    fi

  else
    warn "Platform '$sys' is not yet supported for sigmask"
  fi
#######
  echo "End sigmask build for $sys"
}  

build_status() {

## Mark build is completed. Create a file "$sys.build.all.DONE". This file will be used by stage.sh to start staging.  

touch $LOGDIR/$sys.build.all.DONE

}

build_ars_healthadvisor() {

  sys=solaris; export sys
  comp=healthadvisor; export comp
  eval "host=\$${sys}HOST_${comp}"

  info "Build Step: build_healthadvisor"

  build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
  
  ## If there is requirement to distinguish repositories for same component but on different branches then we will introduce the new path. (which is commented out in ars_unix_build.sh) , where, $version stands for branch. 
  ##maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository
  
  maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository
  
  [ -f $build_logfile ] && mv $build_logfile $build_logfile.$$

  ## build.
  cd  $BUILD_BASE/src/unix/ars/healthadvisor/repository
  ./repoinstall.sh > $build_logfile 2>&1

  cd  $BUILD_BASE/src/unix/ars/healthadvisor/projects
  mvn clean install -Dmaven.repo.local=$maven_local_repository >> $build_logfile 2>&1
  
  cd  $BUILD_BASE/src/unix/ars/healthadvisor/projects/clientinstaller/installer
  ./create-installer.sh >> $build_logfile 2>&1
  
  cd  $BUILD_BASE/src/unix/ars/healthadvisor/projects/server/installer
  ./create-installer.sh >> $build_logfile 2>&1

  cd  $BUILD_BASE/src/unix/ars/healthadvisor/projects/clientinstallconfig/installer
  ./create-installer.sh >> $build_logfile 2>&1

}

build_ars_boulder() {

  sys=linux; export sys
  comp=boulder; export comp
  eval "host=\$${sys}HOST_${comp}"
  
  ##maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository  
	LANG=en_US.UTF-8; export LANG
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && rm -f $build_logfile	
    [ -f $BUILD_BASE/log/$comp.serverj.succeeded ] && rm $BUILD_BASE/log/$comp.serverj.succeeded
	[ -f $BUILD_BASE/log/$comp.serverj.failed ] && rm $BUILD_BASE/log/$comp.serverj.failed

   [ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj; 
 
  ## Boulder has dependency over //ars/main/server/java_components build. Make sure server/linux.api.java.DONE is available before starting boulder build. 
  ## Java_component build get complete in first 30 minutes. Waiting time is set to 1 hour. 
    
  cnt=0
  while :
  do
    [ -f $BUILD_BASE/log/linux.serverj_components.DONE ] && break

    cnt=`expr 1 + $cnt`
    if [ $cnt -gt 90 ]; then
     error "Have been waiting for more than an hour for '$BUILD_BASE/log/linux.serverj_components.DONE'"
    break;
    fi
    sleep 60
    info "Waiting for '$BUILD_BASE/log/linux.serverj_components.DONE' for $cnt minutes..." 
	done
  
  cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/repository
  sh -x repoinstall.sh >> $build_logfile 2>&1
  
  cd  $BUILD_BASE/src/unix/ars/server/activiti/distro
  echo " Change project.properties to devkits.dir=$DEVKITS_DIR/$app/$version/current/winnt/lib/"
  sed -i s%devkits.dir=.*%devkits.dir=$DEVKITS_DIR/$app/$version/current/winnt/lib%g project.properties
  sed -i s%tparty.dir=.*%tparty.dir=$DEVKITS_DIR/lib/thirdparty%g project.properties
  #sed -i s%maven_local_repository.dir=.*%maven_local_repository.dir=$DEVKITS_DIR/localmavenrepo/ars/.m2_boulder%g project.properties
  
  cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects

  if [ $cfg_site = "aus" ]; then
    echo "************ Maven clean ***********************" >>  $build_logfile
    mvn clean -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1
   
    echo "************ Maven deploy ***********************" >>  $build_logfile
    mvn install -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1
 else
    echo "************ Maven clean ***********************" >>  $build_logfile
    mvn clean -DskipTests -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1

    echo "************ Maven deploy ***********************" >>  $build_logfile
    mvn install -DskipTests -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1  
fi   

  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\]|BUILD ERROR)" $build_logfile | egrep -v "(\[ERROR\] Error.*Ignored it\.)"
  
  if [ $? = 0 ]; then
    build_status="FAIL"
    touch $BUILD_BASE/log/$comp.serverj.failed
  else
    build_status="PASS"
    touch $BUILD_BASE/log/$comp.serverj.succeeded
  fi
  
  touch $BUILD_BASE/log/$comp.serverj.DONE
  export build_status
  
  echo "Deploy serverj artifacts to nexus repository"
  build_ars_boulder_deploy_artifacts
  
}

build_ars_boulder_deploy_artifacts() {

  sys=linux; export sys
  comp=boulder_deploy_artifacts; export comp
  eval "host=\$${sys}HOST_${comp}"
  
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_boulder; export maven_local_repository  
	LANG=en_US.UTF-8; export LANG

	if [ -f $BUILD_BASE/log/boulder.serverj.succeeded ] ; then
		cd $BUILD_BASE/src/unix/ars/ar_admin; 
		api_version16=`grep "api_version16" build.version.properties | cut -d"=" -f2 | tr -d '[[:space:]]'`; export api_version16
		
		echo "Below are required parameters for uploading artifacts to remote repository"
		echo "JAVA_HOME=$JAVA_HOME"
		echo "M2_HOME=$M2_HOME"
		echo "api_version16=$api_version16"
		
		cd $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/repository;
		dos2unix Deploy_Snapshot_Artifacts_jars_Unix.sh
		echo "#======================================================" >> $BUILD_BASE/log/$sys.$host.${comp}.log
		sh -x Deploy_Snapshot_Artifacts_jars_Unix.sh >> $BUILD_BASE/log/$sys.$host.${comp}.log 2>&1
		
		egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\]|BUILD ERROR|FAILED)" $BUILD_BASE/log/$sys.$host.${comp}.log 
  
		if [ $? = 0 ]; then
			touch $BUILD_BASE/log/$comp.failed
		else
			touch $BUILD_BASE/log/$comp.succeeded
		fi
	else
		echo "ServerJ (boulder) build has been failed hence deploy is skipped"
	fi 
		
	
	
}
build_ars_boulder_deploy() {

  sys=linux; export sys
  comp=boulder_deploy; export comp
  eval "host=\$${sys}HOST_${comp}"
  
  ##maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository  
	LANG=en_US.UTF-8; export LANG
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && rm -f $build_logfile	
    [ -f $BUILD_BASE/log/$comp.serverj.succeeded ] && rm $BUILD_BASE/log/$comp.serverj.succeeded
	[ -f $BUILD_BASE/log/$comp.serverj.failed] && rm $BUILD_BASE/log/$comp.serverj.failed

   #[ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj; 
 
  ## Boulder has dependency over //ars/main/server/java_components build. Make sure server/linux.api.java.DONE is available before starting boulder build. 
  ## Java_component build get complete in first 30 minutes. Waiting time is set to 1 hour. 
    
  cnt=0
  while :
  do
    [ -f $BUILD_BASE/log/linux.serverj_components_deploy.DONE ] && break

    cnt=`expr 1 + $cnt`
    if [ $cnt -gt 90 ]; then
     error "Have been waiting for more than an hour for '$BUILD_BASE/log/linux.serverj_components_deploy.DONE'"
    break;
    fi
    sleep 60
    info "Waiting for '$BUILD_BASE/log/linux.serverj_components_deploy.DONE' for $cnt minutes..." 
	done
  
#  cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/repository
#  sh -x repoinstall.sh >> $build_logfile 2>&1
  
  cd  $BUILD_BASE/src/unix/ars/server/activiti/distro
  echo " Change project.properties to devkits.dir=$DEVKITS_DIR/$app/$version/current/winnt/lib/"
  sed -i s%devkits.dir=.*%devkits.dir=$DEVKITS_DIR/$app/$version/current/winnt/lib%g project.properties
  sed -i s%tparty.dir=.*%tparty.dir=$DEVKITS_DIR/lib/thirdparty%g project.properties
  #sed -i s%maven_local_repository.dir=.*%maven_local_repository.dir=$DEVKITS_DIR/localmavenrepo/ars/.m2_boulder%g project.properties
  
  cd  $BUILD_BASE/src/unix/ars/server/common/serverj_deploy/arsystem/projects

  if [ $cfg_site = "aus" ]; then
    echo "************ Maven clean ***********************" >>  $build_logfile
    mvn clean -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1
   
    echo "************ Maven deploy ***********************" >>  $build_logfile
    mvn deploy -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1
 else
    echo "************ Maven clean ***********************" >>  $build_logfile
    mvn clean -DskipTests -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1

    echo "************ Maven deploy ***********************" >>  $build_logfile
    mvn deploy -DskipTests -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dnpm.root.module.dir=$NVM_PATH >> $build_logfile 2>&1  
fi   

  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\]|BUILD ERROR)" $build_logfile | egrep -v "(\[ERROR\] Error.*Ignored it\.)"
  
  if [ $? = 0 ]; then
    build_status="FAIL"
    touch $BUILD_BASE/log/$comp.serverj.failed
  else
    build_status="PASS"
    touch $BUILD_BASE/log/$comp.serverj.succeeded
  fi
  
  touch $BUILD_BASE/log/$comp.serverj.DONE
  export build_status
}

build_ars_boulder_clover() {

  info "Build Boulder with Clover Instrument"
  ENABLE_CLOVER=yes; export ENABLE_CLOVER
   
  sys=linux; export sys
  comp=boulder_clover; export comp
  eval "host=\$${sys}HOST_${comp}"
  
   ##maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository
   maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository   
   serverj_local_maven_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_boulder; export serverj_local_maven_repository
  
   build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
   [ -f $build_logfile ] && rm -f $build_logfile
   [ -f $BUILD_BASE/log/boulder.server.clover.succeeded ] && rm $BUILD_BASE/log/boulder.server.clover.succeeded
   
   ## Serverj build has dependencies over serverj_components
   ## Copy required dependencies from serverj local maven repo to clover local maven repo. 
   
   cp -rp $serverj_local_maven_repository/com/bmc/arsys/* $maven_local_repository/com/bmc/arsys/* >> $build_logfile 2>&1
   cp -rp $serverj_local_maven_repository/com/kaazing $maven_local_repository/com/ >> $build_logfile 2>&1
   cp -rp $serverj_local_maven_repository/com/retrologic $maven_local_repository/com/ >> $build_logfile 2>&1
   cp -rp $serverj_local_maven_repository/com/rsa $maven_local_repository/com/ >> $build_logfile 2>&1   
   
   [ ! -d $maven_local_repository/com/bmc/arsys ] && mkdir -p $maven_local_repository/com/bmc/arsys >> $build_logfile 2>&1
   cp -rfp $serverj_local_maven_repository/com/bmc/arsys/nonserver $maven_local_repository/com/bmc/arsys/ >> $build_logfile 2>&1
   cp -rfp $serverj_local_maven_repository/com/bmc/arsys/api $maven_local_repository/com/bmc/arsys/ >> $build_logfile 2>&1

   [ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj_clover ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj_clover; 
   
  ## Boulder has dependency over //ars/main/server/java_components build. Make sure server/linux.api.java.DONE is available before starting boulder build. 
  ## Java_component build get complete in first 30 minutes. Waiting time is set to 1 hour. 
    
  cnt=0
  while :
  do
    [ -f $BUILD_BASE/log/linux.serverj_components.DONE ] && break

    cnt=`expr 1 + $cnt`
    if [ $cnt -gt 90 ]; then
     error "Have been waiting for more than an hour for '$BUILD_BASE/log/linux.serverj_components.DONE'"
    break;
    fi
    sleep 60
    info "Waiting for '$BUILD_BASE/log/linux.serverj_components.DONE' for $cnt minutes..." 
	done
  
    cd  $BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/repository
    sh -x repoinstall.sh >> $build_logfile 2>&1

    cd  $BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects
    mvn clean install -Dclover -Dclover.dbLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/target/clover.db -Dclover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj_clover >> $build_logfile 2>&1
  
  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\]|BUILD ERROR)" $build_logfile
  
  if [ $? = 0 ]; then
    build_status="FAIL"
    touch $BUILD_BASE/log/$comp.server.failed	
  else
    build_status="PASS"
      touch $BUILD_BASE/log/$comp.server.succeeded
  fi

  touch $BUILD_BASE/log/$comp.server.DONE
  export build_status
  
}

build_ars_boulder_kw() {

  sys=linux; export sys
  comp=boulder_kw; export comp
  eval "host=\$${sys}HOST_${comp}"
  
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository  
    serverj_local_maven_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_boulder; export serverj_local_maven_repository
	build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    
	[ -f $build_logfile ] && rm -f $build_logfile	
    [ -f $BUILD_BASE/log/boulder.serverj.succeeded ] && rm $BUILD_BASE/log/boulder.serverj.succeeded
	
    cp -rp $serverj_local_maven_repository/com/bmc/arsys/* $maven_local_repository/com/bmc/arsys/* >> $build_logfile 2>&1
    cp -rp $serverj_local_maven_repository/com/kaazing $maven_local_repository/com/ >> $build_logfile 2>&1
    cp -rp $serverj_local_maven_repository/com/retrologic $maven_local_repository/com/ >> $build_logfile 2>&1
    cp -rp $serverj_local_maven_repository/com/rsa $maven_local_repository/com/ >> $build_logfile 2>&1   
   
    [ ! -d $maven_local_repository/com/bmc/arsys ] && mkdir -p $maven_local_repository/com/bmc/arsys >> $build_logfile 2>&1
    cp -rfp $serverj_local_maven_repository/com/bmc/arsys/nonserver $maven_local_repository/com/bmc/arsys/ >> $build_logfile 2>&1
    cp -rfp $serverj_local_maven_repository/com/bmc/arsys/api $maven_local_repository/com/bmc/arsys/ >> $build_logfile 2>&1

	
	#KWDIR=$LOGDIR/klocwork; export KWDIR
	#KWDIR=$cfg_root/klocwork; export KWDIR
	KWDIR=$cfg_root/klocwork1041/; export KWDIR

	
	#[ -d $LOGDIR/$KWDIR ] && mv $LOGDIR/$KWDIR $LOGDIR/$KWDIR_$$
	#mkdir -p $KWDIR/Tables; 	
	[ -d $KWDIR/kwreport ] && mv $KWDIR/kwreport $KWDIR/kwreport_$$
	mkdir -p $KWDIR/kwreport;
	[ -f $KWDIR/kwinject.out ] && mv $KWDIR/kwinject.out $KWDIR/kwinject.out_$$
    
   [ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj; 
 
    cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/repository
    sh -x repoinstall.sh >> $build_logfile 2>&1
  
    export JAVA_TOOL_OPTIONS=-Dfile.encoding=cp1252
  
    cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects
  
    echo "************ Maven clean ***********************" >>  $build_logfile
    mvn clean -DskipTests -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj -Dnpm.root.module.dir=$NVM_PATH  -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1
    
	echo "************ Maven install ***********************" >>  $build_logfile
    mvn  install -DskipTests -Dskip-installer -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj -Dnpm.root.module.dir=$NVM_PATH  -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1  
	
	cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects/localapi/
	mvn clean install -DskipTests -Dversion.drop-or-patch=$buildid -Dmaven.repo.local=$maven_local_repository -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj -Dnpm.root.module.dir=$NVM_PATH  -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1  
	
	cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/projects/gensowfile
	mvn clean install -Dmaven.repo.local=$maven_local_repository >> $build_logfile 2>&1  

	cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/projects/genkwreport
	mvn clean install -Dmaven.repo.local=$maven_local_repository >> $build_logfile 2>&1  
	
  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\] BUILD ERROR)" $build_logfile
  
  if [ $? = 0 ]; then
    build_status="FAIL"
    touch $BUILD_BASE/log/$comp.server.failed
	MailSubject="Serverj Klocwork build failed. Please check build $buildid for the same. Log file -> $build_logfile"; export MailSubject
	perl $DEVKITS_DIR/tools/build/bin/sendEmail.pl -u "$MailSubject" -f $cfg_notify_from  -t _12fbc4@BMC.com -cc _23b031@bmc.com
	exit 1; 
  else
    build_status="PASS"
    touch $BUILD_BASE/log/$comp.server.succeeded
  fi
  
  touch $BUILD_BASE/log/$comp.server.DONE	
	
	
	## Export Perforce variables
	P4PORT=$cfg_p4svr; export P4PORT
	P4USER=$cfg_p4usr; export P4USER
    P4CLIENT=$cfg_p4client_ux; export P4CLIENT
	#//pun-rem-fs02/devkits/tools/perforce/linux/p4 sync -f //ars/main/server/common/serverj/... > ${LOGDIR}/serverj.kw.p4getsrc.log 2>&1
	
	
	#cd /pun-rem-fs02/build_ars/rbuild/klocwork/main; 
	cd $BUILD_BASE/src/unix/ars/server/common/serverj;
	find . -name "*.java" > $KWDIR/boulder.sow
	mv $KWDIR/boulder.sow $KWDIR/boulder.sow_orig
	
	## Splitting boulder.sow_orig file into multiple parts of 1000 lines each. 
	## sow file has more than 4000 entries of java files, running p4 changes command against each takes very long time. 
	## sow file will be splitted in files naming, "xa, xb, xc ...". p4 command will be run against each file in parallel. 
	## Final report will be available in a single file "boulder.sow"
	## sow file format, <username>;<localfilepath>
	
	cd $KWDIR
	split -l 1000 -a 1 boulder.sow_orig
	
	generate_sow_files(){
        for line in `cat $KWDIR/$splitfile`
        do
				## Convert path to perforce format //ars/main/<file path>
                p4line=`echo $line| sed -e "s$^\.$\/\/ars\/main\/server\/common\/serverj$"`
                echo $p4line
				## Extract user name, last change made by the user for file.
                user=`//pun-rem-fs02/devkits/tools/perforce/linux/p4 changes -m 1 $p4line | awk -F "@" '{print $1}'  | awk -F " " '{print $6}' `
                ## Create local file path, //pun-rem-fs02/build_ars/rbuild/klocwork/main/<file path> 
				newline=`echo $line| sed -e "s$^\.$\/\/pun-rem-fs02\/build_ars\/rbuild\/ars\/main\/$buildid\/ars\/src\/unix\/ars\/server\/common\/serverj$"`
                echo $newline
				## Enter <username>;<localfilepath> entry to sow file
                echo "$user;$newline" >> $KWDIR/boulder.sow
        done
	}

		files=`ls x*`; export files
		echo $files

		for splitfile in $files
		do
		  echo $splitfile
		  export spiltfile
		  generate_sow_files > $KWDIR/kw-generate-sow-file-${splitfile}.log 2>&1 &
		done

		## Wait till all background processes are complete. 
		wait
	
	echo "Generate KW reports --  import-config Phase 1" > $KWDIR/kwreport.log 2>&1
	kwadmin --url $KW_SERVER_URL import-config ARS_MAIN_SERVERJ $KWDIR/boulder.sow  >> $KWDIR/kwreport.log 2>&1

	echo "Generate KW reports --  import-config Phase 2" >> $KWDIR/kwreport.log 2>&1
	kwadmin --url $KW_SERVER_URL import-config ARS_MAIN_SERVERJ $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/klocwork/java_default.pconf  >> $KWDIR/kwreport.log 2>&1
	
	echo "Generate KW reports --  import-config Phase 3" >> $KWDIR/kwreport.log 2>&1
	kwadmin --url $KW_SERVER_URL import-config ARS_MAIN_SERVERJ $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/klocwork/problems_default.pconf >> $KWDIR/kwreport.log 2>&1

	echo "Generate KW reports --  kwbuildproject" >> $KWDIR/kwreport.log 2>&1
	kwbuildproject --incremental --url $KW_SERVER_URL/ARS_MAIN_SERVERJ -v -e $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/klocwork/problems_default.pconf  $KWDIR/kwinject.out -o $KWDIR/Tables/ARS_MAIN_SERVERJ >> $KWDIR/kwreport.log 2>&1

	echo "Generate KW reports --  Load reports to server " >> $KWDIR/kwreport.log 2>&1
	kwadmin --url $KW_SERVER_URL load ARS_MAIN_SERVERJ $KWDIR/Tables/ARS_MAIN_SERVERJ >> $KWDIR/kwreport.log 2>&1

	echo "Generate KW reports --  generate html report" >> $KWDIR/kwreport.log 2>&1
	cd $ARS_API_SERVER_UNIX_SRC_DIR/common/serverj/arsystem/projects/dev-utilities/projects/genkwreport/target
	java -jar genkwreport-1.0-jar-with-dependencies.jar -url $KW_SERVER_URL -user buildadm -p ARS_MAIN_SERVERJ -o "$KWDIR/kwreport/kwemailBody.htm" -l 2  >> $KWDIR/kwreport.log 2>&1

	egrep "Error occurred during build" $KWDIR/kwreport.log
      
    if [ $? = 0 ]; then
		MailSubject="Serverj Klocwork Gibraltar(Main) build analysis failed. Please check build $buildid log file -> $KWDIR/kwreport.log"; export MailSubject
		perl $DEVKITS_DIR/tools/build/bin/sendEmail.pl -u "$MailSubject" -f $cfg_notify_from  -t _12fbc4@BMC.com -cc _23b031@bmc.com
		exit 1; 
    else
		MailSubject="Klocwork Build Summary (ARS_MAIN_SERVERJ) -- Severity level 2"; export MailSubject
		cd $KWDIR/kwreport/
		grep ">0 Open Issues<" kwemailBody.htm
		cat kwemailBody.htm | perl $DEVKITS_DIR/tools/build/bin/sendEmail.pl -u "$MailSubject" -f $cfg_notify_from  -t _12fbc4@BMC.com -cc  _23b031@bmc.com
    fi
	
  export build_status
}

build_ars_oengine() {

  sys=linux; export sys
  comp=oengine; export comp
  eval "host=\$${sys}HOST_${comp}"
  
  ##maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository
    export JAVA_HOME=${DEVKITS_DIR}/tools/build_software/jdk/jdk1.7.0_45/linux64/
    export M2_HOME=${DEVKITS_DIR}/tools/build_software/maven/3.2.1/
    export PATH=$M2_HOME/bin:$JAVA_HOME/bin:$PATH

    echo `which java`;
    java -version 
    
    echo `which mvn`
    mvn -v 

    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_boulder; export maven_local_repository  
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && rm -f $build_logfile	
   
   cd  $BUILD_BASE/src/unix/ars/orchestrationengine/repository
   sh -x repoinstall.sh >> $build_logfile 2>&1

  cd  $BUILD_BASE/src/unix/ars/orchestrationengine/activiti/distro/
  echo " Change project.properties to devkits.dir=$DEVKITS_DIR/$app/$version/$ARS_BUILD_ID/winnt/lib/"
  sed -i s%devkits.dir=.*%devkits.dir=$DEVKITS_DIR/$app/$version/current/winnt/lib%g project.properties
  sed -i s%maven_local_repository.dir=.*%maven_local_repository.dir=$DEVKITS_DIR/localmavenrepo/ars/.m2_boulder%g project.properties
  sed -i s%tparty.dir=.*%tparty.dir=$DEVKITS_DIR/lib/thirdparty%g project.properties

  echo " Use pun-rem-fs02 for Pune site and build for San Jose site"
  if [ $cfg_site = "aus" ]; then
     sed -i s%pun-rem-fs02%build%g build.xml
  fi
  
  cd  $BUILD_BASE/src/unix/ars/orchestrationengine/
  echo "************ Maven clean install ***********************" >>  $build_logfile
  mvn clean install -U -DskipTests=true -Dmaven.repo.local=$maven_local_repository >> $build_logfile 2>&1

  
  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\] BUILD ERROR)" $build_logfile
  
  if [ $? = 0 ]; then
    build_status="FAIL"
    touch $BUILD_BASE/log/ars.$comp.failed
  else
    build_status="PASS"
    touch $BUILD_BASE/log/ars.$comp.succeeded
  fi
  
  touch $BUILD_BASE/log/ars.$comp.DONE
  
}

build_ars_inappreporting() {

  sys=linux; export sys
  comp=inappreporting; export comp
  eval "host=\$${sys}HOST_${comp}"

    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository  
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && rm -f $build_logfile	
   
   cd $BUILD_BASE/src/unix/ars/inappreporting/src/main/config;
   cp inAppReporting.properties inAppReporting.properties.orig
   cat inAppReporting.properties.orig | sed -e "s/build.version=.*/build.version=$ARS_BUILD_ID/" > inAppReporting.properties
   
   
   cd  $BUILD_BASE/src/unix/ars/inappreporting ; 
   sh -x repoinstall.sh >> $build_logfile 2>&1

   cd  $BUILD_BASE/src/unix/ars/inappreporting/parent;
  echo "************ Maven clean install ***********************" >>  $build_logfile
  mvn clean install -Dmaven.repo.local=$maven_local_repository >> $build_logfile 2>&1
  
  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\] BUILD ERROR)" $build_logfile
  
  if [ $? = 0 ]; then
    build_status="FAIL"
    touch $BUILD_BASE/log/ars.$comp.failed
  else
    build_status="PASS"
    touch $BUILD_BASE/log/ars.$comp.succeeded
  fi
  
  touch $BUILD_BASE/log/ars.$comp.DONE
  
}

build_ars_midtier() {

  info "Start - Building MT Server"

  cd ${ARS_MIDTIER_SRC_DIR}/client/arsysFlex
  if [ $cfg_site = "pun" ]; then
      cat build.properties.default | sed -e 's#smbufs1#pun-rem-fs02#g' > build.properties
  else
      cat build.properties.default > build.properties
  fi

  cd ${ARS_MIDTIER_SRC_DIR} 

  [ -f buildnumber ] && chmod 777 buildnumber
  perl $BUILD_BASE/src/win32/ars/ar_admin/build.pl -b ${VER_BUILD_TYPE} -v ${VER_PATCH} -s ${ARS_BUILD_ID} -m midtier

  FLEX_SERVER=${DEVKITS_DIR}/tools/build_software/flexHome; export FLEX_SERVER
  FLEX_SDK_HOME=$FLEX_SERVER/flex_sdk_3; export FLEX_SDK_HOME

  echo "version=$VER_API" > ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "client.version=$VER_MAJOR.$VER_MINOR" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "tparty.lib.dir=$THIRDPARTY_DIR" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
#  echo "arbo.install.dir=C:/Program Files/AR System/ARWebReportViewer" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
#  echo "tomcat.dir=C:/Program Files/Apache Software Foundation/Tomcat 5.0" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "ARSystemAPI=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/winnt/lib" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "ARSystemAPI70=$DEVKITS70_DIR/winnt/lib"  >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "tparty.src.dir=$THIRDPARTY_DIR" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "FLEX_SERVER=$FLEX_SERVER" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "FLEX_SDK_HOME=$FLEX_SDK_HOME" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "buildtype=${ARS_BUILD_TYPE}" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  echo "atrium.sso.webagent.src=$DEVKITS_DIR/atrium_dev/atrium-sso/8.0.01/webagent.zip" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  
  if [ $BUILD_MIDTIER_CLOVER = "YES" ]; then
    echo "midtier.install.dir=${ARS_MIDTIER_SRC_DIR}/install_clover" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
    echo "clover.data.dir=$cfg_rbuild_root/CloverData/$version/$ARS_BUILD_ID" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  else
    echo "midtier.install.dir=${ARS_MIDTIER_SRC_DIR}/install" >> ${ARS_MIDTIER_SRC_DIR}/build.properties
  fi

  if [ $BUILD_MIDTIER_CLOVER = "YES" ]; then
    $ANT_HOME/bin/ant -DJAVA_HOME=$JAVA_HOME -f ${ARS_MIDTIER_SRC_DIR}/build.xml dist.clover 
    mkdir -p $RELEASEAREA/midtier
    cp -rp $ARS_MIDTIER_SRC_DIR/install_clover $RELEASEAREA/midtier
  else
    $ANT_HOME/bin/ant -DJAVA_HOME=$JAVA_HOME -f ${ARS_MIDTIER_SRC_DIR}/bobuild.xml dist 
    $ANT_HOME/bin/ant -DJAVA_HOME=$JAVA_HOME -f ${ARS_MIDTIER_SRC_DIR}/build.xml dist 
    $ANT_HOME/bin/ant -DJAVA_HOME=$JAVA_HOME -f ${ARS_MIDTIER_SRC_DIR}/build.xml war 
    $ANT_HOME/bin/ant -DJAVA_HOME=$JAVA_HOME -f ${ARS_MIDTIER_SRC_DIR}/build.xml combinedWar

    for f in arapi71.dll arrpc71.dll arutl71.dll rcmn71.dll icudtbmc32.dll arjni71.dll
    do
      cp -v $DEVKITS71_DIR/winnt/lib/$f $ARS_MIDTIER_SRC_DIR/install/WEB-INF/lib
    done

    for f in arapi75.dll arrpc75.dll arutl75.dll arjni75.dll
    do
      cp -v $DEVKITS75_DIR/winnt/lib/$f $ARS_MIDTIER_SRC_DIR/install/WEB-INF/lib
    done

    for f in msvcp71.dll msvcr71.dll mfc71.dll
    do
      cp -v $MIDTIER71_RBUILD_DIR/java/lib/$f $ARS_MIDTIER_SRC_DIR/install/WEB-INF/lib
    done


    ## TODO
    ## Not sure why midtier build is not able to copy the Visualizer to install
    ## directory.
    if [ -d $ARS_MIDTIER_SRC_DIR/built/Visualizer ]; then
      cp -rp $ARS_MIDTIER_SRC_DIR/built/Visualizer  $ARS_MIDTIER_SRC_DIR/install
    else
      echo "[ERROR] Can not access $ARS_MIDTIER_SRC_DIR/built/Visualizer"
    fi

    mkdir -p $cfg_root/$ARS_BUILD_ID/ars/src/unix/ars/midtier
 #   /usr/bin/cp -rpv `cygpath $ARS_MIDTIER_SRC_DIR/install/*` $cfg_root/$ARS_BUILD_ID/ars/src/unix/ars/midtier > $LOGDIR/$sys.$host.midtier_unix_copy.log

    mkdir -p $RELEASEAREA/midtier/install_unix
    mkdir -p $RELEASEAREA/midtier/install_unix/stage
    mkdir -p $RELEASEAREA/midtier/install_unix/stage_lib
    mkdir -p $RELEASEAREA/midtier/install_unix/war
    mkdir -p $RELEASEAREA/midtier/install_unix/war_stage

  #  /usr/bin/cp -rpv `cygpath $ARS_MIDTIER_SRC_DIR/install` $RELEASEAREA/midtier >> $LOGDIR/$sys.$host.midtier_unix_copy.log

    cp -rp $ARS_MIDTIER_SRC_DIR/install/* $RELEASEAREA/midtier/install_unix/stage >> $LOGDIR/$sys.$host.midtier_unix_copy.log
    rm -rf $RELEASEAREA/midtier/install_unix/stage/WEB-INF/lib/*.dll 

    cp -rp $cfg_root/$ARS_BUILD_ID/ars/src/unix/ars/SMBU_Installers/Distribution/install_static/utils/CRPass.class $RELEASEAREA/midtier/install_unix/stage/WEB-INF/lib >> $LOGDIR/$sys.$host.midtier_unix_copy.log

  fi

  [ -d $ARS_MIDTIER_SRC_DIR/tparty ] && rm -rf $ARS_MIDTIER_SRC_DIR/tparty

  info "End - Building MT Server"
}

build_ars_ARMigrate () {

  info "Start - Building ARMigrate"

  cd ${ARS_ARMigrate_SRC_DIR} 

  echo "Create build.properties file"

  echo "tparty.src.dir=$THIRDPARTY_DIR" > build.properties
  echo "devkits.dir=$DEVKITS_DIR/ars/$version/$buildid/winnt" >> build.properties
  echo "devstudio.src.dir=../../../win32/ars/DeveloperStudio/publish/Utilities" >> build.properties

  $ANT_HOME/bin/ant 

  info "End - Building ARMigrate"
}

build_ars_serverj_components () {

  sys=linux; export sys
  comp=serverj_components; export comp
  eval "host=\$${sys}HOST_${comp}"
  ARCH=$sys; export ARCH
  
  ## Local Maven repo for both serverj_components and serverj should be same since serverj_components do validation and creates pom.xml to be used by both. 
  comp_localrepo=boulder; export comp_localrepo
  
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp_localrepo}; export maven_local_repository  
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && mv $build_logfile	${build_logfile}_$$
    [ -f $BUILD_BASE/log/$sys.${comp}.succeeded ] && rm $BUILD_BASE/log/$sys.${comp}.succeeded
	[ -f $BUILD_BASE/log/$sys.${comp}.DONE ] && rm $BUILD_BASE/log/$sys.${comp}.DONE

   [ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj; 
 
	RELEASE_DIR1=$RELEASEAREA/linux; export RELEASE_DIR1  ## hard coded to linux as of now, need to do for all unix platforms
	BASE_DIR=${BUILD_BASE}/src/unix/ars/server/common; export BASE_DIR

	echo "##### Serverj_Components build STARTED #####" > $build_logfile 2>&1

#	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects
#	mvn initialize  -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

    echo "##### Serverj_Components : validate #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/repository
	mvn -Dmaven.repo.local=$maven_local_repository -Dtparty.src.dir=${THIRDPARTY_DIR} -Datriumsso.version=current validate  >> $build_logfile 2>&1

	echo "##### Serverj_Components : serverj_components compilation #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components
	mvn clean install -Dcompiler=${CPLUSPLUS} -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1
	
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/api
	mvn javadoc:jar -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1
	
	echo "##### Serverj_Components : messagingclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/messagingclient
	mvn clean install -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

	echo "##### Serverj_Components : companionremote #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/companionremote
	mvn clean install -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1
	
	echo "##### Serverj_Components : companionclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/companionclient
	mvn clean install -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1

	echo "##### Serverj_Components : dev-utilities/projects/lucenemigrator  #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/projects/lucenemigrator
	mvn clean install -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1
		
	echo "##### Serverj_Components : devkits #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/devkits
	mvn clean install -Dmaven.repo.local=$maven_local_repository  -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj  >> $build_logfile 2>&1

	echo "##### Serverj_Components : pluginsvr #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/pluginsvr
	mvn clean install -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

	echo "##### Serverj_Components : plugins #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/plugins
	mvn clean install javadoc:jar -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1
	
	echo "##### Serverj_Components : UnsupportedUtils #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/unsupportedUtils
	mvn clean install -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1
	
	## Required java components files will be copied under release directory. It was earlier done by server_install target under each platform. 
	echo "##### Serverj_Components : severj-packager #####" >> $build_logfile 2>&1
    
	for platform in linux solaris
        do
            RELEASE_DIR1=$RELEASEAREA/$platform; export RELEASE_DIR1
            echo "Release directory = $RELEASE_DIR1 " >>$build_logfile 2>&1
	    [ ! -d ${RELEASE_DIR1}/fileset2/api ] && mkdir -p ${RELEASE_DIR1}/fileset2/api >> $build_logfile 2>&1
	    cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/serverj-packager
	    mvn -Dbuild.arch=${ARCH} -Ddist.dir=${RELEASE_DIR1}/fileset2/api -Dtparty.src.dir=${THIRDPARTY_DIR}  -Dmaven.repo.local=$maven_local_repository clean install  >> $build_logfile 2>&1
        done

  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\] BUILD ERROR|FAILURE)" $build_logfile
  
  if [ $? = 0 ]; then
    touch $BUILD_BASE/log/$sys.$comp.failed
  else
    touch $BUILD_BASE/log/$sys.$comp.succeeded
  fi
  
  touch $BUILD_BASE/log/$sys.$comp.DONE
}

build_ars_serverj_components_clover () {

  sys=linux; export sys
  comp=serverj_components_clover; export comp
  eval "host=\$${sys}HOST_${comp}"
  ARCH=$sys; export ARCH

  ## Local Maven repo for both serverj_components_clover and serverj_clover should be same since serverj_components_clover do validation and creates pom.xml to be used by both. 
  comp_localrepo=boulder_clover; export comp_localrepo
  
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp_localrepo}; export maven_local_repository  
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && mv $build_logfile	${build_logfile}_$$
    [ -f $BUILD_BASE/log/$sys.${comp}.succeeded ] && rm $BUILD_BASE/log/$sys.${comp}.succeeded
	[ -f $BUILD_BASE/log/$sys.${comp}.DONE ] && rm $BUILD_BASE/log/$sys.${comp}.DONE

   [ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj_clover ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj_clover; 
 
	RELEASE_DIR1=$RELEASEAREA/linux; export RELEASE_DIR1  ## hard coded to linux as of now, need to do for all unix platforms
	BASE_DIR=${BUILD_BASE}/src/unix/ars/server/common; export BASE_DIR

	echo "##### serverj_components_clover build STARTED #####" > $build_logfile 2>&1
	
    echo "##### serverj_components_clover : validate #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_clover/repository
	mvn -Dmaven.repo.local=$maven_local_repository -Dtparty.src.dir=${THIRDPARTY_DIR} -Datriumsso.version=current validate  >> $build_logfile 2>&1

	echo "##### serverj_components_clover : serverj_components_clover compilation #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_clover
	mvn clean install -Dcompiler=${CPLUSPLUS} -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license >> $build_logfile 2>&1
	
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_clover/api
	mvn javadoc:jar -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license >> $build_logfile 2>&1
	
	echo "##### serverj_components_clover : messagingclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_clover/arsystem/projects/messagingclient
	mvn clean install -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license >> $build_logfile 2>&1

	echo "##### serverj_components_clover : companionremote #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_clover/arsystem/projects/companionremote
	mvn clean install -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license >> $build_logfile 2>&1
	
	echo "##### serverj_components_clover : companionclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_clover/arsystem/projects/companionclient
	mvn clean install -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license  >> $build_logfile 2>&1

	echo "##### serverj_components_clover : dev-utilities/projects/lucenemigrator  #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_clover/arsystem/projects/dev-utilities/projects/lucenemigrator
	mvn clean install -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license  >> $build_logfile 2>&1
		
	echo "##### serverj_components_clover : devkits #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_clover/arsystem/projects/devkits
	mvn clean install -Dmaven.repo.local=$maven_local_repository  -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj_clover  >> $build_logfile 2>&1

	echo "##### serverj_components_clover : pluginsvr #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_clover/pluginsvr
	mvn clean install -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license >> $build_logfile 2>&1

	echo "##### serverj_components_clover : plugins #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_clover/plugins
	mvn clean install javadoc:jar -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license  >> $build_logfile 2>&1
	
	echo "##### serverj_components_clover : UnsupportedUtils #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_clover/unsupportedUtils
	mvn clean install -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license  >> $build_logfile 2>&1
	
	## Required java components files will be copied under release directory. It was earlier done by server_install target under each platform. 
	echo "##### serverj_components_clover : severj-packager #####" >> $build_logfile 2>&1
    
	for platform in linux solaris
        do
            RELEASE_DIR1=$RELEASEAREA/$platform; export RELEASE_DIR1
            echo "Release directory = $RELEASE_DIR1 " >>$build_logfile 2>&1
	    [ ! -d ${RELEASE_DIR1}/fileset2_clover/api ] && mkdir -p ${RELEASE_DIR1}/fileset2_clover/api >> $build_logfile 2>&1
	    cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_clover/serverj-packager
	    mvn clean install -Dbuild.arch=${ARCH} -Ddist.dir=${RELEASE_DIR1}/fileset2_clover/api -Dtparty.src.dir=${THIRDPARTY_DIR} -Dmaven.repo.local=$maven_local_repository -Dmaven.clover.cloverDatabaseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_components_clover/target/clover -Dmaven.clover.licenseLocation=$BUILD_BASE/src/unix/ars/server/common/serverj_clover/arsystem/projects/external/licenses/clover.license  >> $build_logfile 2>&1
        done

  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\] BUILD ERROR|FAILURE)" $build_logfile
  
  if [ $? = 0 ]; then
    touch $BUILD_BASE/log/$sys.$comp.failed
  else
    touch $BUILD_BASE/log/$sys.$comp.succeeded
  fi
  
  touch $BUILD_BASE/log/$sys.$comp.DONE

}


build_ars_serverj_components_deploy () {

  sys=linux; export sys
  comp=serverj_components_deploy; export comp
  eval "host=\$${sys}HOST_${comp}"
  ARCH=$sys; export ARCH
  
  ## Local Maven repo for both serverj_components and serverj should be same since serverj_components do validation and creates pom.xml to be used by both. 
  comp_localrepo=boulder_deploy; export comp_localrepo
  
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp_localrepo}; export maven_local_repository  
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && mv $build_logfile	${build_logfile}_$$
    [ -f $BUILD_BASE/log/$sys.${comp}.succeeded ] && rm $BUILD_BASE/log/$sys.${comp}.succeeded
	[ -f $BUILD_BASE/log/$sys.${comp}.DONE ] && rm $BUILD_BASE/log/$sys.${comp}.DONE

   #[ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj; 
 
	RELEASE_DIR1=$RELEASEAREA/linux; export RELEASE_DIR1  ## hard coded to linux as of now, need to do for all unix platforms
	BASE_DIR=${BUILD_BASE}/src/unix/ars/server/common; export BASE_DIR

	echo "##### Serverj_Components_deploy build STARTED #####" > $build_logfile 2>&1

#	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects
#	mvn initialize  -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

#    echo "##### serverj_components_deploy : validate #####" >> $build_logfile 2>&1
#	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_deploy/repository
#	mvn -Dmaven.repo.local=$maven_local_repository -Dtparty.src.dir=${THIRDPARTY_DIR} -Datriumsso.version=current validate  >> $build_logfile 2>&1

	echo "##### serverj_components_deploy : serverj_components_deploy compilation #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_deploy
	mvn clean deploy -Dcompiler=${CPLUSPLUS} -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1
	
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_deploy/api
	mvn javadoc:jar -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1
	
	echo "##### serverj_components_deploy : messagingclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_deploy/arsystem/projects/messagingclient
	mvn clean deploy -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

	echo "##### serverj_components_deploy : companionremote #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_deploy/arsystem/projects/companionremote
	mvn clean deploy -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1
	
	echo "##### serverj_components_deploy : companionclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_deploy/arsystem/projects/companionclient
	mvn clean deploy -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1

	echo "##### serverj_components_deploy : dev-utilities/projects/lucenemigrator  #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/projects/lucenemigrator
	mvn clean deploy -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1
		
	#echo "##### serverj_components_deploy : devkits #####" >> $build_logfile 2>&1
	#cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_deploy/arsystem/projects/devkits
	#mvn clean install -Dmaven.repo.local=$maven_local_repository  -Dapidrop.source=$DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj  >> $build_logfile 2>&1

	echo "##### serverj_components_deploy : pluginsvr #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_deploy/pluginsvr
	mvn clean deploy -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

	echo "##### serverj_components_deploy : plugins #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_deploy/plugins
	mvn clean deploy javadoc:jar -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1
	
	echo "##### serverj_components_deploy : UnsupportedUtils #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_deploy/unsupportedUtils
	mvn clean deploy -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1
	
	## Required java components files will be copied under release directory. It was earlier done by server_install target under each platform. 
	## server-packager has known issues when run after deploy targets. Also it is not necessary to build serverj-packager since it is already built in install target. 
	#echo "##### serverj_components_deploy : severj-packager #####" >> $build_logfile 2>&1
    
	# for platform in linux solaris
        # do
            # RELEASE_DIR1=$RELEASEAREA/$platform; export RELEASE_DIR1
            # echo "Release directory = $RELEASE_DIR1 " >>$build_logfile 2>&1
	    # [ ! -d ${RELEASE_DIR1}/fileset2/api ] && mkdir -p ${RELEASE_DIR1}/fileset2/api >> $build_logfile 2>&1
	    # cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components_deploy/serverj-packager
	    # mvn -Dbuild.arch=${ARCH} -Ddist.dir=${RELEASE_DIR1}/fileset2/api -Dtparty.src.dir=${THIRDPARTY_DIR}  -Dmaven.repo.local=$maven_local_repository clean install  >> $build_logfile 2>&1
        # done

  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\] BUILD ERROR|FAILURE)" $build_logfile
  
  if [ $? = 0 ]; then
    touch $BUILD_BASE/log/$sys.$comp.failed
  else
    touch $BUILD_BASE/log/$sys.$comp.succeeded
  fi
  
  touch $BUILD_BASE/log/$sys.$comp.DONE
}


build_ars_serverj_components_kw () {

  sys=linux; export sys
  comp=serverj_components_kw; export comp
  eval "host=\$${sys}HOST_${comp}"
  ARCH=$sys; export ARCH
  
  KWDIR=$LOGDIR/klocwork_sjcomp; export KWDIR
  mkdir -p $KWDIR
  ## Local Maven repo for both serverj_components and serverj should be same since serverj_components do validation and creates pom.xml to be used by both. 
  comp_localrepo=boulder_kw; export comp_localrepo
  
    maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp_localrepo}; export maven_local_repository  
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
    [ -f $build_logfile ] && mv $build_logfile	${build_logfile}_$$
    [ -f $BUILD_BASE/log/$sys.${comp}.succeeded ] && rm $BUILD_BASE/log/$sys.${comp}.succeeded
	[ -f $BUILD_BASE/log/$sys.${comp}.DONE ] && rm $BUILD_BASE/log/$sys.${comp}.DONE

   [ ! -d $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj ] && mkdir -p $DEVKITS_DIR/$app/$version/${ARS_BUILD_ID}/serverj; 
 
	RELEASE_DIR1=$RELEASEAREA/linux; export RELEASE_DIR1  ## hard coded to linux as of now, need to do for all unix platforms
	BASE_DIR=${BUILD_BASE}/src/unix/ars/server/common; export BASE_DIR

	echo "##### Serverj_Components build STARTED #####" > $build_logfile 2>&1

#	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects
#	mvn initialize  -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

    echo "##### Serverj_Components : validate #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/repository
	mvn -Dmaven.repo.local=$maven_local_repository -Dtparty.src.dir=${THIRDPARTY_DIR} -Datriumsso.version=current validate -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH  >> $build_logfile 2>&1

	echo "##### Serverj_Components : serverj_components compilation #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components
	mvn clean install -Dcompiler=${CPLUSPLUS} -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1
	
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/api
	mvn javadoc:jar -Dmaven.repo.local=$maven_local_repository -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1
	
	echo "##### Serverj_Components : messagingclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/messagingclient
	mvn clean install -Dmaven.repo.local=$maven_local_repository -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1

	echo "##### Serverj_Components : companionremote #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/companionremote
	mvn clean install -Dmaven.repo.local=$maven_local_repository -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1
	
	echo "##### Serverj_Components : companionclient #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/companionclient
	mvn clean install -Dmaven.repo.local=$maven_local_repository -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH  >> $build_logfile 2>&1
	
	echo "##### Serverj_Components : devkits #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/devkits
	mvn clean install -Dmaven.repo.local=$maven_local_repository  >> $build_logfile 2>&1

	echo "##### Serverj_Components : pluginsvr #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/pluginsvr
	mvn clean install -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1

	echo "##### Serverj_Components : plugins #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/plugins
	mvn clean install javadoc:jar -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository  -Dklocwork.spec=$KWDIR/kwinject.out -Dklocwork.path=$KW_SERVER_PATH >> $build_logfile 2>&1
	
	echo "##### Serverj_Components : UnsupportedUtils #####" >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/unsupportedUtils
	mvn clean install -Datriumsso.version=current -Dmaven.repo.local=$maven_local_repository   >> $build_logfile 2>&1
	
	## Required java components files will be copied under release directory. It was earlier done by server_install target under each platform. 
	echo "##### Serverj_Components : severj-packager #####" >> $build_logfile 2>&1
	[ ! -d ${RELEASE_DIR1}/fileset2/api ] && mkdir -p ${RELEASE_DIR1}/fileset2/api >> $build_logfile 2>&1
	cd ${BUILD_BASE}/src/unix/ars/server/common/serverj_components/serverj-packager
	mvn -Dbuild.arch=${ARCH} -Ddist.dir=${RELEASE_DIR1}/fileset2/api -Dtparty.src.dir=${THIRDPARTY_DIR}  -Dmaven.repo.local=$maven_local_repository clean install  >> $build_logfile 2>&1

  egrep "(BUILD FAILURE|fatal error|FATAL ERROR|\[ERROR\] BUILD ERROR)" $build_logfile
  
  if [ $? = 0 ]; then
    touch $BUILD_BASE/log/$sys.$comp.failed
  else
    touch $BUILD_BASE/log/$sys.$comp.succeeded
  fi
  
  touch $BUILD_BASE/log/$sys.$comp.DONE
}

genrate_kw_report(){

    sys=linux; export sys
	eval "host=\$${sys}HOST_${comp}"
	
    build_logfile=$cfg_root/$buildid/$app/log/$sys.$host.$comp.log; export build_logfile
	
   gen_kwreport_jar="${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/projects/genkwreport/target/genkwreport-1.0-jar-with-dependencies.jar"; export gen_kwreport_jar
   
   maven_local_repository=${DEVKITS_DIR}/localmavenrepo/$app/.m2_${version}_${comp}; export maven_local_repository
  
  if [ ! -f $gen_kwreport_jar ] ; then
  
    echo "Maven Local Repository = $maven_local_repository" > $build_logfile 2>&1
	
    cd  $BUILD_BASE/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/projects/gensowfile
	mvn clean install -Dmaven.repo.local=$maven_local_repository >> $build_logfile 2>&1  
    
    cd   ${BUILD_BASE}/src/unix/ars/server/common/serverj/arsystem/projects/dev-utilities/projects/genkwreport; 
	mvn clean install -Dmaven.repo.local=$maven_local_repository >> $build_logfile 2>&1  
  
  fi
  
	mkdir $LOGDIR/${comp}_kwreport; 
	
	echo  >> $build_logfile
	echo "Generate KW reports --  generate html report" >> $build_logfile 2>&1
	java -jar $gen_kwreport_jar -url $KW_SERVER_URL -user buildadm -p ${KWProject} -o "$LOGDIR/${comp}_kwreport/kwemailBody.htm" -l 2 >> $build_logfile 2>&1

	MailSubject="Klocwork Build Summary (Main_${comp})"; export MailSubject

	cd $LOGDIR/${comp}_kwreport
	grep ">0 Open Issues<" kwemailBody.htm
	cat kwemailBody.htm | perl $DEVKITS_DIR/tools/build/bin/sendEmail.pl -u "$MailSubject" -f $cfg_notify_from  -t _153a8f@BMC.com -cc _23b031@bmc.com		
	#cat kwemailBody.htm | perl $DEVKITS_DIR/tools/build/bin/sendEmail.pl -u "$MailSubject" -f $cfg_notify_from  -t ssonaika@bmc.com		
}

build_ars_pentaho6 () {

  info "Start - Building Pentaho6.0.1.0"

  echo "ANT 1.8.1 is required for Pentaho6.0.1.0 build" 
  ANT_HOME=$DEVKITS_DIR/tools/build_software/ant/apache-ant-1.8.1; export ANT_HOME
  JAVA_HOME=$DEVKITS_DIR/tools/build_software/jdk/jdk1.8.0_45/lx64; export JAVA_HOME
  PATH=$ANT_HOME/bin:$PATH
  export PATH

  echo $PATH

  cd $ARS_COMMON_PERIPHERALS_SRC_DIR
  [ -f build.properties ] && rm -f build.properties
  echo "devkit.dir=$DEVKITS_DIR/$app/$version/$ARS_BUILD_ID" > $ARS_COMMON_PERIPHERALS_SRC_DIR/build.properties


  cd ${ARS_PENTAHO6_SRC_DIR} 

  echo "Create build.properties file"

  echo "devkit.dir=$DEVKITS_DIR/$app/$version/$ARS_BUILD_ID" > build.properties
  echo "build.platform=linux" >> build.properties
  echo "tparty.lib.dir=$THIRDPARTY_DIR" >> build.properties

  
  [ -f build.properties.default ] &&  mv build.properties.default  build.properties.default.orig
  cat build.properties.default.orig | sed -e 's/#modules.publish-remote=false/modules.publish-remote=false/' > build.properties.default

  [ -f build.properties.default ] &&  mv build.properties.default  build.properties.default.orig
   cat build.properties.default.orig | sed -e 's/modules.publish-remote=false/modules.publish-remote=true/'  > build.properties.default

  [ -f build.properties.default ] &&  mv build.properties.default  build.properties.default.orig
   cat build.properties.default.orig | sed -e 's/pentaho-bmc-repo.username=/pentaho-bmc-repo.username=test/' > build.properties.default

  [ -f build.properties.default ] &&  mv build.properties.default  build.properties.default.orig
  cat build.properties.default.orig | sed -e 's/pentaho-bmc-repo.password=/pentaho-bmc-repo.password=test123/' > build.properties.default

  
  mv build.xml  build.xml.orig
  cat build.xml.orig  | sed -e  's#<property name="ivy.default.ivy.user.dir" value="${user.home}/.ivy2">/#<property name="ivy.default.ivy.user.dir" value="/pun-rem-fs02/devkits/localmavenrepo/ars/.ivy2_pentaho-kettle_main"/>#' > build.xml
  
  #if [ $cfg_site = "pun" ]; then
    #echo "cmdbkettlebinary.dir=${ATRIUM_BLD_ROOT}/rbuild/cmdb/main/current/cmdb/atriumfoundation_stagearea/ngie/server/data-integration" >> ${ARS_PENTAHO_SRC_DIR}/build.properties
  #else
    #echo "cmdbkettlebinary.dir=${ATRIUM_BLD_ROOT}/rbuild/cmdb/dev_cobalt/current/cmdb/atriumfoundation_stagearea/ngie/server/data-integration" >> ${ARS_PENTAHO_SRC_DIR}/build.properties
  #fi

  $ANT_HOME/bin/ant

  info "End - Building Pentaho"
}


if [ $ARS_BUILD_COMP = "all" ]; then
  build_env_out
  update_build_version
  build_ars_api 
  build_ars_server
  build_ars_client_unix
  copy_api_devkits
  copy_rik_devkits
#  build_ars_approval 
#  build_ars_assignment 
   build_ars_install 
#  build_approval_install
#  if [ $cfg_site = "pun" ]; then
#	sleep 500
#  fi
#  build_assignment_install 
  build_appsignal
  build_sigmask
  build_status
elif [ $ARS_BUILD_COMP = "api_server_debug" ]; then
  update_build_version
  build_ars_api
  build_ars_server
elif [ $ARS_BUILD_COMP = "api" ]; then
  build_ars_api
elif [ $ARS_BUILD_COMP = "server" ]; then
  build_ars_server
elif [ $ARS_BUILD_COMP = "client_unix" ]; then
  build_ars_client_unix
elif [ $ARS_BUILD_COMP = "api_devkits" ]; then
  copy_api_devkits
elif [ $ARS_BUILD_COMP = "rik_devkits" ]; then
  copy_rik_devkits
#elif [ $ARS_BUILD_COMP = "approval" ]; then
#  build_ars_approval
#elif [ $ARS_BUILD_COMP = "assignment" ]; then
#  build_ars_assignment
elif [ $ARS_BUILD_COMP = "ars_install" ]; then
  build_ars_install
#elif [ $ARS_BUILD_COMP = "approval_install" ]; then
#  build_approval_install
#elif [ $ARS_BUILD_COMP = "assignment_install" ]; then
#  build_assignment_install
elif [ $ARS_BUILD_COMP = "appsignal" ]; then 
  build_appsignal
elif [ $ARS_BUILD_COMP = "sigmask" ]; then 
  build_sigmask
elif [ $ARS_BUILD_COMP = "copy_api_complete_devkits" ]; then
  copy_api_complete_devkits
elif [ $ARS_BUILD_COMP = "healthadvisor" ]; then   
  build_ars_healthadvisor  
elif [ $ARS_BUILD_COMP = "boulder" ]; then  
  build_ars_boulder
elif [ $ARS_BUILD_COMP = "boulder_deploy" ]; then  
  build_ars_boulder_deploy
elif [ $ARS_BUILD_COMP = "boulder_clover" ]; then  
  build_ars_serverj_components_clover
  build_ars_boulder_clover  
elif [ $ARS_BUILD_COMP = "boulder_kw" ]; then  
  build_ars_boulder_kw 
elif [ $ARS_BUILD_COMP = "oengine" ]; then
  build_ars_oengine
 elif [ $ARS_BUILD_COMP = "inappreporting" ]; then 
  build_ars_inappreporting
elif [ $ARS_BUILD_COMP = "midtier" ]; then     
  build_ars_midtier  
elif [ $ARS_BUILD_COMP = "ARMigrate" ]; then     
  build_ars_ARMigrate
elif [ $ARS_BUILD_COMP = "serverj_components" ]; then     
  build_ars_serverj_components  
elif [ $ARS_BUILD_COMP = "serverj_components_clover" ]; then     
  build_ars_serverj_components_clover  
elif [ $ARS_BUILD_COMP = "serverj_components_deploy" ]; then     
  build_ars_serverj_components_deploy   
elif [ $ARS_BUILD_COMP = "serverj_components_kw" ]; then     
  build_ars_serverj_components_kw
elif [ $ARS_BUILD_COMP = "midtier_kw" ]; then     
  comp=midtier_kw; export comp
  KWProject=ARS_MAIN_MIDTIER; export KWProject
  genrate_kw_report  
elif [ $ARS_BUILD_COMP = "emaild_kw" ]; then     
  comp=emaild_kw; export comp
  KWProject=Remedy_Email_Engine_Main; export KWProject
  genrate_kw_report
elif [ $ARS_BUILD_COMP = "ars_peripherals_kw" ]; then     
  comp=ars_peripherals_kw; export comp
  KWProject=Remedy_Approval_Server_Main; export KWProject
  genrate_kw_report  
elif [ $ARS_BUILD_COMP = "aej_kw" ]; then     
  comp=aej_kw; export comp
  KWProject=Remedy_Assignment_Engine_Main; export KWProject
  genrate_kw_report
elif [ $ARS_BUILD_COMP = "rikj_kw" ]; then     
  comp=rikj_kw; export comp
  KWProject=ARS_MAIN_RIKJ; export KWProject
  genrate_kw_report 
elif [ $ARS_BUILD_COMP = "devstudio_kw" ]; then     
  comp=devstudio_kw; export comp
  KWProject=ARS_MAIN_DEVSTUDIO; export KWProject
  genrate_kw_report 
elif [ $ARS_BUILD_COMP = "migrator_kw" ]; then     
  comp=migrator_kw; export comp
  KWProject=ARS_MAIN_MIGRATOR; export KWProject
  genrate_kw_report  
elif [ $ARS_BUILD_COMP = "pentaho6" ]; then 
  build_ars_pentaho6
elif [ $ARS_BUILD_COMP = "boulder_deploy_artifacts" ]; then 
  build_ars_boulder_deploy_artifacts
fi
