FROM neurodebian:buster-non-free

MAINTAINER Marius Vach <marius.vach@med.uni-duesseldorf.de>

ARG DEBIAN_FRONTEND="noninteractive"

#
# Set up the base system with dependencies
#
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

RUN set -eux \
  && apt-get update -qq \
  && apt-get -y upgrade \
  && apt-get install -y -q --no-install-recommends \
      apt-utils \
      bzip2 \
      ca-certificates \
      wget \
      locales \
      unzip \
      git \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && dpkg-reconfigure --frontend=noninteractive locales \
  && update-locale LANG="en_US.UTF-8"

#
# dcm2niix source install adapted from NeuroDocker (https://github.com/ReproNim/neurodocker)
#
ENV DCM2NIIX_VERSION v1.0.20210317
ENV PATH /opt/dcm2niix-${DCM2NIIX_VERSION}/bin:$PATH

RUN set -eux \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      cmake \
      g++ \
      gcc \
      git \
      make \
      pigz \
      zlib1g-dev \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && git clone https://github.com/rordenlab/dcm2niix /tmp/dcm2niix \
  && cd /tmp/dcm2niix \
  && git fetch --tags \
  && git checkout ${DCM2NIIX_VERSION} \
  && mkdir /tmp/dcm2niix/build \
  && cd /tmp/dcm2niix/build \
  && cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt/dcm2niix-${DCM2NIIX_VERSION} .. \
  && make \
  && make install \
  && rm -rf /tmp/dcm2niix

#
# FSL install adapted from NeuroDocker (https://github.com/ReproNim/neurodocker)
#
ENV FSL_VERSION 5.0.11
ENV FSLDIR /opt/fsl-${FSL_VERSION}
ENV FSLOUTPUTTYPE NIFTI
ENV FSLMULTIFILEQUIT TRUE
ENV FSLTCLSH /opt/fsl-${FSL_VERSION}/bin/fsltclsh
ENV FSLWISH /opt/fsl-${FSL_VERSION}/bin/fslwish
ENV PATH /opt/fsl-${FSL_VERSION}/bin:$PATH

RUN set -eux \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      bc \
      dc \
      file \
      libfontconfig1 \
      libfreetype6 \
      libgl1-mesa-dev \
      libgl1-mesa-dri \
      libglu1-mesa-dev \
      libgomp1 \
      libice6 \
      libxcursor1 \
      libxft2 \
      libxinerama1 \
      libxrandr2 \
      libxrender1 \
      libxt6 \
      sudo \
      wget \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && mkdir -p /opt/fsl-${FSL_VERSION} \
  && wget \
      --progress=bar:force \
      -O - \
      https://fsl.fmrib.ox.ac.uk/fsldownloads/fsl-${FSL_VERSION}-centos6_64.tar.gz | \
        tar \
          -xz \
          -C /opt/fsl-${FSL_VERSION} \
          --strip-components 1 \
  && bash /opt/fsl-${FSL_VERSION}/etc/fslconf/fslpython_install.sh -f /opt/fsl-${FSL_VERSION}

#
# Install BrainImAccs fatbACPC dependencies
#
RUN set -eux \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      bc \
      dcmtk \
      nifti2dicom \
      parallel \
      python3-pip \
      python3-setuptools \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && pip3 install --no-cache-dir \
      numpy \
      six 

#
# Install BrainSTEM and init the needed submodules
#
ENV BIA_MODULE fatbACPC 

ARG TSTAMP=unknown
RUN set -eux \
  && git clone https://github.com/BrainImAccs/BrainSTEM.git /opt/BrainSTEM \
  && cd /opt/BrainSTEM \
  && git checkout docker-cat12.7-standalone \
  && git submodule update --init modules/${BIA_MODULE} \
  && cd /opt/BrainSTEM/modules/${BIA_MODULE} \ # Need to switch to docker branch if its ready
  && cp \
      /opt/BrainSTEM/setup.brainstem.bash-template \
      /opt/BrainSTEM/setup.brainstem.bash \
  && cp \
      /opt/BrainSTEM/tools/startJob.bash-template \
      /opt/BrainSTEM/tools/startJob.bash \
  && useradd --system --user-group --create-home --uid 999 bia \
  && echo '#!/usr/bin/env bash' >> /opt/entry.bash \
  && echo 'bash /opt/BrainSTEM/incoming/incoming.bash &' >> /opt/entry.bash \
  && echo 'bash /opt/BrainSTEM/received/queue.bash &' >> /opt/entry.bash \
  && echo 'wait' >> /opt/entry.bash \
  && chmod 755 /opt/entry.bash /opt/BrainSTEM/tools/startJob.bash \
  && chown bia:bia /opt/BrainSTEM/incoming /opt/BrainSTEM/received

USER bia

EXPOSE 10105/tcp

ENTRYPOINT ["/opt/entry.bash"]
