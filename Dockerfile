# Use the latest Ubuntu LTS (24.04) as the base image
FROM ubuntu:24.04

# Disable interactive prompts during package installation
ARG DEBIAN_FRONTEND=noninteractive
# OpenWRT version can be overridden at build time (default: 23.05.3)
ARG OPENWRT_VERSION=23.05.5
ENV OPENWRT_VERSION=${OPENWRT_VERSION}
# Define image builder
ENV IMAGE_BUILDER="openwrt-imagebuilder-${OPENWRT_VERSION}-bcm27xx-bcm2711.Linux-x86_64"

# Install build dependencies and utilities (including yq)
RUN apt-get update && apt-get install -y \
      build-essential \
      libncurses5-dev \
      libncursesw5-dev \
      zlib1g-dev \
      gawk \
      git \
      gettext \
      libssl-dev \
      xsltproc \
      wget \
      unzip \
      python3 \
      python3-setuptools \
      file \
      jq \
 && wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
 && chmod a+x /usr/local/bin/yq \
 && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /build

# Copy the repository contents into the container.
# (Make sure your build context includes your repo files such as packages.yaml, files/, etc.)
COPY . .

# Download and extract the OpenWRT Image Builder
RUN wget https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/bcm27xx/bcm2711/${IMAGE_BUILDER}.tar.xz \
    && tar xJf ${IMAGE_BUILDER}.tar.xz

# Download custom packages defined in packages.yaml
# For any package entry containing an "=" sign, download the file.
RUN mkdir -p custom_packages && \
    for pkg in $(yq e '.[] | .[]' packages.yaml | grep '='); do \
        pkg_name=$(echo "$pkg" | cut -d'=' -f1); \
        pkg_url=$(echo "$pkg" | cut -d'=' -f2-); \
        echo "Downloading custom package: $pkg_name from $pkg_url"; \
        wget -q "$pkg_url" -O custom_packages/$(basename "$pkg_url"); \
    done

# Build OpenWRT image using package lists from packages.yaml
# Combine all package entries from all keys, stripping any URL parts.
RUN packages="$(yq e '.[] | .[]' packages.yaml | sed 's/=.*//' | xargs)" && \
    echo "Building with packages: $packages" && \
    cd ${IMAGE_BUILDER} && \
    [ -d "../files" ] && cp -r ../files ./files || true && \
    [ -d "../custom_packages" ] && cp -r ../custom_packages ./packages || true && \
    echo "src imagebuilder file:packages" >> repositories.conf && \
    sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=256/' .config && \
    sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=10240/' .config && \
    make image PROFILE="rpi-4" PACKAGES="$packages" FILES="files"



# Validate the built images using sha256sum
RUN cd ${IMAGE_BUILDER}/bin/targets/bcm27xx/bcm2711 \
    && sha256sum -c sha256sums

# Prepare release assets by copying images and checksum files into a dedicated folder
RUN mkdir -p release_assets \
    && cp ${IMAGE_BUILDER}/bin/targets/bcm27xx/bcm2711/openwrt-${OPENWRT_VERSION}-bcm27xx-bcm2711-rpi-4-ext4-factory.img.gz release_assets/ \
    && cp ${IMAGE_BUILDER}/bin/targets/bcm27xx/bcm2711/openwrt-${OPENWRT_VERSION}-bcm27xx-bcm2711-rpi-4-ext4-sysupgrade.img.gz release_assets/ \
    && cp ${IMAGE_BUILDER}/bin/targets/bcm27xx/bcm2711/openwrt-${OPENWRT_VERSION}-bcm27xx-bcm2711-rpi-4-squashfs-factory.img.gz release_assets/ \
    && cp ${IMAGE_BUILDER}/bin/targets/bcm27xx/bcm2711/openwrt-${OPENWRT_VERSION}-bcm27xx-bcm2711-rpi-4-squashfs-sysupgrade.img.gz release_assets/ \
    && cp ${IMAGE_BUILDER}/bin/targets/bcm27xx/bcm2711/sha256sums release_assets/

# Default command (for example, list the release assets)
CMD ["bash", "-c", "ls -l release_assets"]
