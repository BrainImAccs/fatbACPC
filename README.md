# Brain Imaging Accesosoires: Fully automatic tilting of brainscans to ACPC (fatbACPC)

Everyday CT or MR examinations are supposed to be acquired in the same fashion, but slight deviations (e.g. due to subject/patient movement, differences in planning standards for MR and CT, or improper planning) may result in not easily comparable images. The fully automatic tilting of brainscans to Anterior Commissure - Posterior Commissure (fatbACPC) tool is meant to align CT and MR scans to the [ACPC](https://radiopaedia.org/articles/anterior-commissure-posterior-commissure-line) line to yield easily comparable images.

fatbACPC depends on [brainstem](https://github.com/brainimaccs/brainstem) to receive and handle DICOM files from the Picture Archiving and Communication System (PACS) or modalities, process the scans in a parallel fashion and then export the results back to the PACS.

# Details

The fatbACPC script takes a directory with DICOM files of a CT or (3D) MR brain scan as input and then aligns that scan with a reference volume, such as the MNI brain atlas.

The [Anterior Commissure - Posterior Commissure (ACPC) line](https://radiopaedia.org/articles/anterior-commissure-posterior-commissure-line) has been adopted as a standard in neuroimaging as a reference plane for axial imaging. Most atlases are aligned with the ACPC line and therefore this script should yield image volumes aligned to the ACPC line. Hence the name of the script.

![Screenshot of the MNI ICBM 2009c Nonlinear Symmetric T1 template highlighting the ACPC line](img/mni_icbm152_t1_tal_nlin_asym_09c_acpc.png "Screenshot of the MNI ICBM 2009c Nonlinear Symmetric T1 template highlighting the ACPC line")
![Screenshot of the CT template from the Clinical toolbox for SPM 8/2014 highlighting the ACPC line](img/scct_unsmooth_acpc.png "Screenshot of the CT template from the Clinical toolbox for SPM 8/2014 highlighting the ACPC line")

The ACPC line is similar to the orbitomeatal line used as a common reference plane in CT, which is about 9° steeper than the ACPC line. Aligning both CT and MR scans to the ACPC line should yield image volumes, which are easily comparable longitudinally and between modalities.

Especially interesting for CT scans is the option to automatically generate mean slabs. By default, mean slabs of 5 mm thickness are generated for CT scans. When generating the slabs, an algorithm finds the top non-air slice in the volume and starts the creation of slabs with that slice.

A simple check for a mis-registration is in place. If rotation around one axis is more than 45°, we assume a mis-registration happened and try to realign the image volume after skull stripping. FSL's skull stripping might introduce it's own set of artifacts in CT, therefore, we apply it as "rescue attempt" only.

The aligned scans will be automatically exported back to the PACS.

Options to `fatbACPC.bash`:

```
 -i --input [arg]    Directory containing the DICOM input files. Required.
 -k --keep-workdir   After running, copy the temporary work directory into the input directory.
 -c --cleanup        After running, empty the source directory (reference DICOM and translation matrix are kept)
 -p --no-pacs        Do not send the results to the PACS.
 -v                  Enable verbose mode, print script as it is executed.
 -d --debug          Enables debug mode.
 -h --help           This page.
```

# Installation

## Requirements

We are listing the software versions we used (likely the latest available during development), but we are currently not aware that we rely on any features that are specific to one of the software's versions.

* [brainstem](https://github.com/brainimaccs/brainstem)
* [BASH](https://www.gnu.org/software/bash/), we used v4.4.19(1)
* [bc](https://www.gnu.org/software/bc/), we used 1.07.1
* [FSL](https://fsl.fmrib.ox.ac.uk/), we used v5.0.11
* In the current early state: [Git](https://git-scm.com), we used v2.17.1
* [parallel](https://www.gnu.org/software/parallel/), we used v20180822
* [Python 2 or 3](https://www.python.org), we used v2.7.15
  * [NumPy](http://www.numpy.org) , we used v1.14.5
  * [six](https://pypi.org/project/six/), we used v1.11.0

## Installation

Change to the directory where the brainstem directory resides. fatbACPC and brainstem directories are supposed to be at the same level.

```bash
$ cd /path/to/brainiaccs
$ ls -lah # Make sure, that there is a "brainstem" directory, which contains, well, brainstem
$ git clone https://github.com/brainimaccs/fatbACPC.git
$ cd fatbACPC
```

# Configuration

Copy the setup templates:

```bash
$ cp setup.fatbACPC.bash-template setup.fatbACPC.bash
```

Update the PATH to FSL in `setup.fatbACPC.bash`:

```bash
# Setup FSL
#
export FSLDIR="/path/to/fsl-5.0.11"
```

By default, mean slabs are only generated for CT examinations.

```bash
# Intended slice thickness for DICOM export in millimetres (mm),
# which will be matched as close as possible.
#
# Use -1 to not generate any mean slabs, for example on isometric
# MRI acquisitions.
#
intended_slice_thickness_ct=5
intended_slice_thickness_t1=-1
intended_slice_thickness_t2=-1
```

# Running

Make sure that you [enable fatbACPC in brainstem](https://github.com/brainimaccs/brainstem#assign-jobs-to-queue).

# Debugging

Please see https://github.com/brainimaccs/brainstem#debugging

# Acknowledgements

Please see [templates/README.md](https://github.com/brainimaccs/fatbACPC/blob/master/templates/README.md) for information on the templates.

The main scripts are based on the [BASH3 Boilerplate](http://bash3boilerplate.sh).
