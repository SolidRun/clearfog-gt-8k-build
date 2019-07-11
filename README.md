# clearfog-gt-8k-build

This is unofficial fork of official SolidRun repo, updating everything possible to latest versions, and making hardware work as it should.

- U-boot 2019.07
- Linux kernel 5.2.x
- Ubuntu 18.04.2

Tested and working hardware:

- Topaz switch (four blue switching ports)
- WLAN port (yellow port)
- back side PCIe slot, that implements mini PCIe USB lanes
- next to DRAM PCIe slot, including stable support of Compex Atheros ath10k cards
- next to above PCIe slot, implementing SATA mini PCIe lanes
- SPI memory
- internal eMMC memory
- SD card slot

Not tested hardware:

- SFP slot (I don't have any cards)
