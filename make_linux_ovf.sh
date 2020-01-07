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


## Creates Red Hat Linux OVF file for import into Skytap cloud
## Intended to be run by export_linux script, but can be used stand-alone
## Pass desired physical volumes into script starting with boot disk


########################################################################
## FIND AND DECLARE VARIABLES
########################################################################


## Check for compression flag
c_flag='false' ## Compression flag
while getopts 'c' flag; do
  case "${flag}" in
    c) c_flag='true'
    shift $((OPTIND -1));;
  esac
done

## Will set the imported VM name to be the same as the hostname
LPAR_NAME=$(hostname)

## Find number of virtual processors (count of unique cores and sockets)
VIRTUAL_PROCESSORS=$(lscpu -b -p=Core,Socket | grep -v '^#' | sort -u | wc -l)

## Find amount of allocated RAM in MB
totalmem=0;
for mem in /sys/devices/system/memory/memory*; do
  [[ "$(cat ${mem}/online)" == "1" ]] \
    && totalmem=$((totalmem+$((0x$(cat /sys/devices/system/memory/block_size_bytes)))));
done
RAM_ALLOCATION=$((totalmem/1024**2))

## Find all in-use ethernet adapters
ETHERNET_ADAPTERS=$(nmcli -t -g NAME connection show | awk '{ print $1 }' | awk '!x[$0]++')

## Discover disks from input in bytes
for arg in "$@";do
   DISK=`lscfg -l $arg`
   if [ $? -ne 0 ]; then
      >&2 echo "FAILED: unable to detect device $arg, exiting script"
      exit 1 #exit script due to failure state, unable to find disk
   fi
done


########################################################################
## CREATE OVF FILE
########################################################################

echo ""
echo 'Creating OVF file: '$LPAR_NAME'.ovf'
cat << EOF > $LPAR_NAME.ovf
<?xml version="1.0" encoding="UTF-8"?>
<ovf:Envelope xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:skytap="http://help.skytap.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2.22.0/CIM_VirtualSystemSettingData.xsd http://schemas.dmtf.org/ovf/envelope/1 http://schemas.dmtf.org/ovf/envelope/1/dsp8023_1.1.0.xsd http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2.22.0/CIM_ResourceAllocationSettingData.xsd">
    <ovf:References>
EOF
for arg in "$@";do
   cat << EOF >> $LPAR_NAME.ovf
        <ovf:File ovf:id="file_$arg" ovf:href="$LPAR_NAME-$arg.img"/>
EOF
done
cat << EOF >> $LPAR_NAME.ovf
    </ovf:References>
    <ovf:DiskSection>
        <ovf:Info>Virtual disk information</ovf:Info>
EOF
for arg in "$@";do
   DISK_ALLOCATION=$(lsblk --output SIZE -n -d -b /dev/$arg)
   cat << EOF >> $LPAR_NAME.ovf
            <ovf:Disk ovf:fileRef="file_$arg" ovf:diskId="disk_$arg" ovf:capacity="$DISK_ALLOCATION"/>
EOF
done
   cat << EOF >> $LPAR_NAME.ovf
    </ovf:DiskSection>
    <ovf:VirtualSystemCollection ovf:id="Linux">
        <ovf:VirtualSystem ovf:id="Linux MachineName">
            <ovf:Name>$LPAR_NAME</ovf:Name>
            <ovf:OperatingSystemSection ovf:id="80">
                <ovf:Info/>
                <ovf:Description>Linux on Power</ovf:Description>
                <ns0:architecture xmlns:ns0="ibmpvc">ppc64</ns0:architecture>
            </ovf:OperatingSystemSection>
            <ovf:VirtualHardwareSection>
EOF
COUNT=1
for e in $ETHERNET_ADAPTERS;do
   SLOT=$(lscfg -l $e | sed -n 's/.*-C\([^-]*\)-.*/\1/p')
   NETCIDR=$(ip -4 addr show $e | grep inet | awk '{print $2}')
   NETADDR=$(echo $NETCIDR | awk -F/ '{print $1}')
   CIDRMASK=$(echo "${NETCIDR#*/}")
   MASKbase10=$(( 0xffffffff ^ ((1 << (32 - $CIDRMASK)) - 1) ))
   NETMASK=$(echo "$(( (MASKbase10 >> 24) & 0xff )).$(( (MASKbase10 >> 16) & 0xff )).\
$(( (MASKbase10 >> 8) & 0xff )).$(( MASKbase10 & 0xff ))")
   cat << EOF >> $LPAR_NAME.ovf
                <ovf:Item>
                    <rasd:Description>Ethernet adapter $COUNT</rasd:Description>
                    <rasd:ElementName>Network adapter $COUNT</rasd:ElementName>
                    <rasd:InstanceID>10$COUNT</rasd:InstanceID>
                    <rasd:ResourceType>10</rasd:ResourceType>
EOF
   if [ -n "$SLOT" ]; then
      cat << EOF >> $LPAR_NAME.ovf
                    <skytap:Config skytap:value="$SLOT" skytap:key="slotInfo.cardSlotNumber"/>
EOF
   fi
   if [ -n "$NETADDR" ]; then
      cat << EOF >> $LPAR_NAME.ovf
                    <skytap:Config skytap:value="$NETADDR" skytap:key="networkInterface.ipAddress"/>
EOF
   fi
   if [ -n "$NETMASK" ]; then
      cat << EOF >> $LPAR_NAME.ovf
                    <skytap:Config skytap:value="$NETMASK" skytap:key="networkInterface.netmask"/>
EOF
   fi
   cat << EOF >> $LPAR_NAME.ovf
                </ovf:Item>
EOF
   ((COUNT=COUNT+1))
done
COUNT=1
for arg in "$@";do
   SLOT=$(lscfg -l $arg | sed -n 's/.*-C\([^-]*\)-.*/\1/p')
   cat << EOF >> $LPAR_NAME.ovf
                <ovf:Item>
                    <rasd:Description>Hard disk</rasd:Description>
                    <rasd:ElementName>Hard disk $COUNT</rasd:ElementName>
                    <rasd:HostResource>ovf:/disk/disk_$arg</rasd:HostResource>
                    <rasd:InstanceID>100$COUNT</rasd:InstanceID>
                    <rasd:ResourceType>17</rasd:ResourceType>
EOF
   if [ -n "$SLOT" ]; then
         cat << EOF >> $LPAR_NAME.ovf
                    <skytap:Config skytap:value="$SLOT" skytap:key="slotInfo.cardSlotNumber"/>
EOF
   fi
   cat << EOF >> $LPAR_NAME.ovf
                </ovf:Item>
EOF
   ((COUNT=COUNT+1))
done
cat << EOF >> $LPAR_NAME.ovf
                <ovf:Item>
                    <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
                    <rasd:Description>Number of Virtual CPUs</rasd:Description>
                    <rasd:ElementName>$VIRTUAL_PROCESSORS virtual CPU(s)</rasd:ElementName>
                    <rasd:InstanceID>7</rasd:InstanceID>
                    <rasd:Reservation>0</rasd:Reservation>
                    <rasd:ResourceType>3</rasd:ResourceType>
                    <rasd:VirtualQuantity>$VIRTUAL_PROCESSORS</rasd:VirtualQuantity>
                    <rasd:Weight>0</rasd:Weight>
                </ovf:Item>
                <ovf:Item>
                    <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
                    <rasd:Description>Memory Size</rasd:Description>
                    <rasd:ElementName>$RAM_ALLOCATION MB of memory</rasd:ElementName>
                    <rasd:InstanceID>8</rasd:InstanceID>
                    <rasd:Reservation>0</rasd:Reservation>
                    <rasd:ResourceType>4</rasd:ResourceType>
                    <rasd:VirtualQuantity>$RAM_ALLOCATION</rasd:VirtualQuantity>
                    <rasd:Weight>0</rasd:Weight>
                </ovf:Item>
            </ovf:VirtualHardwareSection>
        </ovf:VirtualSystem>
    </ovf:VirtualSystemCollection>
</ovf:Envelope>
EOF

## OVF completed
echo 'OVF Completed Successfully'

## Compressing OVA file
if [ $c_flag = 'true' ] ; then
    echo 'Compressing files into OVA: '$LPAR_NAME'.ova'
    MKTAR=$LPAR_NAME'.ovf'
    for arg in "$@";do
      MKTAR=$(echo $MKTAR $LPAR_NAME-$arg'.img')
    done
    if command -v pigz >/dev/null 2>&1; then
        tar -cv --remove-files -f - ${MKTAR} | pigz > ${LPAR_NAME}.ova
    else
        tar -czv --remove-files -f ${LPAR_NAME}.ova ${MKTAR}
    fi
fi

## All done
exit 0 #successful exit
