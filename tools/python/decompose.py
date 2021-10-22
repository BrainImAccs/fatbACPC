#!/usr/bin/env python3
#
# This script decomposes the translation matrix and prints the rotations performed in degrees.
# It uses functions from fslpy, which are based on the following two files:
#
# https://git.fmrib.ox.ac.uk/ndcn0236/fslpy/blob/88d3ca938247ea07125eb167420aa913298d13e0/fsl/utils/transform.py
# https://git.fmrib.ox.ac.uk/ndcn0236/fslpy/blob/88d3ca938247ea07125eb167420aa913298d13e0/tests/test_transform.py
#
# The functions used are: readlines, decompose and rotMatToAxisAngles.
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
import numpy.linalg as linalg
import collections
import math

import six

import sys, getopt

def readlines(filename):
    with open(filename, 'rt') as f:
        lines = f.readlines()
        lines = [l.strip()         for l in lines]
        lines = [l                 for l in lines if not l.startswith('#')]
        lines = [l                 for l in lines if l != '']

        # numpy.genfromtxt is busted in python 3.
        # Pass it [str, str, ...], and it complains:
        #
        #   TypeError: must be str or None, not bytes
        #
        # Pass it [bytes, bytes, ...], and it works
        # fine.
        if six.PY3:
            lines = [l.encode('ascii') for l in lines]

    return lines

def decompose(xform, angles=True):
    """Decomposes the given transformation matrix into separate offsets,
    scales, and rotations, according to the algorithm described in:

    Spencer W. Thomas, Decomposing a matrix into simple transformations, pp
    320-323 in *Graphics Gems II*, James Arvo (editor), Academic Press, 1991,
    ISBN: 0120644819.

    It is assumed that the given transform has no perspective components. Any
    shears in the affine are discarded.

    :arg xform:  A ``(4, 4)`` affine transformation matrix.

    :arg angles: If ``True`` (the default), the rotations are returned
                 as axis-angles, in radians. Otherwise, the rotation matrix
                 is returned.

    :returns: The following:

               - A sequence of three scales
               - A sequence of three translations
               - A sequence of three rotations, in radians. Or, if
                 ``angles is False``, a rotation matrix.
    """

    # The inline comments in the code below are taken verbatim from
    # the referenced article, [except for notes in square brackets].

    # The next step is to extract the translations. This is trivial;
    # we find t_x = M_{4,1}, t_y = M_{4,2}, and t_z = M_{4,3}. At this
    # point we are left with a 3*3 matrix M' = M_{1..3,1..3}.
    xform        = xform.T
    translations = xform[ 3, :3]
    xform        = xform[:3, :3]

    M1 = xform[0]
    M2 = xform[1]
    M3 = xform[2]

    # The process of finding the scaling factors and shear parameters
    # is interleaved. First, find s_x = |M'_1|.
    sx = np.sqrt(np.dot(M1, M1))

    # Then, compute an initial value for the xy shear factor,
    # s_xy = M'_1 * M'_2. (this is too large by the y scaling factor).
    sxy = np.dot(M1, M2)

    # The second row of the matrix is made orthogonal to the first by
    # setting M'_2 = M'_2 - s_xy * M'_1.
    M2 = M2 - sxy * M1

    # Then the y scaling factor, s_y, is the length of the modified
    # second row.
    sy = np.sqrt(np.dot(M2, M2))

    # The second row is normalized, and s_xy is divided by s_y to
    # get its final value.
    M2  = M2  / sy
    sxy = sxy / sy

    # The xz and yz shear factors are computed as in the preceding,
    sxz = np.dot(M1, M3)
    syz = np.dot(M2, M3)

    # the third row is made orthogonal to the first two rows,
    M3 = M3 - sxz * M1 - syz * M2

    # the z scaling factor is computed,
    sz = np.sqrt(np.dot(M3, M3))

    # the third row is normalized, and the xz and yz shear factors are
    # rescaled.
    M3  = M3  / sz
    sxz = sxz / sz
    syz = sxz / sz

    # The resulting matrix now is a pure rotation matrix, except that it
    # might still include a scale factor of -1. If the determinant of the
    # matrix is -1, negate the matrix and all three scaling factors. Call
    # the resulting matrix R.
    #
    # [We do things different here - if the rotation matrix has negative
    #  determinant, the flip is encoded in the x scaling factor.]
    R = np.array([M1, M2, M3])
    if linalg.det(R) < 0:
        R[0] = -R[0]
        sx   = -sx

    # Finally, we need to decompose the rotation matrix into a sequence
    # of rotations about the x, y, and z axes. [This is done in the
    # rotMatToAxisAngles function]
    if angles: rotations = rotMatToAxisAngles(R.T)
    else:      rotations = R.T

    return [sx, sy, sz], translations, rotations

def rotMatToAxisAngles(rotmat):
    """Given a ``(3, 3)`` rotation matrix, decomposes the rotations into
    an angle in radians about each axis.
    """

    yrot = np.sqrt(rotmat[0, 0] ** 2 + rotmat[1, 0] ** 2)

    if np.isclose(yrot, 0):
        xrot = np.arctan2(-rotmat[1, 2], rotmat[1, 1])
        yrot = np.arctan2(-rotmat[2, 0], yrot)
        zrot = 0
    else:
        xrot = np.arctan2( rotmat[2, 1], rotmat[2, 2])
        yrot = np.arctan2(-rotmat[2, 0], yrot)
        zrot = np.arctan2( rotmat[1, 0], rotmat[0, 0])

    return [xrot, yrot, zrot]

def main(argv):
  xformFile = ''

  try:
    opts, args = getopt.getopt(argv, "x:", ["xform="])
  except getopt.GetoptError:
    print(sys.argv[0], '--xform=<xform_file>')
    sys.exit(2)
  for opt, arg in opts:
    if opt == '-h':
       print(sys.argv[0], '--xform=<xform_file>')
       sys.exit()
    elif opt in ("-x", "--xform"):
       xformFile = arg

  xform = np.genfromtxt(readlines(xformFile))
  result = decompose(xform=xform)

  # Radians
  # print 'Radians: %.3f, %.3f, %.3f' % (result[2][0], result[2][1], result[2][2])
  # Degrees
  # print 'Degrees: %.3f %.3f %.3f' % (math.degrees(result[2][0]), math.degrees(result[2][1]), math.degrees(result[2][2]))

  print('%.3f %.3f %.3f' % (math.degrees(result[2][0]), math.degrees(result[2][1]), math.degrees(result[2][2])))

if __name__ == "__main__":
   main(sys.argv[1:])
