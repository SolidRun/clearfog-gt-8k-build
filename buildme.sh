#!/bin/bash


echo "Checking all required tools are installed"
TOOLS="wget tar git make 7z unsquashfs dd mkfs.ext4 parted dtc"

for i in $TOOLS; do
	TOOL_PATH=`which $i`
	if [ "x$TOOL_PATH" == "x" ]; then
		echo "Tool $i is not installed"
		exit -1
	fi
done

SUDO=`if [ $UID -ne 0 ]; then echo 'sudo'; fi`

GCCDIR=7.4-2019.02
GCCVER=7.4.1-2019.02

ROOTDIR=`pwd`
if [[ ! -d $ROOTDIR/build/toolchain/gcc-linaro-$GCCVER-x86_64_aarch64-linux-gnu ]]; then
	mkdir -vp $ROOTDIR/build/toolchain
	cd $ROOTDIR/build/toolchain
        wget https://releases.linaro.org/components/toolchain/binaries/$GCCDIR/aarch64-linux-gnu/gcc-linaro-$GCCVER-x86_64_aarch64-linux-gnu.tar.xz
        tar -xvf gcc-linaro-$GCCVER-x86_64_aarch64-linux-gnu.tar.xz
fi

export CFLAGS=
export CPPFLAGS=
export CXXFLAGS=

# U-Boot config
export UBOOTDIR=u-boot
export UBOOT_REPO=https://github.com/MarvellEmbeddedProcessors/u-boot-marvell
export UBOOT_BRANCH=u-boot-2017.03-armada-17.10

export BINARIES_BRANCH=binaries-marvell-armada-17.10

export ATF_BRANCH=atf-v1.3-armada-17.10

export MVDDR_BRANCH=mv_ddr-armada-17.10

export KERNELDIR=linux-marvell
export KERNEL_REPO=https://github.com/MarvellEmbeddedProcessors/linux-marvell
export KERNEL_BRANCH=linux-4.4.52-armada-17.10

export PATH=$PATH:$ROOTDIR/build/toolchain/gcc-linaro-$GCCVER-x86_64_aarch64-linux-gnu/bin
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ATF specific defines
export SCP_BL2=$ROOTDIR/build/bootloader/binaries-marvell/mrvl_scp_bl2_8040.img
export MV_DDR_PATH=$ROOTDIR/build/bootloader/mv-ddr-marvell
export BL33=$ROOTDIR/build/bootloader/$UBOOTDIR/u-boot.bin

echo "Downloading boot loader"
cd $ROOTDIR
mkdir -vp build/bootloader
if [[ ! -d $ROOTDIR/build/bootloader/$UBOOTDIR ]]; then
	cd $ROOTDIR/build/bootloader
	git clone --branch=$UBOOT_BRANCH $UBOOT_REPO $UBOOTDIR
	cd $UBOOTDIR
	git am $ROOTDIR/patches/u-boot/*
else
        cd $ROOTDIR/build/bootloader/$UBOOTDIR
        git pull
        git branch -v
fi

if [[ ! -d $ROOTDIR/build/bootloader/binaries-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone --branch=$BINARIES_BRANCH https://github.com/MarvellEmbeddedProcessors/binaries-marvell
else
	cd $ROOTDIR/build/bootloader/binaries-marvell
        git pull
        git branch -v
fi

if [[ ! -d $ROOTDIR/build/bootloader/atf-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone --branch=$ATF_BRANCH https://github.com/MarvellEmbeddedProcessors/atf-marvell.git
	cd atf-marvell
	git am $ROOTDIR/patches/atf/0001-plat-marvell-a80x0_cf_gt_8k-soft-links-to-mcbin.patch
else
	cd $ROOTDIR/build/bootloader/atf-marvell
	git pull
	git branch -v
fi

if [[ ! -d $ROOTDIR/build/bootloader/mv-ddr-marvell ]]; then
	cd $ROOTDIR/build/bootloader
	git clone --branch=$MVDDR_BRANCH https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git
else
	cd $ROOTDIR/build/bootloader/mv-ddr-marvell
	git pull
	git branch -v
fi

echo "Building U-Boot"
cd $ROOTDIR/build/bootloader/$UBOOTDIR
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

echo "Downloading Linux kernel"
if [[ ! -d $ROOTDIR/build/$KERNELDIR ]]; then
        cd $ROOTDIR/build/
        git clone --branch=$KERNEL_BRANCH $KERNEL_REPO $KERNELDIR
	cd $KERNELDIR
        git am $ROOTDIR/patches/kernel/*
else
	cd $ROOTDIR/build/$KERNELDIR
	git pull
	git branch -v
fi

echo "Building Kernel"
cd $ROOTDIR/build/$KERNELDIR
make mvebu_v8_lsp_defconfig
./scripts/kconfig/merge_config.sh .config $ROOTDIR/configs/extra.config
make -j4
if [ $? != 0 ]; then
	echo "Error building kernel"
	exit -1
fi

echo "Downloading Ubuntu Image"
if [[ ! -f $ROOTDIR/build/ubuntu-18.04.1-server-arm64.squashfs ]]; then
        cd $ROOTDIR/build
        if [[ ! -f ubuntu-18.04.1-server-arm64.iso ]]; then
                wget http://cdimage.ubuntu.com/releases/18.04/release/ubuntu-18.04.1-server-arm64.iso
        fi
        7z x ubuntu-18.04.1-server-arm64.iso install/filesystem.squashfs
	mv install/filesystem.squashfs ubuntu-18.04.1-server-arm64.squashfs
fi

cd $ROOTDIR

echo "Creating partitions and images"
dd if=/dev/zero of=$ROOTDIR/image.img bs=1M count=1024
parted --script $ROOTDIR/image.img mklabel msdos mkpart primary 4096s 100%

echo "Fusin bootloader to the image"
dd if=$ROOTDIR/build/bootloader/atf-marvell/build/a80x0_cf_gt_8k/release/flash-image.bin of=image.img conv=notrunc bs=512 seek=1

echo "Filling image with data"
mkdir -pv $ROOTDIR/image
$SUDO losetup -o 4096 /dev/loop0 $ROOTDIR/image.img
$SUDO mkfs.ext4 /dev/loop0
$SUDO mount /dev/loop0 $ROOTDIR/image

echo "Copying filesystem to the image"
$SUDO unsquashfs -d $ROOTDIR/image/ -f $ROOTDIR/build/ubuntu-18.04.1-server-arm64.squashfs

echo "Copying kernel to the image"
cp -av $ROOTDIR/build/$KERNELDIR/arch/arm64/boot/Image $ROOTDIR/image/boot/
cp -av $ROOTDIR/build/$KERNELDIR/arch/arm64/boot/dts/marvell/armada-8040-clearfog-gt-8k.dtb $ROOTDIR/image/boot/
cat > $ROOTDIR/image/boot/uenv.txt <<EOF
bootargs=console=ttyS0,115200 root=/dev/sda2 rw
uenvcmd=fatload scsi 0:1 0x02000000 Image; fatload scsi 0:1 0x01800000 armada-8040-clearfog-gt-8k.dtb; booti 0x02000000 - 0x01800000
EOF
cd $ROOTDIR/build/$KERNELDIR && make INSTALL_MOD_PATH=$ROOTDIR/image/ modules_install
$SUDO chown -R root:root $ROOTDIR/image/boot $ROOTDIR/image/lib/modules

echo "Finishing..."
$SUDO umount $ROOTDIR/image
$SUDO losetup -d /dev/loop0

echo "Done."
cd $ROOTDIR

