#!/usr/bin/env bash
#
# This script takes a directory with DICOM files of a CT or (3D) MR brain scan as input and then
# aligns that scan with a reference volume, such as the MNI brain atlas.
#
# The Anterior Commissure - Posterior Commissure (ACPC) line has been adopted as a standard in
# neuroimaging as a reference plane for axial imaging. Most atlases are aligned with the ACPC
# line and therefore this script should yield image volumes aligned to the ACPC line. Hence the
# name of the script.
#
# The ACPC line is similar to the orbitomeatal line used as a common reference plane in CT, which
# is about 9° steeper than the ACPC line. Aligning both CT and MR scans to the ACPC line should
# yield image volumes, which are easily comparable longitudinally and between modalities.
#
# Especially interesting for CT scans is the option to automatically generate mean slabs. By
# default, mean slabs of 5 mm thickness are generated for CT scans. When generating the slabs,
# the top non-air slice of the volume is identified and used as a starting point for the mean slabs.
#
# The aligned scans will be automatically exported back to the PACS.
#
# Please run ./fatbACPC.bash -h for usage information.
# See setup.fatbACPC.bash (and also setup.brainstem.bash) for configuration options.
# Check README for requirements.
#
# Version history:
# 2018-09-13 - v0.1 - Initial version
# 2019-02-26 - v0.2 - Split into "fatbACPC" and base functions "brainstem"
#
# Authors:
# - Christian Rubbert <christian.rubbert@med.uni-duesseldorf.de>
# - Julian Caspers <julian.caspers@med.uni-duesseldorf.de>
#


### Acknowledgements
##############################################################################
#
# This script is based on a template by BASH3 Boilerplate v2.3.0
# http://bash3boilerplate.sh/#authors
#
# The BASH3 Boilerplate is under the MIT License (MIT) and is
# Copyright (c) 2013 Kevin van Zonneveld and contributors

### Handle errors
##############################################################################
set -o pipefail

### Command line options
##############################################################################

# shellcheck disable=SC2034
read -r -d '' __usage <<-'EOF' || true # exits non-zero when EOF encountered
  -i --input [arg]    Directory containing the DICOM input files. Required.
  -k --keep-workdir   After running, copy the temporary work directory into the input directory.
  -c --cleanup        After running, empty the source directory (reference DICOM, translation matrices and logs are kept).
  -t --total-cleanup  After running, delete the source directory.
  -n --no-pacs        Do not send the results to the PACS.
  -v                  Enable verbose mode, print script as it is executed.
  -d --debug          Enables debug mode.
  -h --help           This page.
EOF

# shellcheck disable=SC2034
read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 This scripts takes a directory with DICOM files of a CT or MRI brain scan and
 applies linear transformations to align the scan with a standard template, and
 therefore the Anterior Commissure - Posterior Commissure (ACPC) line.
EOF

# shellcheck source=b3bp.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tools/b3bp.bash"

# Set version
version_acpc=$(cd "${__dir}" && git describe --always)

# Set UID prefix
prefixUID=11

### Signal trapping and backtracing
##############################################################################

function __b3bp_cleanup_before_exit {
  # Delete the temporary workdir, if necessary
  if { [[ ! "${arg_k:?}" = "1" ]] || [[ "${arg_t:?}" = "1" ]]; } && [[ "${workdir:-}" ]]; then
    rm -rf "${workdir}"
    info "Removed temporary workdir ${workdir}"
  fi
  # Delete the source dir, if necessary
  if [[ "${arg_t:?}" = "1" ]] && [[ "${source_dir:-}" ]]; then
    rm -rf "${source_dir}"
    info "Removed source dir ${source_dir}"
  fi
}
trap __b3bp_cleanup_before_exit EXIT

# requires `set -o errtrace`
function __b3bp_err_report {
    local error_code
    error_code=${?}
    # shellcheck disable=SC2154
    error "Error in ${__file} in function ${1} on line ${2}"
    exit ${error_code}
}

# Uncomment the following line for always providing an error backtrace
# trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR


### Command-line argument switches
##############################################################################

# debug mode
if [[ "${arg_d:?}" = "1" ]]; then
  set -o xtrace
  LOG_LEVEL="4"
  # Enable error backtracing
  trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR
fi

# verbose mode
if [[ "${arg_v:?}" = "1" ]]; then
  set -o verbose
fi

# help mode
if [[ "${arg_h:?}" = "1" ]]; then
  # Help exists with code 1
  help "Help using ${0}"
fi


### Validation. Error out if the things required for your script are not present
##############################################################################

[[ "${arg_i:-}" ]]     || help  "Setting a directory with -i or --input is required"
[[ "${LOG_LEVEL:-}" ]] || error "Cannot continue without LOG_LEVEL."

# Check for setup.acpc.bash, then source it
if [[ ! -f "${__dir}/setup.fatbACPC.bash" ]]; then
  error "\"${__dir}/setup.fatbACPC.bash\" does not exist."
else
  # shellcheck source=setup.fatbACPC.bash
  source "${__dir}/setup.fatbACPC.bash"
fi

# Check if the input/source directory exists
if [[ ! -d "${arg_i}" ]]; then
  error "\"${arg_i}\" is not a directory or does not exist."
fi 

# Get absolute path of the input directory (just in case) and exit if directory is empty
source_dir=$(realpath "${arg_i}")
if [[ "x"$(ls -1A "${source_dir}") = "x" ]]; then
  error "Directory \"${source_dir}\" is empty."
fi 


### Source the necessary functions
##############################################################################

# shellcheck source=../brainstem/tools/bash/getDCMTag.bash
source "${__dir}/../../tools/bash/getDCMTag.bash"
# shellcheck source=../brainstem/tools/bash/convertDCM2NII.bash
source "${__dir}/../../tools/bash/convertDCM2NII.bash"
# shellcheck source=../brainstem/tools/bash/convertNII2DCM.bash
source "${__dir}/../../tools/bash/convertNII2DCM.bash"
# shellcheck source=../brainstem/tools/bash/copyDCMTags.bash
source "${__dir}/../../tools/bash/copyDCMTags.bash"
# shellcheck source=../brainstem/tools/bash/sendDCM.bash
source "${__dir}/../../tools/bash/sendDCM.bash"

# shellcheck source=bash/tools/acpcAlignment.bash
source "${__dir}/tools/bash/acpcAlignment.bash"
# shellcheck source=bash/tools/meanSlab.bash
source "${__dir}/tools/bash/meanSlab.bash"


### Runtime
##############################################################################

info "Starting fully automatic tilting of brainscans to Anterior Commissure - Posterior Commissure line (fatbACPC):"
info "  version: ${version_acpc}"
info "  source_dir: ${source_dir}"

# Create the temporary workdir
workdir=$(TMPDIR="${tmpdir}" mktemp --directory -t "${__base}-XXXXXX")
info "  workdir: ${workdir}"

# When the workdir will be kept, do compress intermediary files, otherwise don't
if [[ "${arg_k:?}" = "1" ]]; then
  info "  FSLOUTPUTTYPE: NIFTI_GZ (for space, since the workdir will be kept)"
  export FSLOUTPUTTYPE="NIFTI_GZ"
else
  info "  FSLOUTPUTTYPE: NIFTI (for speed, since the workdir will be discarded)"
  export FSLOUTPUTTYPE="NIFTI"
fi

# Copy all DICOM files, except for files which are of the modality presentation
# state (PR) or a residual ref_dcm.dcm, into the workdir and create an index file,
# which contains the ImagePositionPatient DICOM tag (for sorting) and the DICOM file
mkdir "${workdir}/dcm-in"
${dcmftest} "${source_dir}/"* | \
  grep -E "^yes:" | \
  grep -vE "^yes: .*\/ref_dcm.dcm$" | \
  while read bool dcm; do
    modality=$(getDCMTag "${dcm}" "0008,0060" "n")
    if [[ $modality != "PR" ]]; then
      cp "${dcm}" "${workdir}/dcm-in"
      instanceNo=$(LANG=C printf "%03d" $(getDCMTag "${dcm}" "0020,0013" "n"))
      imagePosPatient=$(getDCMTag "${dcm}" "0020,0032" "n")
      echo ${instanceNo}\\"${imagePosPatient}" $dcm >> "${workdir}/index-dcm-in-unsorted"
      # Please ignore the following ", it just fixes vim syntax highlighting after aboves escape
    fi
  done || true
set -u modality
set -u imagePosPatient

# The ImagePositionPatient tag contains information on the x, y and z position in mm of the
# upper left voxel of the image. We sort by the z (axial), then x (sagittal), then y (coronal)
# position to later extract the reference DICOM from the middle of the stack (see below) and
# for properly merging colour maps with the original DICOMs
sort -n -k4,4 -k2,2 -k3,3 -t'\' "${workdir}/index-dcm-in-unsorted" | sed -e 's/\\/ /' > "${workdir}/index-dcm-in"

# Get the middle line (minus two) of the index-dcm-in file as the reference DICOM file
# The reference DICOM file will be used as a source for DICOM tags, when (at the end)
# a DICOM dataset is created to send it back to the PACS. Since reference images might
# be embedded inside the DICOM stack at the beginning, end, or in the middle, we
# choose a DICOM file two off the center. This should yield a reasonable window/center
# setting in case of MR examinations, as well.
dcm_index_lines=$(wc -l "${workdir}/index-dcm-in" | cut -d" " -f1)
dcm_index_lines_middle=$(echo "($dcm_index_lines / 2) - 2" | bc)
ref_dcm=$(sed -n "${dcm_index_lines_middle},${dcm_index_lines_middle}p" "${workdir}/index-dcm-in" | cut -d" " -f3)
info "  ref_dcm: ${ref_dcm}"

# Get and save the subject's name (for debugging reasons)
getDCMTag "${ref_dcm}" "0010,0010" > "${workdir}/name"

# Get modality type and set modality-specific options
case $(getDCMTag "${ref_dcm}" "0008,0060") in
  "CT")
    intended_slice_thickness=${intended_slice_thickness_ct}
    template=${template_ct}
    ;;
  "MR")
    # Test for T1 or T2
    tr=$(getDCMTag "${ref_dcm}" "0018,0080")
    # ... and choose the appropriate settings/templates
    if [[ $tr > $tr_threshold_t1t2 ]]; then
      intended_slice_thickness=${intended_slice_thickness_t2}
      template=${template_t2}
    else
      intended_slice_thickness=${intended_slice_thickness_t1}
      template=${template_t1}
    fi
    ;;
esac

info "  template: ${template}"
info "  intended_slice_thickness: ${intended_slice_thickness}"

### Step 1: Create NII of original DCM files
mkdir "${workdir}/nii-in"
# convertDCM2NII exports the variable nii, which contains the full path to the converted NII file
if [[ $FSLOUTPUTTYPE == "NIFTI" ]]; then
  # The third parameter to convertDCM2NII intentionally disables the creation of a gzip'ed NII
  convertDCM2NII "${workdir}/dcm-in/" "${workdir}/nii-in" "n" || error "convertDCM2NII failed"
else
  convertDCM2NII "${workdir}/dcm-in/" "${workdir}/nii-in" || error "convertDCM2NII failed"
fi

### Step 2: ACPC alignment
mkdir "${workdir}/acpc"
# acpcAlignment export the variable ACPC_OUT, which is the full path to the result from the operation
acpcAlignment "${nii}" "${workdir}/acpc" "${template}" "center" || error "acpcAlignment failed"

### Optional Step 2b: Generate mean slab
if [[ $intended_slice_thickness -gt 0 ]]; then
  mkdir "${workdir}/acpc/meanSlab"
  # meanSlab exports the variable slice_thickness, which is the slice thickness
  # as close to the intended slice thickness as possible
  meanSlab "${acpc_out}" "${workdir}/acpc/meanSlab" ${intended_slice_thickness} || error "meanSlab failed"
  result=$(realpath "${workdir}/acpc/meanSlab/merged"*.nii*)
else
  slice_thickness=""
  result="${acpc_out}"
fi

### Step 3: Convert NIfTI back to DICOM
mkdir "${workdir}/dcm-out"

info "Prepare convertNII2DCM"
# Get the series number from the reference DICOM and add $base_series_no from setup.fatbACPC.bash
ref_series_no=$(getDCMTag "${ref_dcm}" "0020,0011" "n")
series_no=$(echo "${base_series_no} + ${ref_series_no}" | bc)

# Generate series description
# - "s/[0-9]\.[0-9]\+ //" - Remove slice thickness in the series name (e.g. 2.0)
# - "s/$/ ACPC ${slice_thickness}/" - Append ACPC and the slice thickness
# - "s/\s\+$//" - if there is no meanSlab generated, and therefore no slice
#                 thickness just remove the trailing space
series_description=$(getDCMTag "${ref_dcm}" "0008,103e" | sed -e "s/[0-9]\.[0-9]\+ //" -e "s/$/ ACPC ${slice_thickness}/" -e "s/\s\+$//")
info "    New series description: ${series_description}"

convertNII2DCM "${result}" "${workdir}/dcm-out" ${series_no} "${series_description}" "${ref_dcm}" || error "convertNII2DCM failed"

### Step 4: Modify some more DICOM tags specific to fatbACPC

# Set some version information on this tool
"${dcmodify}" \
  --no-backup \
  --insert "(0008,1090)"="BrainImAccs fatbACPC - Research" \
  --insert "(0018,1020)"="BrainImAccs fatbACPC ${version_acpc}" \
  "${workdir}/dcm-out"/*

# Set slice thickness and gap, if a meanSlab was generated
if [[ $intended_slice_thickness -gt 0 ]]; then
  "${dcmodify}" \
    --no-backup \
    --insert "(0018,0050)"="${slice_thickness}" \
    "${workdir}/dcm-out"/*
else
  # Otherwise, copy the values from the reference DICOM file
  copy_dcm_tags="
    0018,0050
    0018,0088
  "
  copyDCMTags "${ref_dcm}" "${workdir}/dcm-out" "${copy_dcm_tags}"
fi

info "Modified DICOM tags specific to $(basename ${0})"

### Step 5: Send DCM to PACS
if [[ ! "${arg_n:?}" = "1" ]]; then
  sendDCM "${workdir}/dcm-out/" || error "sendDCM failed"
fi

### Step 6: Cleaning up
# Copy reference DICOM file to ref_dcm.dcm and copy translation matrices to the source dir
info "Copying reference DICOM file and translation matrices to source dir"
cp "${ref_dcm}" "${source_dir}/ref_dcm.dcm"
cp "${workdir}/acpc/xfms/"*.mat "${source_dir}/"

# Remove the DICOM files from the source directory, but keep ref_dcm.dcm, translation matrices and log (if it exists)
if [[ "${arg_c:?}" = "1" ]]; then
  if [ -e "${source_dir}/log" ]; then
    info "Removing everything except reference DICOM and log from the source dir."
  else
    info "Removing everything except reference DICOM from the source dir."
  fi
  find "${source_dir}" -type f -not -name 'ref_dcm.dcm' -not -name '*.mat' -not -name 'log' -delete
fi

# Keep or discard the workdir. The exit trap (see __b3bp_cleanup_before_exit) is used to discard the temporary workdir.
if [[ "${arg_k:?}" = "1" ]]; then
  kept_workdir="${source_dir}/$(basename ${BASH_SOURCE[0]})-workdir-$(date -u +'%Y%m%d-%H%M%S-UTC')"
  mv "${workdir}" "${kept_workdir}"
  info "Keeping temporary workdir as ${kept_workdir}"
fi
