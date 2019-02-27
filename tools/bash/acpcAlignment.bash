#!/usr/bin/env bash
#
# This script aligns a input file in the NIfTI format to a template (also in NIfTI format), optionally centers the aligned image
# (if the dimensions of the template are larger than the dimensions of the input volume) and outputs everything to a directory.
#
# The whole process was inspired from the ACPCAlignment step of the PreFreeSurfer step of the Human Connectome Project's pipeline:
# https://github.com/Washington-University/HCPpipelines/blob/4d9996ba07556f096606f2c594647b87341b896f/PreFreeSurfer/scripts/ACPCAlignment.sh
#

# The following function adjusts the transformation matrix
function doCenter {
  # Original imgae volume in the NIfTI format
  local input_nii="${1}"
  # ACPC-aligned image volume to be centered
  local acpc_out="${2}"
  # The transformation matrix
  local transformation_matrix="${3}"

  # The output will happen in the directory of the original transformation matrix
  local output_dir=$(dirname "${transformation_matrix}")

  # Derive the x- and y-dimensions and pixel sizes from both $input_nii and $acpc_out
  local acpc_dim1=$("${FSLDIR}/bin/fslval" "${acpc_out}" dim1 | bc -l)
  local acpc_pixdim1=$("${FSLDIR}/bin/fslval" "${acpc_out}" pixdim1 | bc -l)
  local ref_dim1=$("${FSLDIR}/bin/fslval" "${input_nii}" dim1 | bc -l)
  local ref_pixdim1=$("${FSLDIR}/bin/fslval" "${input_nii}" pixdim1 | bc -l)

  local acpc_dim2=$("${FSLDIR}/bin/fslval" "${acpc_out}" dim2 | bc -l)
  local acpc_pixdim2=$("${FSLDIR}/bin/fslval" "${acpc_out}" pixdim2 | bc -l)
  local ref_dim2=$("${FSLDIR}/bin/fslval" "${input_nii}" dim2 | bc -l)
  local ref_pixdim2=$("${FSLDIR}/bin/fslval" "${input_nii}" pixdim2 | bc -l)

  # Read the transformation matrix and add an extra translation to center the ACPC-aligned image volume
  #
  # The process is described in:
  # https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FLIRT/FAQ#Can_I_register_to_an_image_but_use_higher.2Flower_resolution_.28voxel_size.29.3F
  # 
  #   "Note that when changing the FOV rather than the voxel size, the bottom left corner remains fixed.
  #    Hence, resampling to a smaller FOV will tend to cut-off the portions of the image with large x, y
  #    or z coordinates (near the right/top). In order to resample to a smaller FOV but keep say the
  #    Centre of Volume (COV) in the centre of both images it is necessary to add an extra translation
  #    to the transformation file. This can be done by adding the appropriate offsets (in mm) to the
  #    values in the right hand column (first row is x, second is y, third is z) of the transformation
  #    (.mat) file - which is in plain text. The appropriate offset to keep the COV constant is half of
  #    the difference in the respective FOVs (in mm)."
  #
  head -n1 "${transformation_matrix}" | while read one two three four; do
    echo -n "$one $two $three " > "${output_dir}/acpc-center.mat"
    echo "$four + ((($ref_dim1 * $ref_pixdim1) - ($acpc_dim1 * $acpc_pixdim1)) / 2)" | bc -l >> "${output_dir}/acpc-center.mat"
  done

  head -n2 "${transformation_matrix}" | tail -n1 | while read one two three four; do
    echo -n "$one $two $three " >> "${output_dir}/acpc-center.mat"
    echo "$four + ((($ref_dim2 * $ref_pixdim2) - ($acpc_dim2 * $acpc_pixdim2)) / 2)" | bc -l >> "${output_dir}/acpc-center.mat"
  done

  tail -n2 "${transformation_matrix}" >> "${output_dir}/acpc-center.mat"
}

function doFlirt {
  # The input image volume in the NIfTI format
  local robustroi="${1}"
  # Output directory
  local output_dir="${2}"
  # The template to align the $input_nii to
  local template="${3}"

  info "  doFlirt start"

  # Register the cropped image volume to the defined template volume with 12 degrees of freedom (DOF)
  # https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FLIRT/FAQ
  info "    flirt start"
  ${FSLDIR}/bin/flirt \
    -interp spline \
    -in "${robustroi}" \
    -ref "${template}" \
    -omat "${output_dir}/roi2std.mat" \
    -out "${output_dir}/acpc_final.nii.gz" \
    -searchrx -30 30 -searchry -30 30 -searchrz -30 30
  info "    flirt done"

  # Concatenate the steps to get the full transformation from full FOV to template space
  info "    convert_xfm start"
  ${FSLDIR}/bin/convert_xfm \
    -omat "${output_dir}/full2std.mat" \
    -concat "${output_dir}/roi2std.mat" \
    "${output_dir}/full2roi.mat"
  info "    convert_xfm done"

  # Derive a 6 DOF approximation ACPC alignment (AC, ACPC line, and hemispheric plane)
  info "    aff2rigid start"
  if [ ! -d "${output_dir}/xfms" ]; then
    mkdir "${output_dir}/xfms"
  fi
  ${FSLDIR}/bin/aff2rigid \
    "${output_dir}/full2std.mat" \
    "${output_dir}/xfms/acpc-aff2rigid.mat"
  info "    aff2rigid done"
}

function acpcAlignment {
  # The input image volume in the NIfTI format
  local input_nii="${1}"
  # Output directory
  local output_dir="${2}"
  # The template to align the $input_nii to
  local template="${3}"
  # Optionally center the $input_nii image volume, if the template dimensions are larger than the ${input_nii}'s dimensions
  local do_center="${4:-}"

  info "acpcAlignment start"

  # Crop the field of the view (FoV), creating a region of interest (ROI) from the brain
  # The estimate of 150 mm brain diameter is taken from the Human Connectome Project's PreFreeSurfer pipeline
  info "  robustfov start"
  ${FSLDIR}/bin/robustfov \
    -i "${input_nii}" \
    -m "${output_dir}/roi2full.mat" \
    -r "${output_dir}/robustroi.nii.gz" \
    -b 150 >/dev/null
  info "  robustfov done"

  # Invert the matrix (to get the steps from full FoV to ROI)
  info "  convert_xfm start"
  ${FSLDIR}/bin/convert_xfm \
    -omat "${output_dir}/full2roi.mat" \
    -inverse "${output_dir}/roi2full.mat"
  info "  convert_xfm done"

  # Start FLIRT registration process
  doFlirt "${output_dir}/robustroi.nii.gz" "${output_dir}" "${template}"

  local degrees=$(/usr/bin/env python "${__dir}/tools/python/decompose.py" --xform="${output_dir}/xfms/acpc-aff2rigid.mat")
  local deg1=$(echo $degrees | cut -d' ' -f1)
  local deg2=$(echo $degrees | cut -d' ' -f2)
  local deg3=$(echo $degrees | cut -d' ' -f3)
  info "    Rotations (°): ${degrees}"

  # Check if one of the axis was rotated more than 45° - which usually is the case when a volume was mis-registered
  # If true, perform rescue
  local threshold_misregistration=45
  if \
    [[ $(echo "${deg1} > ${threshold_misregistration} || (${deg1} * -1) > ${threshold_misregistration}" | bc -l) -eq 1 ]] || \
    [[ $(echo "${deg2} > ${threshold_misregistration} || (${deg2} * -1) > ${threshold_misregistration}" | bc -l) -eq 1 ]] || \
    [[ $(echo "${deg3} > ${threshold_misregistration} || (${deg3} * -1) > ${threshold_misregistration}" | bc -l) -eq 1 ]];
  then
    # Start the brain extraction for more robust alignment
    warning "      Mis-registration likely, initiating rescue"

    # Perform a brain extraction.
    # The idea is get a volume with mostly brain (this is may not be as robust on CTs)
    info "      bet2 start"
    ${FSLDIR}/bin/bet2 \
      "${output_dir}/robustroi.nii.gz" \
      "${output_dir}/robustroi-bet2.nii.gz"
    info "      bet2 done"

    # Restart FLIRT registration using the brain-extracted volume
    doFlirt "${output_dir}/robustroi-bet2.nii.gz" "${output_dir}" "${template}"
    local degrees=$(/usr/bin/env python "${__dir}/tools/python/decompose.py" --xform="${output_dir}/xfms/acpc-aff2rigid.mat")
    info "    Rotations (°): ${degrees}"
  fi

  # Derive the maximum z-dimension of the image volume from the translation matrix, which might be larger
  # than the input volume's z-dimension after translation
  local ref_dim1=$("${FSLDIR}/bin/fslval" "${input_nii}" dim1 | bc -l)
  local ref_dim2=$("${FSLDIR}/bin/fslval" "${input_nii}" dim2 | bc -l)
  local ref_dim3=$("${FSLDIR}/bin/fslval" "${input_nii}" dim3 | bc -l)
  local axisBounds=$(/usr/bin/env python "${__dir}/tools/python/axisBounds.py" --dim1=${ref_dim1} --dim2=${ref_dim2} --dim3=${ref_dim3} --xform="${output_dir}/xfms/acpc-aff2rigid.mat")
  info "    Dim3 (z-height) after aff2rigid: ${axisBounds}"
  local new_dim3=$(echo ${axisBounds} | sed -e 's/.* = //')

  # Using the input image volume as a template, create a new, empty image volume with an adjusted z-dimension
  "${FSLDIR}/bin/fslhd" -x "${input_nii}" | \
    sed -e "s/nz = '$ref_dim3'/nz = '$new_dim3'/" | \
    "${FSLDIR}/bin/fslcreatehd" - "${output_dir}/larger_zdim.nii.gz"

  # Optional: Adjust the transformation matrix to center the ACPC-aligned image volume in the new dimensions
  if [[ "${do_center}" = "center" ]]; then
    doCenter "${input_nii}" "${output_dir}/acpc_final.nii.gz" "${output_dir}/xfms/acpc-aff2rigid.mat"
    premat="${output_dir}/xfms/acpc-center.mat"
  else
    premat="${output_dir}/xfms/acpc-aff2rigid.mat"
  fi

  # Finally apply the transformation matrix to the input image volume to create a resampled, ACPC-aligned image volume
  info "  applywarp start"
  acpc_out="${output_dir}/$(basename ${input_nii} | sed -e 's/\.nii\.gz$/_acpc.nii.gz/')"
  ${FSLDIR}/bin/applywarp \
    --rel \
    --interp=spline \
    -i "${input_nii}" \
    -r "${output_dir}/larger_zdim.nii.gz" \
    --premat="${premat}" \
    -o "${acpc_out}"
  info "  applywarp done"

  # Export the full path and filename to the final ACPC-aligned image volume
  export acpc_out

  info "acpcAlignment done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f acpcAlignment
else
  echo "acpcAlignment is an internal function and cannot be called directly."
  exit 1
fi
