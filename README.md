# POWER Linux Export Script

Copyright 2019 Skytap Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Things to know before getting started:
- Both scripts need to be made available on the Linux lpar and should be in the same directory (export\_linux runs make\_linux\_ovf).
- Script output, including disk images and ovf file will be placed in the current working directory they are run from.
- The scripts do not perform destructive tasks and will in general not clean up files they generate. However: make\_linux\_ovf will overwrite the output ovf file with the same name. If compression is flagged, this will create temporary files.
- Only the disk images specified when running export\_linux will generate disk images and these images will include unused space on the disk (do not have a way to flatten the images out at this time).
- It is recommended to include a bootable disk, disk order on import is not guaranteed.
- Disks will consume a LOT of space on initial export. Expect the output disk images to be the full size of any volumes targeted for export. If using compression you will need space for the full disks and the compressed disks until compression is complete.

## There are two scripts involved:
```
export_linux
make_linux_ovf
```

## Background
These scripts are intended to produce two types of output. One output of these scripts are IMG files which are the disk images for the lpar, one of these IMG files should represent a bootable volume. It will also generate an OVF file which is the descriptor of the linux system. The OVF will be used at time of import by Skytap to create the power lpar to specifications.

export\_linux will automatically run make\_linux\_ovf when it is complete. make\_linux\_ovf can be run separately if desired.

## How to use these scripts
- Your OS activity and databases should be quiesced if possible, disk activity can cause inconsistencies in the copy.
- (Optional) to further unmount the physical volumes.
- Within the directory you want your images to be created, run export\_linux.sh with  disk names as arguments, starting with your boot disk. (THIS WILL TAKE A LONG TIME)
- export\_linux.sh [-c] drive [driveb ... drivex]
- (Optional) -c can be used as a flag to compress the output into an OVA file. This is a compressed tarball of the image and ovf output. If pigz (Parallel gzip) can be found in the path this will be used, otherwise the gzip flag from tar will be used.
- When export\_linux.sh is complete, it will automatically start make\_linux\_ovf.sh with the same disks specified when running export\_linux.sh.
- The the output files (OVF+IMG or OVA) can be uploaded and imported directly into Skytap via SFTP, or shipped to Skytap's office and we can assist with import efforts.

## export\_linux.sh
export\_lpap expects to be passed a string of drive names (eg, sda sdb sdx ...). It will then validate it has access to those drives and use dd to create IMG files for each disk. The IMG files will be created in your present working directory. The first drive specified should be a bootable drive, it is strongly recommended to quiesce the system to avoid data inconsistencies. When the image files are created, it will then automatically run make\_linux\_ovf with the same arguments.

## make\_linux\_ovf.sh
make\_ovf expects to be passed a string of devices names (eg, sda sdb sdx ...) that should be included within the OVF file and a compression flag if OVA files are desired. It will detect the number of virtual processors (not physical), RAM allocation, active ethernet adapters, and it will name the exported server and OVF file after the server hostname. Disks passed into the script are evaluated to exist and then will also be included in the output OVF. Other system details are not captured in the OVF. If compression is flagged this script will attempt to use pigz (parallal gzip) or the compression flag on tar to compress the disk images and ovf files into a tarball appended with .ova. This script will be automatically called when export\_linux is complete, it can also be run as a stand-alone script to only generate an OVF/OVA file.
