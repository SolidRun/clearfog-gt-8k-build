# clearfog-gt-8k-build

This is unofficial fork of official SolidRun repo, updating everything possible to latest versions, and making hardware work as it should.

- U-boot 2019.04-rc3
- Linux kernel 5.0.0
- Ubuntu 18.04.2

Tested and working hardware:

- Topaz switch
- WLAN port
- back side PCIe that implements USB lanes with mini pcie cards that use USB
- next to DRAM slot PCIe implementing PCIe, including Compex Atheros ath10k cards
- next PCIe slot implementing SATA mini PCIe mode with mini PCIe sata cards
- SPI memory
- internal eMMC memory
- SD card slot

Not tested hardware:

- SFP slot (I don't have cards)
