#!/bin/sh
#  %name: change_history.sh %
#  %instance: wildlife_1 %
#  %version: 1 %
#  %derived_by: ekramer %
#  %date_modified: (space)%
#  Copyright (c) 2003 Remedy a BMC Software company.  All rights reserved.
#------------------------------------------------------------------
# Print CCM Change History report to stdout
#------------------------------------------------------------------

Usage="$0 -c current_folder_spec {-p previous_folder_spec | -f folder_family} [-h]"


#------------------------------------------------------------------
# Process command line
#------------------------------------------------------------------

# parse command line 
while [ ! -z "$1" ]; do
  case "$1" in
  -c|-curr)
    shift
	  curr_folder_spec=$1
	  ;;
  -p|-prev) 
    shift
	  prev_folder_spec=$1
	  ;;
  -f|-family) 
    shift
	  folder_family=$1
	  ;;
  -h) 
    echo $Usage
	  exit;;
  *)  
    echo "$0: Unknown parameter $1, exiting ... "
	  exit ;;
  esac
  shift
done



#--------------------------------------------
# Assure critical variables are set
#
[ -z ${CCM_ADDR} ] && echo Error:  CCM_ADDR not set && exit 1
[ -z "$curr_folder_spec" ] && echo Error:  Current folder spec not set && echo $Usage && exit 1
[ -z "$prev_folder_spec" -a -z "$folder_family"  ] && \
  echo Error:  Must supply either previous folder or folder family && exit 1



#--------------------------------------------
# Initialization
#

#debug mode
[ ! -z "$BLD_DEBUG" ] && set -xv

# we should have sourced envs already. If not, do some investigation
if [ -z "$BLDADMIN" ]; then
	BLDADMIN=`/usr/bin/dirname $0`
	cd $BLDADMIN
	BLDADMIN=`pwd`; export BLDADMIN
	SRC_BASE=`/usr/bin/dirname $BLDADMIN`; export SRC_BASE

	. ${BLDADMIN}/setvar.sh
fi

. ${BLDADMIN}/lib.sh



#--------------------------------------------
# ccm_change_report writes CCM change history 
# based on folder differences to standard output.
#--------------------------------------------
# Input:
#	 $1 Folder spec for current (newer) folder
#  $2 Folder spec for previous (older) folder
#
# Output:
#	Change history from folder comparisons is written to standard output.
#
# Return Code:
#	0	Change history written
# 1 Error occurred composing change history report
#
# Error Handling:
#	Fatal error on invalid parameters or CCM_ADDR not set
#	Fatal error for folder lookup failure
# Fatal error if sed write fails
#
#
ccm_change_report()
{
  curr_folderspec=$1
  prev_folderspec=$2

  tempfile=fldrcmp.$$
  rptfmt=rptfmt.$$


  #--------------------------------------------
  # Assure critical variables are set
  #
  [ -z ${CCM_ADDR} ] && echo Error:  CCM_ADDR not set && return 1 
  [ "X" = "${curr_folderspec}X" ] && echo Error:  Current folder spec not set && return 1
  [ "X" = "${prev_folderspec}X" ] && echo Error:  Previous folder spec not set && return 1


  #--------------------------------------------
  # sed script for formatting change history report
  #
  cat > $rptfmt <<\_END
s/^_CCMTSK: \(.*\)_CCMSYNPSS: \(.*\)_CCMDSCR: \(.*\)/Task:  \1\
Synopsis:  \2\
Description: \
\3\
/
_END


  #--------------------------------------------
  # Find changes (current tasks - previous tasks)
  #
  rm -f ${tempfile}
  ccm folder -compare ${curr_folderspec} -not_in ${prev_folderspec} -u \
    -f "_CCMTSK: %displayname _CCMSYNPSS: %task_synopsis _CCMDSCR: %task_description" \
    > ${tempfile} \
    || { echo Error: folder compare failed for ${prev_folderspec} to ${curr_folderspec}; \
       return 1 ;}


  #--------------------------------------------
  # Format report and write to stdout
  #
  sed -f ${rptfmt} ${tempfile} \
      || { echo Error: sed failed on ${tempfile}; return 1 ;}


  #--------------------------------------------
  # Cleanup and return
  #
  rm -f ${tempfile} ${rptfmt}
  return 0

}


#--------------------------------------------
# ccm_previous_folder finds the folder of the
# same family (by name) created prior to the
# argument folder
#--------------------------------------------
# Input:
#	 $1 Folder spec for current folder
#  $2 Folder family name (prefix)
#  $3 Variable name for previous folder spec
#
# Output:
#	Previous folder spec is passed back by reference via final argument
#
# Return Code:
#	0	Previous folder found
#
# Error Handling:
#	Error on invalid parameters or CCM_ADDR not set
#	Error for folder lookup failure
# Error if folder not found
#
#
ccm_previous_folder()
{
  curr_folderspec=$1
  folderfamily=$2
  prev_folderspec_ptr=$3

  findprev=findprev.$$


  #--------------------------------------------
  # Assure critical variables are set
  #
  [ -z ${CCM_ADDR} ] && echo Error:  CCM_ADDR not set && return 1 
  [ "X" = "${curr_folderspec}X" ] && echo Error:  Current folder spec not set && return 1
  [ "X" = "${folderfamily}X" ] && echo Error:  Folder family name not set && return 1
  [ "X" = "${prev_folderspec_ptr}X" ] && echo Error:  Previous folder spec reference not supplied && return 1


  #--------------------------------------------
  # Initialize
  #

  # Get curr_foldernum and dbname if present from curr_folderspec
  curr_foldernum=`echo $curr_folderspec | sed "s/.*#//"`
  dbname=`echo $curr_folderspec | sed "s/#.*//"`


  #--------------------------------------------
  # sed script to find previous folder number
  #
  # This script assumes numbers are sorted in ascending order and are unique.
  # Place any number not matching current folder number in holding space(h).
  # Delete on pattern space (d) causes control to go to the top on the next line.
  # When current folder number is found, get previous number from holding space.
  # Since we'll reach the end of the sed script, we'll print the result that we
  # get from the holding space.
  cat > $findprev <<_END
/$curr_foldernum/!{
h
d
}
/$curr_foldernum/{
g
}
_END


  #--------------------------------------------
  # Find previous folder
  #

#
# Print all build folders; name is really the folder number without the database id
#
  prev_foldernum=`ccm folder -list -u all_build_mgrs -f "%name %description" |
#
# Filter on folder family name
#
 grep "${folderfamily}" |
#
# Remember just the folder numbers for folders in our family
#
  cut -f1 -d\ |
#
# Put family folders in ascending numerical/chronological order
#
  sort -n |
#
# Now locate the folder just before the current folder
#
  sed -f $findprev`
  
  if [ "X" = "X${prev_foldernum}" ]; then
    echo Error:  finding previous folder to $curr_folderspec in family $folderfamily 
    return 1
  fi


  #--------------------------------------------
  # Set value of previous folder
  #
  if [ "${curr_folderspec}" = "${curr_foldernum}" ]; then
    spec=${prev_foldernum}
  else
    spec=${dbname}#${prev_foldernum}
  fi

  eval "${prev_folderspec_ptr}=\"${spec}\""

  rm $findprev
  return 0

}

#--------------------------------------------
# Compose change report using current folder and previous folder
#

# If I don't have a previous folder, I must have a folder family;
# Find previous folder from current folder and folder family
if [ -z "$prev_folder_spec" ]; then
  ccm_previous_folder ${curr_folder_spec} "${folder_family}" prev_folder_spec || \
    { echo Error: failed to find previous folder given $curr_folder_spec and $folder_family ; \
    exit 1;}
fi


[ ! -z "$BLD_DEBUG" ] && echo Previous folder spec is $prev_folder_spec

# Print Change Report to stdout
ccm_change_report $curr_folder_spec $prev_folder_spec 


exit 0



