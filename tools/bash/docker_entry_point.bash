#!/usr/bin/env bash

cat <<EOF

This script takes a directory with DICOM files of a CT or (3D) MR brain scan as input and then
aligns that scan with a reference volume, such as the MNI brain atlas.

 When no arguments are given, the container will start in daemon mode and listen
 for incoming DICOM connections.

 More help may be found when starting the container with the "--help" argument.

EOF

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if any arguments have been passed
if [ "$#" -eq 0 ]; then
  bash "${__dir}/../../BrainSTEM/incoming/incoming.bash" &
  bash "${__dir}/../../BrainSTEM/received/queue.bash" &
  wait
else
  "${__dir}/../../fatbACPC.bash" "$@"
fi 
