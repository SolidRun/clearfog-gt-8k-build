#!/bin/bash

ROOTDIR=`pwd`
if [[ ! -d $ROOTDIR/build/toolchain ]]; then
	mkdir -p $ROOTDIR/build/toolchain
	cd $ROOTDIR/build/toolchain
	wget https://releases.linaro.org/components/toolchain/binaries/5.3-2016.05/aarch64-linux-gnu/gcc-linaro-5.3.1-2016.05-x86_64_aarch64-linux-gnu.tar.xz
	tar -xvf gcc-linaro-5.3.1-2016.05-x86_64_aarch64-linux-gnu.tar.xz
fi

export PATH=$PATH:$ROOTDIR/build/toolchain/gcc-linaro-5.3.1-2016.05-x86_64_aarch64-linux-gnu/bin
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
# ATF specific defines
export SCP_BL2=$ROOTDIR/build/bootloader/binaries-marvell/mrvl_scp_bl2_8040.img
export MV_DDR_PATH=$ROOTDIR/build/bootloader/mv-ddr-marvell
export BL33=$ROOTDIR/build/bootloader/u-boot-marvell/u-boot.bin

echo "Building boot loader"
cd $ROOTDIR
mkdir -p build/bootloader
if [[ ! -d $ROOTDIR/build/bootloader/u-boot-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone https://github.com/MarvellEmbeddedProcessors/u-boot-marvell
	cd u-boot-marvell
	git checkout -b u-boot-2017.03-armada-17.10 origin/u-boot-2017.03-armada-17.10
	git am $ROOTDIR/patches/u-boot/*
fi

if [[ ! -d $ROOTDIR/build/bootloader/binaries-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone https://github.com/MarvellEmbeddedProcessors/binaries-marvell
	cd binaries-marvell
	git checkout -b binaries-marvell-armada-17.10 origin/binaries-marvell-armada-17.10
fi
if [[ ! -d $ROOTDIR/build/bootloader/atf-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone https://github.com/MarvellEmbeddedProcessors/atf-marvell.git
	cd atf-marvell
	git checkout -b atf-v1.3-armada-17.10 origin/atf-v1.3-armada-17.10 
	git am $ROOTDIR/patches/atf/0001-plat-marvell-a80x0_cf_gt_8k-soft-links-to-mcbin.patch
fi

if [[ ! -d $ROOTDIR/build/bootloader/mv-ddr-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git
	cd mv-ddr-marvell
	git checkout -b mv_ddr-armada-17.10 origin/mv_ddr-armada-17.10
fi

if [[ ! -d $ROOTDIR/build/linux-marvell ]]; then
	cd $ROOTDIR/build/
	git clone https://github.com/MarvellEmbeddedProcessors/linux-marvell
	cd linux-marvell
	git checkout linux-4.4.52-armada-17.10
	git am $ROOTDIR/patches/kernel/*
fi

echo "Building u-boot"
cd $ROOTDIR/build/bootloader/u-boot-marvell
make solidrun_cf_gt_8k_defconfig
make

if [ $? != 0 ]; then
	echo "Error building u-boot"
	exit -1
fi

echo "Building ATF - MV_DDR_PATH at $MV_DDR_PATH, BL33 at $BL33"
cd $ROOTDIR/build/bootloader/atf-marvell
make USE_COHERENT_MEM=0 LOG_LEVEL=20 MV_DDR_PATH=$MV_DDR_PATH PLAT=a80x0_cf_gt_8k all fip
if [ $? != 0 ]; then
	echo "Error building ATF"
	exit -1
fi

echo "Building kernel"
cd $ROOTDIR/build/linux-marvell
make mvebu_v8_lsp_defconfig
make
if [ $? != 0 ]; then
	echo "Error building kernel"
	exit -1
fi

echo "Done building... Now copy images"
cd $ROOTDIR/
mkdir -p images
cp build/bootloader/atf-marvell/build/a80x0_cf_gt_8k/release/flash-image.bin images/
cp build/linux-marvell/arch/arm64/boot/Image images/
cp build/linux-marvell/arch/arm64/boot/dts/marvell/armada-8040-clearfog-gt-8k.dtb images/

