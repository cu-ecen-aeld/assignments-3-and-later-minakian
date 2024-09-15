#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR="/tmp/aeld"
KERNEL_REPO="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
KERNEL_VERSION="v5.15.163"
BUSYBOX_VERSION="1_33_1"
FINDER_APP_DIR="$(realpath $(dirname "$0"))"
ARCH="arm64"
CROSS_COMPILE="aarch64-none-linux-gnu-"

if [ $# -lt 1 ]; then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR="$1"
    echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p "${OUTDIR}"

if [ ! -d "${OUTDIR}" ]; then
    echo "Failed to create the directory ${OUTDIR}"
    exit 1
fi

cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    # Clone only if the repository does not exist.
    echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
    git clone "${KERNEL_REPO}" --depth 1 --single-branch --branch "${KERNEL_VERSION}"
fi

cd "${OUTDIR}/linux-stable"
if [ ! -e "arch/${ARCH}/boot/Image" ]; then
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout "${KERNEL_VERSION}"

    # TODO: Add your kernel build steps here
    # Clean the kernel build tree
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" mrproper

    # Configure for the default ARM64 platform
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig

    # Build All
    make -j$(nproc) ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" all

    # Build the modules
    # make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" modules

    # Build the Device Tree Blobs
    make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" dtbs
fi

# Copy the kernel image to the output directory
echo "Adding the Image in outdir"
cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}"

echo "Creating the staging directory for the root filesystem"
cd "${OUTDIR}"
if [ -d "${OUTDIR}/rootfs" ]; then
    echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm -rf "${OUTDIR}/rootfs"
fi

# TODO: Create necessary base directories
mkdir -p "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr/bin usr/lib usr/sbin var/log

cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/busybox" ]; then
    git clone "git://busybox.net/busybox.git"
    cd busybox
    git checkout "${BUSYBOX_VERSION}"

    # Configure BusyBox
    # Clean the busybox build tree
    make distclean
    # Configure busybox for the target
    make defconfig
else
    cd busybox
fi

# TODO: Make and install BusyBox
make -j$(nproc) ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}"
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" install

# The readelf commands should be executed after BusyBox has been built.
# Moving them to after the BusyBox build and installation.

echo "Library dependencies"
${CROSS_COMPILE}readelf -a busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)

# Create lib and lib64 directories if they don't exist
mkdir -p "${OUTDIR}/rootfs/lib" "${OUTDIR}/rootfs/lib64"

# Copy necessary libraries
sudo cp -a "${SYSROOT}/lib/ld-linux-aarch64.so.1" "${OUTDIR}/rootfs/lib/"
sudo cp -a "${SYSROOT}/lib64/"{libm.so.6,libresolv.so.2,libc.so.6} "${OUTDIR}/rootfs/lib64/"

# TODO: Make device nodes
sudo mknod -m 666 "${OUTDIR}/rootfs/dev/null" c 1 3
sudo mknod -m 622 "${OUTDIR}/rootfs/dev/console" c 5 1

# TODO: Clean and build the writer utility
cd "${FINDER_APP_DIR}"
make clean
make CROSS_COMPILE="${CROSS_COMPILE}"

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
mkdir -p "${OUTDIR}/rootfs/home"
mkdir -p "${OUTDIR}/rootfs/home/conf"
cp "${FINDER_APP_DIR}/autorun-qemu.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/writer" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/finder-test.sh" "${OUTDIR}/rootfs/home/"
cp "${FINDER_APP_DIR}/conf/username.txt" "${OUTDIR}/rootfs/home/conf"
cp "${FINDER_APP_DIR}/conf/assignment.txt" "${OUTDIR}/rootfs/home/conf"

# TODO: Chown the root directory
# Change ownership to root
sudo chown -R root:root "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"
find . | cpio -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"

# TODO: Create initramfs.cpio.gz
gzip -f "${OUTDIR}/initramfs.cpio"
