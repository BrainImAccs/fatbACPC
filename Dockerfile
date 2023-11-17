ARG BIA_MODULE=fatbACPC

ARG DCM2NIIX_VERSION=v1.0.20210317

# ---- Start of the dcm2niix build stage ----
#
# dcm2niix source install adapted from NeuroDocker (https://github.com/ReproNim/neurodocker)
#
FROM neurodebian:bullseye-non-free AS dcm2niix-builder

ARG DCM2NIIX_VERSION
ENV DCM2NIIX_VERSION=${DCM2NIIX_VERSION}

RUN set -eux \
  && echo Building dcm2niix ${DCM2NIIX_VERSION} \
  && apt-get update -qq \
  && apt-get install -y -q --no-install-recommends \
      ca-certificates \
      cmake \
      g++ \
      gcc \
      git \
      make \
      pigz \
      zlib1g-dev \
  && git clone https://github.com/rordenlab/dcm2niix /tmp/dcm2niix \
  && cd /tmp/dcm2niix \
  && git fetch --tags \
  && git checkout ${DCM2NIIX_VERSION} \
  && mkdir /tmp/dcm2niix/build \
  && cd /tmp/dcm2niix/build \
  && cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt/dcm2niix .. \
  && make \
  && make install
# ---- End of the dcm2niix build stage ----

# Following https://micromamba-docker.readthedocs.io/en/latest/advanced_usage.html#adding-micromamba-to-an-existing-docker-image
# bring in the micromamba image so we can copy files from it
FROM mambaorg/micromamba:1.5.3 as micromamba

# ---- Start of the main image ----

FROM neurodebian:bullseye-non-free
LABEL maintainer="Christian Rubbert <christian.rubbert@med.uni-duesseldorf.de>"
ARG DEBIAN_FRONTEND="noninteractive"

#
# Set up the base system with dependencies
#
RUN set -eux \
  && apt-get update -qq \
  && apt-get -y upgrade \
  && apt-get install -y -q --no-install-recommends \
      apt-utils \
      bzip2 \
      ca-certificates \
      iproute2 \
      wget \
      locales \
      unzip \
      git \
      dcmtk=3.6.5-1 \
      nifti2dicom=0.4.11-3 \
      parallel \
      libjpeg-dev \
      bc \
  && apt-get clean \
  && rm -rf /tmp/hsperfdata* /var/*/apt/*/partial /var/lib/apt/lists/* /var/log/apt/term* \
  && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && dpkg-reconfigure --frontend=noninteractive locales \
  && update-locale LANG="en_US.UTF-8"

ENV LANGUAGE en_US
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

#
# Install dcm2niix
#
COPY --from=dcm2niix-builder /opt/dcm2niix /opt/dcm2niix
ENV PATH /opt/dcm2niix/bin:$PATH

# Following https://micromamba-docker.readthedocs.io/en/latest/advanced_usage.html#adding-micromamba-to-an-existing-docker-image
# if your image defaults to a non-root user, then you may want to make the
# next 3 ARG commands match the values in your image. You can get the values
# by running: docker run --rm -it my/image id -a

ARG MAMBA_USER=bia
ARG MAMBA_USER_ID=999
ARG MAMBA_USER_GID=999
ENV MAMBA_USER $MAMBA_USER
ENV MAMBA_ROOT_PREFIX "/opt/conda"
ENV MAMBA_EXE "/bin/micromamba"

ENV FSLDIR ${MAMBA_ROOT_PREFIX}
ENV FSLOUTPUTTYPE NIFTI
ENV FSLMULTIFILEQUIT TRUE
ENV PATH ${FSLDIR}/bin:$PATH

COPY --from=micromamba "$MAMBA_EXE" "$MAMBA_EXE"
COPY --from=micromamba /usr/local/bin/_activate_current_env.sh /usr/local/bin/_activate_current_env.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_shell.sh /usr/local/bin/_dockerfile_shell.sh
COPY --from=micromamba /usr/local/bin/_entrypoint.sh /usr/local/bin/_entrypoint.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_initialize_user_accounts.sh /usr/local/bin/_dockerfile_initialize_user_accounts.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_setup_root_prefix.sh /usr/local/bin/_dockerfile_setup_root_prefix.sh

COPY --chown=$MAMBA_USER_ID:$MAMBA_USER_GID . /opt/bia

ENV FSL_CONDA_CHANNEL="https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/public"

RUN set -eux \
  && /usr/local/bin/_dockerfile_initialize_user_accounts.sh \
  && /usr/local/bin/_dockerfile_setup_root_prefix.sh \
  && micromamba install --yes --name base --channel $FSL_CONDA_CHANNEL \
    fsl-avwutils=2209.2 \
    fsl-miscmaths=2203.2 \
    fsl-flirt=2111.2 \
    fsl-bet2=2111.5 \
    nibabel=5.1.0 \
    pydicom=2.4.3 \
    matplotlib=3.8.0 \
    pillow=10.0.1 \
    colorcet=3.0.1 \
    --channel conda-forge \
  && micromamba clean --all --yes

USER bia

ARG BIA_MODULE
ENV BIA_MODULE=${BIA_MODULE}
ARG BIA_TSTAMP=${BIA_TSTAMP:-unknown}

RUN set -eux \
  && cp \
      /opt/bia/setup.${BIA_MODULE}.bash-template \
      /opt/bia/setup.${BIA_MODULE}.bash \
  && cat /opt/bia/BrainSTEM/setup.brainstem.bash-template | \
      sed \
        -e "s%^FSLDIR=/path/to/fsl-.*%FSLDIR=${FSLDIR}%" \
      > /opt/bia/BrainSTEM/setup.brainstem.bash \
  && cp \
      /opt/bia/BrainSTEM/tools/startJob.bash-template \
      /opt/bia/BrainSTEM/tools/startJob.bash \
  && chmod 755 /opt/bia/BrainSTEM/tools/startJob.bash \
  && git config --global --add safe.directory /opt/bia \
  && (cd /opt/bia && git describe --always) >> /opt/bia/version \
  && rm -rf /opt/bia/.git

EXPOSE 10104/tcp

SHELL ["/usr/local/bin/_dockerfile_shell.sh"]
ENTRYPOINT ["/usr/local/bin/_entrypoint.sh", "/opt/bia/tools/bash/docker_entry_point.bash"]