# podman  run --privileged --rm docker.io/tonistiigi/binfmt --install all
# buildah build --platform linux/aarch64,linux/amd64 \
#               --layers=true
#               -t dgiebert/elemental:v0.0.6 \
#               --build-arg IMAGE_REPO=dgiebert/elemental \
#               --build-arg IMAGE_TAG=v0.0.6


# Step 1: Build the Operating System
FROM isv/rancher/elemental/stable/teal53/15.4/rancher/elemental-teal/5.3:latest as os

# Used to parse the package source directory (MULTIARCH) -> e.g. linux/arm64
ARG TARGETPLATFORM

# elemental-toolkit essentials
RUN system/immutable-rootfs
RUN system/cos-setup
RUN cloud-config/network
RUN cloud-config/recovery
RUN cloud-config/live
RUN cloud-config/boot-assessment
RUN cloud-config/default-services
RUN cloud-config/upgrade_grub_hooks
RUN system/grub2-config
RUN system/base-dracut-modules

# elemental-toolkit utilities
RUN utils/k9s
RUN utils/nerdctl
RUN toolchain/cosign
RUN selinux/rancher


# Do not copy in but bind mount
RUN --mount=type=bind,source=./packages/,target=/tmp/packages \
        # rpm -ivh \
        #     /tmp/packages/linux/noarch/*.rpm \
        #     /tmp/packages/${TARGETPLATFORM}/*.rpm &&\
        sed -i "s|timeout=10|timeout=1|g" /etc/cos/grub.cfg &&\
        curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true sh - &&\
        rm /usr/local/bin/k3s-killall.sh /usr/local/bin/k3s-uninstall.sh && \
        zypper clean --all

# IMPORTANT: /etc/os-release is used for versioning/upgrade. The
# values here should reflect the tag of the image currently being built
ARG IMAGE_REPO=norepo
ARG IMAGE_TAG=latest
RUN echo "IMAGE_REPO=${IMAGE_REPO}"          > /etc/os-release && \
    echo "IMAGE_TAG=${IMAGE_TAG}"           >> /etc/os-release && \
    echo "IMAGE=${IMAGE_REPO}:${IMAGE_TAG}" >> /etc/os-release

# Step 2: Build the ISO
FROM registry.opensuse.org/isv/rancher/elemental/stable/teal53/15.4/rancher/elemental-builder-image/5.3:latest AS builder

# Used to write multiple isos (MULTIARCH) -> e.g. arm64
ARG TARGETARCH

WORKDIR /iso
COPY --from=os / rootfs

RUN --mount=type=bind,source=./output/,target=/output,rw \
        elemental build-iso \
            dir:rootfs \
            --bootloader-in-rootfs \
            --squash-no-compression \
            -o /output/tmp -n "elemental-teal.${TARGETARCH}"

RUN --mount=type=bind,source=./output/,target=/output,rw \
        elemental build-disk \
            --arch x86_64
            -o /output/tmp -n "elemental-teal.${TARGETARCH}"