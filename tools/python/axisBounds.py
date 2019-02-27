#!/usr/bin/env python
#
# This script returns the z-height after applying a transformation matrix to an image volume.
# It uses functions from fslpy, which are based on the following two files:
#
# https://git.fmrib.ox.ac.uk/ndcn0236/fslpy/blob/88d3ca938247ea07125eb167420aa913298d13e0/fsl/utils/transform.py
# https://git.fmrib.ox.ac.uk/ndcn0236/fslpy/blob/88d3ca938247ea07125eb167420aa913298d13e0/tests/test_transform.py
#
# The functions used are: readlines, _fillPoints, axisBounds and transform.
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
import collections

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

def _fillPoints(p, axes):
    """Used by the :func:`transform` function. Turns the given array p into
    a ``N*3`` array of ``x,y,z`` coordinates. The array p may be a 1D array,
    or an ``N*2`` or ``N*3`` array.
    """

    if not isinstance(p, collections.Iterable): p = [p]

    p = np.array(p)

    if axes is None: return p

    if not isinstance(axes, collections.Iterable): axes = [axes]

    if p.ndim == 1:
        p = p.reshape((len(p), 1))

    if p.ndim != 2:
        raise ValueError('Points array must be either one or two '
                         'dimensions')

    if len(axes) != p.shape[1]:
        raise ValueError('Points array shape does not match specified '
                         'number of axes')

    newp = np.zeros((len(p), 3), dtype=p.dtype)

    for i, ax in enumerate(axes):
        newp[:, ax] = p[:, i]

    return newp

def axisBounds(shape,
               xform,
               axes=None,
               origin='centre',
               boundary='high',
               offset=1e-4):
    """Returns the ``(lo, hi)`` bounds of the specified axis/axes in the
    world coordinate system defined by ``xform``.

    If the ``origin`` parameter is set to  ``centre`` (the default),
    this function assumes that voxel indices correspond to the voxel
    centre. For example, the voxel at ``(4, 5, 6)`` covers the space:

      ``[3.5 - 4.5, 4.5 - 5.5, 5.5 - 6.5]``

    So the bounds of the specified shape extends from the corner at

      ``(-0.5, -0.5, -0.5)``

    to the corner at

      ``(shape[0] - 0.5, shape[1] - 0.5, shape[1] - 0.5)``

    If the ``origin`` parameter is set to ``corner``, this function
    assumes that voxel indices correspond to the voxel corner. In this
    case, a voxel  at ``(4, 5, 6)`` covers the space:

      ``[4 - 5, 5 - 6, 6 - 7]``

    So the bounds of the specified shape extends from the corner at

      ``(0, 0, 0)``

    to the corner at

      ``(shape[0], shape[1], shape[1])``.


    If the ``boundary`` parameter is set to ``high``, the high voxel bounds
    are reduced by a small amount (specified by the ``offset`` parameter)
    before they are transformed to the world coordinate system.  If
    ``boundary`` is set to ``low``, the low bounds are increased by a small
    amount.  The ``boundary`` parameter can also be set to ``'both'``, or
    ``None``. This option is provided so that you can ensure that the
    resulting bounds will always be contained within the image space.

    :arg shape:    The ``(x, y, z)`` shape of the data.

    :arg xform:    Transformation matrix which transforms voxel coordinates
                   to the world coordinate system.

    :arg axes:     The world coordinate system axis bounds to calculate.

    :arg origin:   Either ``'centre'`` (the default) or ``'corner'``.

    :arg boundary: Either ``'high'`` (the default), ``'low'``, ''`both'``,
                   or ``None``.

    :arg offset:   Amount by which the boundary voxel coordinates should be
                   offset. Defaults to ``1e-4``.

    :returns:      A tuple containing the ``(low, high)`` bounds for each
                   requested world coordinate system axis.
    """

    origin = origin.lower()

    # lousy US spelling
    if origin == 'center':
        origin = 'centre'

    if origin not in ('centre', 'corner'):
        raise ValueError('Invalid origin value: {}'.format(origin))
    if boundary not in ('low', 'high', 'both', None):
        raise ValueError('Invalid boundary value: {}'.format(boundary))

    scalar = False

    if axes is None:
        axes = [0, 1, 2]

    elif not isinstance(axes, collections.Iterable):
        scalar = True
        axes   = [axes]

    x, y, z = shape[:3]

    points = np.zeros((8, 3), dtype=np.float32)

    if origin == 'centre':
        x0 = -0.5
        y0 = -0.5
        z0 = -0.5
        x -=  0.5
        y -=  0.5
        z -=  0.5
    else:
        x0 = 0
        y0 = 0
        z0 = 0

    if boundary in ('low', 'both'):
        x0 += offset
        y0 += offset
        z0 += offset

    if boundary in ('high', 'both'):
        x  -= offset
        y  -= offset
        z  -= offset

    points[0, :] = [x0, y0, z0]
    points[1, :] = [x0, y0,  z]
    points[2, :] = [x0,  y, z0]
    points[3, :] = [x0,  y,  z]
    points[4, :] = [x,  y0, z0]
    points[5, :] = [x,  y0,  z]
    points[6, :] = [x,   y, z0]
    points[7, :] = [x,   y,  z]

    tx = transform(points, xform)

    lo = tx[:, axes].min(axis=0)
    hi = tx[:, axes].max(axis=0)

    if scalar: return (lo[0], hi[0])
    else:      return (lo,    hi)


def transform(p, xform, axes=None, vector=False):
    """Transforms the given set of points ``p`` according to the given affine
    transformation ``xform``.


    :arg p:      A sequence or array of points of shape :math:`N \\times  3`.

    :arg xform:  A ``(4, 4)`` affine transformation matrix with which to
                 transform the points in ``p``.

    :arg axes:   If you are only interested in one or two axes, and the source
                 axes are orthogonal to the target axes (see the note below),
                 you may pass in a 1D, ``N*1``, or ``N*2`` array as ``p``, and
                 use this argument to specify which axis/axes that the data in
                 ``p`` correspond to.

    :arg vector: Defaults to ``False``. If ``True``, the points are treated
                 as vectors - the translation component of the transformation
                 is not applied. If you set this flag, you pass in a ``(3, 3)``
                 transformation matrix.

    :returns:    The points in ``p``, transformed by ``xform``, as a ``numpy``
                 array with the same data type as the input.


    .. note:: The ``axes`` argument should only be used if the source
              coordinate system (the points in ``p``) axes are orthogonal
              to the target coordinate system (defined by the ``xform``).

              In other words, you can only use the ``axes`` argument if
              the ``xform`` matrix consists solely of translations and
              scalings.
    """

    p  = _fillPoints(p, axes)
    t  = np.dot(xform[:3, :3], p.T).T

    if not vector:
        t = t + xform[:3, 3]

    if axes is not None:
        t = t[:, axes]

    if t.size == 1: return t[0]
    else:           return t



def main(argv):
  dim1 = ''
  dim2 = ''
  dim3 = ''
  xformFile = ''

  try:
    opts, args = getopt.getopt(argv, "h1:2:3:x:", ["dim1=", "dim2=", "dim3=", "xform="])
  except getopt.GetoptError:
    print(sys.argv[0], '--dim1=<dim1> --dim2=<dim2> --dim3=<dim3> --xform=<xform_file>')
    sys.exit(2)
  for opt, arg in opts:
    if opt == '-h':
       print(sys.argv[0], '--dim1=<dim1> --dim2=<dim2> --dim3=<dim3> --xform=<xform_file>')
       sys.exit()
    elif opt in ("-1", "--dim1"):
       dim1 = int(arg)
    elif opt in ("-2", "--dim2"):
       dim2 = int(arg)
    elif opt in ("-3", "--dim3"):
       dim3 = int(arg)
    elif opt in ("-x", "--xform"):
       xformFile = arg

  xform = np.genfromtxt(readlines(xformFile))
  shape = (dim1, dim2, dim3)
  result = axisBounds(shape, xform, axes = 2, boundary = "both", origin = "centre")

  print('(%s, %s) = %s') % (result[0], result[1], result[1] - result[0])

if __name__ == "__main__":
   main(sys.argv[1:])
