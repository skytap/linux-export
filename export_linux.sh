#!/bin/bash

########################################################################
## Copyright 2020 Skytap Inc.
## 
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
## 
##     http://www.apache.org/licenses/LICENSE-2.0
## 
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
########################################################################


## Intended to be used to export Red Hat Enterprise Linux on Power
## Generates the disk images required for import into Skytap cloud
## Expect make_linux_ovf script to be within same directory to call at end
## Pass desired physical volumes names into script
##
## It is recommend that that OS have limited activity at time of export


########################################################################
## FIND AND DECLARE VARIABLES
########################################################################


## Check for empty parameters 
if [ $# -eq 0 ];then
   echo "No parameters were passed, exiting script"
   echo "Expecting to drive names as arguments: -c [drive ... drivex]"
   echo "    -c: compresses files into .ova format"
   echo "    expects to receive drive name, eg sda sdb... sdx"
   exit 1
fi

## Check for feature flags
c_flag='false' ## Compression flag
while getopts 'c' flag; do
  case "${flag}" in
    c) c_flag='true'
    shift $((OPTIND -1));;
  esac
done

## Will set the imported VM name to be the same as the hostname
LPAR_NAME=$(hostname)

## Test for disks
echo ""
echo "Locating Disks:"
for arg in "$@";do
   DISK=`lscfg -l $arg`
   if [ $? -ne 0 ]; then
      >&2 echo "FAILED: unable to detect device $arg, exiting script"
      exit 1 #exit script due to failure state, unable to find disk
   fi
   DISK_ALLOCATION=$(lsblk --output SIZE -n -d /dev/$arg)
   echo "Found device $arg, $DISK_ALLOCATION"
done


## Prompt for user response of disk size before proceeding
echo ""
echo "Disk images will be created uncompressed in local directory."
echo "Create these image(s) in your local directory? (Yes/No)"
read  answer
case $answer in
   yes|Yes|y)
       ;;
   no|n|No)
      exit 2 #exiting due to user response, no errors
      ;;
esac

## Create disk images
echo ""
for arg in "$@";do
   echo "=== Creating disk $LPAR_NAME-$arg.img ==="
   dd if=/dev/$arg of=$LPAR_NAME-$arg.img bs=1M conv=noerror,sync status=progress
done
echo 'Disks images created'

echo $c_flag
## Run make_linux_ovf.sh script and pass compression flag
if [ $c_flag = 'true' ] ; then
    ( ${0%/*}/make_linux_ovf.sh "-c" "$@" )
else
    ( ${0%/*}/make_linux_ovf.sh "$@" )
fi

if [ $? -ne 0 ]; then
   >&2 echo "FAILED: error with ovf creation, exiting script"
   exit 1 #exit script due to failure state, received failure from make_ovf script
fi

exit 0 #successful exit
