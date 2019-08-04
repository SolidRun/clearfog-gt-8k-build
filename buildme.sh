#!/bin/bash

echo "Checking all required tools are installed"
TOOLS="wget tar git make 7z unsquashfs dd mkfs.ext4 parted dtc losetup patch"

for i in $TOOLS; do
	TOOL_PATH=`which $i`
	if [ "x$TOOL_PATH" == "x" ]; then
		echo "Tool $i is not installed"
		exit -1
	fi
done

SUDO=$([ "$UID" = "0" ] && echo "" || echo "sudo ")

ROOTDIR=`pwd`
if [[ ! -d $ROOTDIR/build/toolchain/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu ]]; then
	mkdir -vp $ROOTDIR/build/toolchain
	cd $ROOTDIR/build/toolchain
	wget https://developer.arm.com/-/media/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz
        tar -xvf gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu.tar.xz
fi

export CFLAGS=
export CPPFLAGS=
export CXXFLAGS=

# U-Boot config
export UBOOTDIR=u-boot
export UBOOT_REPO=git://git.denx.de/u-boot.git
export UBOOT_TAG=v2019.07

# Marvell binaries
export BINARIES_BRANCH=binaries-marvell-armada-18.12

# Marvell ATF
export ATF_BRANCH=atf-v1.5-armada-18.12

# Marvell DDR
export MVDDR_BRANCH=mv_ddr-armada-18.12

# Linux kernel
export KERNELDIR=linux
export KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
export KERNEL_BRANCH=linux-5.2.y

# Environment variables
export PATH=$PATH:$ROOTDIR/build/toolchain/gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu/bin
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ATF specific defines
export SCP_BL2=$ROOTDIR/build/bootloader/binaries-marvell/mrvl_scp_bl2.img
export MV_DDR_PATH=$ROOTDIR/build/bootloader/mv-ddr-marvell
export BL33=$ROOTDIR/build/bootloader/$UBOOTDIR/u-boot.bin

# Ubuntu version
export UBUNTU_VER=18.04.2

echo "Downloading boot loader"
cd $ROOTDIR
mkdir -vp build/bootloader
if [[ ! -d $ROOTDIR/build/bootloader/$UBOOTDIR ]]; then
	cd $ROOTDIR/build/bootloader
	git clone $UBOOT_REPO $UBOOTDIR
	cd $UBOOTDIR
	git fetch --tags
	git checkout -b $UBOOT_TAG tags/$UBOOT_TAG
else
        cd $ROOTDIR/build/bootloader/$UBOOTDIR
	git reset
	git checkout .
	git clean -fdx
	git branch -v
fi
for n in $ROOTDIR/patches/u-boot/*.patch; do patch -p1 -i $n; done

echo "Downloading Marvell binaries"
if [[ ! -d $ROOTDIR/build/bootloader/binaries-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone --branch=$BINARIES_BRANCH --depth=1 https://github.com/MarvellEmbeddedProcessors/binaries-marvell
else
	cd $ROOTDIR/build/bootloader/binaries-marvell
	git reset
	git checkout .
	git clean -fdx
        git pull origin $BINARIES_BRANCH
        git branch -v
fi

echo "Downoading Marvell ATF"
if [[ ! -d $ROOTDIR/build/bootloader/atf-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone --branch=$ATF_BRANCH --depth=1 https://github.com/MarvellEmbeddedProcessors/atf-marvell.git
	cd atf-marvell
else
	cd $ROOTDIR/build/bootloader/atf-marvell
	git reset
	git checkout .
	git clean -fdx
	git pull origin $ATF_BRANCH
	git branch -v
fi
for n in $ROOTDIR/patches/atf/*.patch; do patch -p1 -i $n; done

echo "Downloading Marvell DDR"
if [[ ! -d $ROOTDIR/build/bootloader/mv-ddr-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone --branch=$MVDDR_BRANCH https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git
else
	cd $ROOTDIR/build/bootloader/mv-ddr-marvell
	git reset
	git checkout .
	git clean -fdx
	git pull origin $MVDDR_BRANCH
	git branch -v
fi
for n in $ROOTDIR/patches/mv-ddr/*.patch; do patch -p1 -i $n; done

echo "Building U-Boot"
cd $ROOTDIR/build/bootloader/$UBOOTDIR
make clearfog_gt_8k_defconfig
make
if [ $? != 0 ]; then
	echo "Error building u-boot"
	exit -1
fi

echo "Building ATF - MV_DDR_PATH at $MV_DDR_PATH, BL33 at $BL33"
cd $ROOTDIR/build/bootloader/atf-marvell
make USE_COHERENT_MEM=0 LOG_LEVEL=20 WORKAROUND_CVE_2018_3639=0 MV_DDR_PATH=$MV_DDR_PATH PLAT=a80x0_cf_gt_8k all fip
if [ $? != 0 ]; then
	echo "Error building ATF"
	exit -1
fi

echo "Downloading Linux kernel"
if [[ ! -d $ROOTDIR/build/$KERNELDIR ]]; then
	cd $ROOTDIR/build/
	git clone --branch=$KERNEL_BRANCH $KERNEL_REPO $KERNELDIR
	cd $KERNELDIR
else
	cd $ROOTDIR/build/$KERNELDIR
	git reset 
	git checkout .
	git clean -fdx
	git pull origin $KERNEL_BRANCH
	git branch -v
fi
for n in $ROOTDIR/patches/kernel/*.patch; do patch -p1 -i $n; done

echo "Building Linux Kernel"
cd $ROOTDIR/build/$KERNELDIR
make defconfig
./scripts/kconfig/merge_config.sh .config $ROOTDIR/configs/kernel.extra.config
make -j4
if [ $? != 0 ]; then
	echo "Error building kernel"
	exit -1
fi

echo "Downloading Ubuntu Image"
if [[ ! -f $ROOTDIR/build/ubuntu-$UBUNTU_VER-server-arm64.squashfs ]]; then
        cd $ROOTDIR/build
        if [[ ! -f ubuntu-$UBUNTU_VER-server-arm64.iso ]]; then
                wget http://cdimage.ubuntu.com/releases/18.04/release/ubuntu-$UBUNTU_VER-server-arm64.iso
        fi
        7z x ubuntu-$UBUNTU_VER-server-arm64.iso install/filesystem.squashfs
	mv install/filesystem.squashfs ubuntu-$UBUNTU_VER-server-arm64.squashfs
fi

cd $ROOTDIR

echo "Creating partitions and images"
dd if=/dev/zero of=$ROOTDIR/image.img bs=1M count=512
parted --script -a optimal $ROOTDIR/image.img mklabel msdos mkpart primary 4096s 100% set 1 boot on

echo "Filling image with data"
mkdir -pv $ROOTDIR/image
LOOPDEV=`losetup -f`
${SUDO}losetup -o 2097152 $LOOPDEV $ROOTDIR/image.img
${SUDO}mkfs.ext4 $LOOPDEV
${SUDO}mount $LOOPDEV $ROOTDIR/image

echo "Copying filesystem to the image"
${SUDO}unsquashfs -d $ROOTDIR/image/ -f $ROOTDIR/build/ubuntu-$UBUNTU_VER-server-arm64.squashfs

echo "Copying kernel to the image"
cp -av $ROOTDIR/build/$KERNELDIR/arch/arm64/boot/Image $ROOTDIR/image/boot/
cp -av $ROOTDIR/build/$KERNELDIR/arch/arm64/boot/dts/marvell/armada-8040-clearfog-gt-8k.dtb $ROOTDIR/image/boot/
cat > $ROOTDIR/image/boot.txt <<EOF
setenv earlyprintk kpti=0 swiotlb=0 console=ttyS0,115200 root=/dev/mmcblk1p1 net.ifnames=0 biosdevname=0 fsck.mode=auto fsck.repair=yes rootwait ro
load ${devtype} ${devnum} ${kernel_addr_r} /boot/Image
load ${devtype} ${devnum} ${fdt_addr_r} /boot/armada-8040-clearfog-gt-8k.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}
EOF
$ROOTDIR/build/bootloader/$UBOOTDIR/tools/mkimage -A arm64 -T script -O linux -d $ROOTDIR/image/boot.txt $ROOTDIR/image/boot.scr
cd $ROOTDIR/build/$KERNELDIR && make INSTALL_MOD_PATH=$ROOTDIR/image/ INSTALL_MOD_STRIP=1 modules_install
${SUDO}chown -R root:root $ROOTDIR/image/boot $ROOTDIR/image/lib/modules

cd $ROOTDIR/image
${SUDO}patch -p1 -i $ROOTDIR/patches/rootfs/01-fstab.patch
${SUDO}patch -p1 -i $ROOTDIR/patches/rootfs/02-autologin-on-serial-console.patch
cd $ROOTDIR

echo "Finishing..."
${SUDO}umount $ROOTDIR/image
${SUDO}losetup -d $LOOPDEV

echo "Fusing bootloader to the image"
dd if=$ROOTDIR/build/bootloader/atf-marvell/build/a80x0_cf_gt_8k/release/flash-image.bin of=image.img conv=notrunc bs=512 seek=1

echo "Done."
cd $ROOTDIR

