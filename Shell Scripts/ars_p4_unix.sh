#!/bin/sh

#   %full_name: wildlife#1/shsrc/ars_p4_unix.sh/1 %
#   %version: 1 %
#   %date_modified: %

set -xv

while [ ! -z "$1" ]
do
  case "$1" in
  -p) shift; p4_port="$1";;
  -c) shift; p4_client="$1";;
  -d) shift; ars_build_dir="$1";;
  *)  error Wrong argument && echo $Usage && exit 1;;
  esac
  shift
done

[ -f "$BLDLOC/buildcontrol.sh" ] && . $BLDLOC/buildcontrol.sh

p4 

echo "[INFO] `date` ARS Source Copy started"

[ ! -d $ars_build_dir ] && mkdir -p $ars_build_dir

if [ -d $ccm_wa ]; then
  cp -rp $ccm_wa $ars_build_dir
else
  echo "[ERROR] Can not access '$ccm_wa'"
  exit 1
fi

echo "[INFO] `date` ARS Source Copy completed"
