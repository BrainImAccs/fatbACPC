#!/usr/bin/env python
#
# This script ...
# It uses functions from fslpy, which are based on the following two files:
#
# https://git.fmrib.ox.ac.uk/ndcn0236/fslpy/blob/88d3ca938247ea07125eb167420aa913298d13e0/fsl/utils/transform.py
#
# The functions used are: ...
#
# Those fules/functions are under the following license:
# 
###
#
# Copyright 2016-2017 University of Oxford, Oxford, UK.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Paul McCarthy <pauldmccarthy@gmail.com>
#
###
#
# The main function is our wrapper around the extracted fslpy functions.
#

import numpy as np
import math
import sys, getopt

def compose(scales, offsets, rotations, origin=None):
    """Compose a transformation matrix out of the given scales, offsets
    and axis rotations.

    :arg scales:    Sequence of three scale values.

    :arg offsets:   Sequence of three offset values.

    :arg rotations: Sequence of three rotation values, in radians, or
                    a rotation matrix of shape ``(3, 3)``.

    :arg origin:    Origin of rotation - must be scaled by the ``scales``.
                    If not provided, the rotation origin is ``(0, 0, 0)``.
    """

    preRotate  = np.eye(4)
    postRotate = np.eye(4)

    rotations = np.array(rotations)

    if rotations.shape == (3,):
        rotations = axisAnglesToRotMat(*rotations)

    if origin is not None:
        preRotate[ 0, 3] = -origin[0]
        preRotate[ 1, 3] = -origin[1]
        preRotate[ 2, 3] = -origin[2]
        postRotate[0, 3] =  origin[0]
        postRotate[1, 3] =  origin[1]
        postRotate[2, 3] =  origin[2]

    scale  = np.eye(4, dtype=np.float64)
    offset = np.eye(4, dtype=np.float64)
    rotate = np.eye(4, dtype=np.float64)

    scale[  0,  0] = scales[ 0]
    scale[  1,  1] = scales[ 1]
    scale[  2,  2] = scales[ 2]
    offset[ 0,  3] = offsets[0]
    offset[ 1,  3] = offsets[1]
    offset[ 2,  3] = offsets[2]

    rotate[:3, :3] = rotations

    return concat(offset, postRotate, rotate, preRotate, scale)

def rotMatToAffine(rotmat, origin=None):
    """Convenience function which encodes the given ``(3, 3)`` rotation
    matrix into a ``(4, 4)`` affine.
    """
    return compose([1, 1, 1], [0, 0, 0], rotmat, origin)

def concat(*xforms):
    """Combines the given matrices (returns the dot product)."""

    result = xforms[0]

    for i in range(1, len(xforms)):
        result = np.dot(result, xforms[i])

    return result

def axisAnglesToRotMat(xrot, yrot, zrot):
    """Constructs a ``(3, 3)`` rotation matrix from the given angles, which
    must be specified in radians.
    """

    xmat = np.eye(3)
    ymat = np.eye(3)
    zmat = np.eye(3)

    xmat[1, 1] =  np.cos(xrot)
    xmat[1, 2] = -np.sin(xrot)
    xmat[2, 1] =  np.sin(xrot)
    xmat[2, 2] =  np.cos(xrot)

    ymat[0, 0] =  np.cos(yrot)
    ymat[0, 2] =  np.sin(yrot)
    ymat[2, 0] = -np.sin(yrot)
    ymat[2, 2] =  np.cos(yrot)

    zmat[0, 0] =  np.cos(zrot)
    zmat[0, 1] = -np.sin(zrot)
    zmat[1, 0] =  np.sin(zrot)
    zmat[1, 1] =  np.cos(zrot)

    return concat(zmat, ymat, xmat)

def main(argv):
  xrot = ''
  yrot = ''
  zrot = ''

  try:
    opts, args = getopt.getopt(argv, "hx:y:z:", ["xrot=", "yrot=", "zrot="])
  except getopt.GetoptError:
    print(sys.argv[0], '--xrot=<x-rotation> --yrot=<y-rotation> --zrot=<z-rotation>')
    sys.exit(2)
  for opt, arg in opts:
    if opt == '-h':
       print(sys.argv[0], '--xrot=<x-rotation> --yrot=<y-rotation> --zrot=<z-rotation>')
       sys.exit()
    elif opt in ("-x", "--xrot"):
       xrot = math.radians(int(arg))
    elif opt in ("-y", "--yrot"):
       yrot = math.radians(int(arg))
    elif opt in ("-z", "--zrot"):
       zrot = math.radians(int(arg))

  rotMat = axisAnglesToRotMat(xrot, yrot, zrot)
  affineMat = rotMatToAffine(rotMat)

  #print(affineMat)
  print('\n'.join([''.join(['{:4} '.format(item) for item in row]) for row in affineMat]))

if __name__ == "__main__":
   main(sys.argv[1:])
