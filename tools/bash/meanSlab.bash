#!/usr/bin/env bash
#
# Generate mean slabs from a NIfTI image volume, approximating the slab thickness based on the dimensions of
# the input volume. The function exports a variable slice_thickness, which contains the actual slice thickness.
#
# To make the mean slabs more comparable, we always try to begin slab generation with the first non-air-only slice.
#

# The function checkForAir takes a slice number and re-uses some variables local to the "meanSlab" function. It
# checks the minimum value of the central 48 x 48 voxels of a slice. If the minimum is >0, a non-air slice is 
# assumed. 

# Given that MR voxel values are not normalized, this is essentially only used in the context of CT
# Hounsfield units.
#
function checkForAir {
  local slice=$1

  # Create a region of interest (ROI) from the central 48 x 48 voxels of a single slice
  # and save it as a temporary file
  "${FSLDIR}/bin/fslroi" \
    "${input_nii}" \
    "$(dirname ${input_nii})/temp${slice}.nii.gz" \
    $(echo "($ref_dim1 / 2) - 7" | bc) 48 \
    $(echo "($ref_dim2 / 2) - 7" | bc) 48 \
    $slice 1

  # Calculate the minimum value of the voxel values in that ROI
  local center_roi=$("${FSLDIR}/bin/fslstats" \
    "$(dirname ${input_nii})/temp${slice}.nii.gz" \
    -R | \
      cut -d" " -f2
  )
  # Remove the temporary file
  rm "$(dirname ${input_nii})/temp${slice}.nii.gz"

  # If the minimum voxel value is >0, declare that slice SOLID, otherwise AIR
  if [[ $(echo "${center_roi} > 0" | bc -l) -eq 1 ]]; then
    echo "SOLID"
  else
    echo "AIR"
  fi
}
export -f checkForAir

function meanSlab {
  # Input NIfTI file
  local input_nii="${1}"
  # Output directory
  local output_dir="${2}"
  # Intended slice thickness. The resulting slab thickness of this function is supposed to match the intended
  # slice thickness as closely as possible, so that (more) interpolation is not necessary.
  local intended_slice_thickness="${3}"

  info "meanSlab start"

  # Get dimensions of the input NIfTI image volume
  local ref_dim1=$("${FSLDIR}/bin/fslval" "${input_nii}" dim1 | bc)
  local ref_dim2=$("${FSLDIR}/bin/fslval" "${input_nii}" dim2 | bc)
  local ref_dim3=$("${FSLDIR}/bin/fslval" "${input_nii}" dim3 | bc)
  local ref_pixdim3=$("${FSLDIR}/bin/fslval" "${input_nii}" pixdim3 | bc)

  # Find the top non-air slice. Initially, the bottom slice of the image volume is declared SOLID and
  # the top slice is declared AIR. Then, the middle slice between SOLID and AIR is tested for being
  # either SOLID or AIR and the result is saved in a variable. That process is repeated until the last
  # known AIR and SOLID slice are only one slice apart, i.e. the top SOLID slice has been found.
  info "  Finding top non-air slice"
  local ref_slice_top=$ref_dim3
  local lastAir=$ref_dim3
  local lastSolid=1

  # First make sure the top slice is actually AIR - if it is solid, we're done already.
  if [[ $(checkForAir $ref_dim3) == "AIR" ]]; then
    # The maximum number of iterations would test every single slice of the image volume, which will
    # hardly be necessary.
    for cZ in $(seq $ref_dim3 -1 0); do
      # ... therefore, test if the last known AIR and SOLID slice are only one apart, and then break out
      # of the loop, updating a variable outside of the loop with the last known solid slice.
      if [[ $(echo "$lastAir - $lastSolid" | bc) == 1 ]]; then
        ref_slice_top=$lastSolid
        break
      fi

      # Check the slice in the middle between the last known SOLID and AIR slice.
      # Dividing by 1 causes bc to round the whole number, leaving no decimal place.
      checkForAirSlice=$(echo "($lastSolid + (($lastAir - $lastSolid) / 2)) / 1" | bc)

      # Update the last known SOLID or AIR slice accordingly and then carry on with the loop
      if [[ $(checkForAir $checkForAirSlice) == "AIR" ]]; then
        lastAir=$checkForAirSlice
      else
        lastSolid=$checkForAirSlice
      fi
    done
  fi
  info "    Found slice $ref_slice_top of $ref_dim3"

  # Calculate the number of slabs and the number of slices in each slab.
  # (x + 0.5) / 1 is essentially a "ceil() function" for bc
  local number_of_slabs=$(echo "((($ref_slice_top * $ref_pixdim3) / $intended_slice_thickness) + 0.5) / 1" | bc)
  local number_of_slices_in_slab=$(echo "(($ref_slice_top / $number_of_slabs) + 0.5) / 1" | bc)

  # Start generation of slabs
  info "  fslmaths loop start"
  # Slabs are generated from top to bottom
  for cZ in $(seq $(echo "$ref_slice_top - $number_of_slices_in_slab" | bc) $(echo "$number_of_slices_in_slab * -1" | bc) 0); do
    # Use fslmaths to generate the mean slabs. Please note that we are defining a ROI of the slices we want in a slab.
    # fslmaths then sets all voxel values outside of that ROI to zero. Unfortunately, Zmean calculates the mean of
    # the whole volume and not only the ROI. Therefore, we need to multiply the voxel values by the ratio of the
    # number of slices and the number of ROI slices. (Acknowledgements: Matthew Webster and Wolf Zinke from the FSL
    # mailing list).
    #
    # sem from GNU parallel is used to parallelize the generation of slabs.
    LANG=C ${sem} -j+0 "${FSLDIR}/bin/fslmaths" \
      "${input_nii}" \
      -roi 0 $ref_dim1 0 $ref_dim2 $cZ $number_of_slices_in_slab 0 1 \
      -Zmean \
      -mul $(echo "$ref_dim3 / $number_of_slices_in_slab" | bc -l) \
      "${output_dir}/slab_$(LANG=C printf "%07.2f" $cZ).nii.gz"
  done
  # Wait for all slabs to be generated
  LANG=C sem --wait
  info "  fslmaths loop done"

  # Merge the slabs into a single NIfTI
  info "  fslmerge start"
  "${FSLDIR}/bin/fslmerge" \
    -z "${output_dir}/merged.nii.gz" \
    "${output_dir}/slab_"*.nii.gz
  info "  fslmerge done"

  # Export the actual slice thickness, rounded to two decimal places
  export slice_thickness=$(LANG=C printf "%.2f" $(echo "$number_of_slices_in_slab * $ref_pixdim3" | bc))

  info "    Adjusting pixdim3 to ${slice_thickness}"
  # Using the input image volume as a template, create a new, empty image volume with an adjusted z-dimension
  "${FSLDIR}/bin/fslhd" -x "${output_dir}/merged.nii.gz" | \
    sed -e "s/dz = '[0-9\.]\+'/dz = '${slice_thickness}'/" | \
    "${FSLDIR}/bin/fslcreatehd" - "${output_dir}/merged.nii.gz"

  info "meanSlab done"
}

# Export the function to be used when sourced, but do not allow the script to be called directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f meanSlab
else
  echo "meanSlab is an internal function and cannot be called directly."
  exit 1
fi
