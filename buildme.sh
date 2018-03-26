#!/bin/bash


echo "Checking all required tools are installed"
TOOLS="wget tar git make 7z unsquashfs dd vim mkfs.ext4 sudo parted mkdosfs mcopy dtc"

for i in $TOOLS; do
	TOOL_PATH=`which $i`
	if [ "x$TOOL_PATH" == "x" ]; then
		echo "Tool $i is not installed"
		exit -1
	fi
done

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

if [[ ! -d $ROOTDIR/build/buildroot ]]; then
	cd $ROOTDIR/build
	git clone https://github.com/buildroot/buildroot.git
fi

if [[ ! -d $ROOTDIR/build/linux-marvell ]]; then
	cd $ROOTDIR/build/
	git clone https://github.com/MarvellEmbeddedProcessors/linux-marvell
	cd linux-marvell
	git checkout linux-4.4.52-armada-17.10
	git am $ROOTDIR/patches/kernel/*
fi
if [[ ! -f $ROOTDIR/build/ubuntu-16.04/ext4.part ]]; then
	cd $ROOTDIR/build/
	mkdir -p ubuntu-16.04
	cd ubuntu-16.04
	if [[ ! -f ubuntu-16.04.3-server-arm64.iso ]]; then
		wget http://cdimage.ubuntu.com/releases/16.04.3/release/ubuntu-16.04.3-server-arm64.iso
	fi
	rm -rf install/filesystem.squashfs
	7z x ubuntu-16.04.3-server-arm64.iso install/filesystem.squashfs
	# The following command requires sudo... sorry
	sudo unsquashfs -d temp/ install/filesystem.squashfs
	# Manuall remove the 'x' from the root passwd
	sudo vim temp/etc/passwd
	# Create a sparse 1GB file
	sudo dd if=/dev/zero of=ext4.part bs=1 count=0 seek=300M
	sudo mkfs.ext4 -b 4096 ext4.part
	sudo mount -o loop ext4.part /mnt/
	sudo cp -a temp/* /mnt/
	sudo umount /mnt/
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
./scripts/kconfig/merge_config.sh .config $ROOTDIR/configs/extra.config
make -j4
if [ $? != 0 ]; then
	echo "Error building kernel"
	exit -1
fi

echo "Building buildroot"
cd $ROOTDIR/build/buildroot/
cp $ROOTDIR/configs/buildroot.config .config
# make # For now do not build buildroot.
if [ $? != 0 ]; then
	echo "Error building buildroot"
	exit -1
fi

echo "Done building... Now copy images"
cd $ROOTDIR/
mkdir -p images
cp build/bootloader/atf-marvell/build/a80x0_cf_gt_8k/release/flash-image.bin images/
cp build/linux-marvell/arch/arm64/boot/Image images/
cp build/linux-marvell/arch/arm64/boot/dts/marvell/armada-8040-clearfog-gt-8k.dtb images/
cd build/linux-marvell/; make INSTALL_MOD_PATH=$ROOTDIR/images/modules/ modules_install
cd $ROOTDIR/
cp build/buildroot/output/images/rootfs.cpio.uboot images

echo "Creating partitions and images"
dd if=/dev/zero of=images/disk.img bs=1M count=401
parted --script images/disk.img mklabel msdos mkpart primary 1MiB 100MiB mkpart primary 100MiB 400MiB
#parted --script images/disk.img mklabel gpt mkpart primary 1MiB 100MiB mkpart primary 100MiB 400MiB
dd if=/dev/zero of=images/boot.part bs=1M count=99

# Start with boot partition
mkdosfs images/boot.part
mcopy -i images/boot.part images/Image ::/Image
mcopy -i images/boot.part images/armada-8040-clearfog-gt-8k.dtb ::/armada-8040-clearfog-gt-8k.dtb
cd images/modules/; tar Jc lib > $ROOTDIR/images/modules.tar.xz; cd -
mcopy -i images/boot.part images/modules.tar.xz ::/modules.tar.xz
# Create a uenv.txt for the boot partition
cat > images/uenv.txt <<EOF
bootargs=console=ttyS0,115200 root=/dev/sda2 rw
uenvcmd=fatload scsi 0:1 0x02000000 Image; fatload scsi 0:1 0x01800000 armada-8040-clearfog-gt-8k.dtb; booti 0x02000000 - 0x01800000
EOF
mcopy -i images/boot.part images/uenv.txt ::/uenv.txt
dd if=images/boot.part of=images/disk.img bs=1M seek=1 conv=notrunc

#Copy over the rootfs partition
dd if=build/ubuntu-16.04/ext4.part of=images/disk.img bs=512 seek=204800 conv=notrunc

#boot_ssd=scsi reset; setenv bootargs console=ttyS0,115200 root=/dev/sda2 rw; fatload scsi 0:1 0x02000000 /Image; fatload scsi 0:1 0x01800000 armada-8040-clearfog-gt-8k.dtb; booti 0x02000000 - 0x01800000

