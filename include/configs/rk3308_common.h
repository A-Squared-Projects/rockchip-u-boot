/*
 * (C) Copyright 2017 Rockchip Electronics Co., Ltd
 *
 * SPDX-License-Identifier:     GPL-2.0+
 */

#ifndef __CONFIG_RK3308_COMMON_H
#define __CONFIG_RK3308_COMMON_H

#include "rockchip-common.h"

#define CONFIG_SYS_MALLOC_LEN		(10 << 20)
#define CONFIG_SYS_CBSIZE		1024
#define CONFIG_SKIP_LOWLEVEL_INIT
#define CONFIG_SYS_MAX_NAND_DEVICE	1
#define CONFIG_SYS_NAND_ONFI_DETECTION
#define CONFIG_SYS_NAND_PAGE_SIZE	2048
#define CONFIG_SYS_NAND_PAGE_COUNT	64
#define CONFIG_SYS_NAND_SIZE		(256 * 1024 * 1024)
#define CONFIG_SPL_FRAMEWORK
#define CONFIG_SPL_TEXT_BASE		0x00000000
#define CONFIG_SPL_MAX_SIZE		0x40000
#define CONFIG_SPL_BSS_START_ADDR	0x00400000
#define CONFIG_SPL_BSS_MAX_SIZE		0x2000
#define CONFIG_SYS_SPI_U_BOOT_OFFS	0x8000

#define CONFIG_SYS_NS16550_MEM32

#define CONFIG_SYS_TEXT_BASE		0x00600000
#define CONFIG_SYS_INIT_SP_ADDR		0x00800000
#define CONFIG_SYS_LOAD_ADDR		0x00C00800
#define CONFIG_SPL_STACK		0x00400000
#define CONFIG_SYS_BOOTM_LEN		(64 << 20)	/* 64M */

#define COUNTER_FREQUENCY		24000000

#define GICD_BASE			0xff581000
#define GICC_BASE			0xff582000

#define OTP_SECURE_BOOT_ENABLE_ADDR	0x0
#define OTP_SECURE_BOOT_ENABLE_SIZE	1
#define OTP_RSA_HASH_ADDR		0x10
#define OTP_RSA_HASH_SIZE		32

#define CONFIG_SYS_BOOTM_LEN	(64 << 20)	/* 64M */

/* MMC/SD IP block */
#define CONFIG_BOUNCE_BUFFER

#define CONFIG_SYS_SDRAM_BASE		0
#define SDRAM_MAX_SIZE			0xff000000
#define SDRAM_BANK_SIZE			(2UL << 30)
#ifdef CONFIG_DM_DVFS
#define CONFIG_PREBOOT			"dvfs repeat"
#else
#define CONFIG_PREBOOT
#endif

#ifndef CONFIG_SPL_BUILD

/* usb mass storage */
#define CONFIG_USB_FUNCTION_MASS_STORAGE
#define CONFIG_ROCKUSB_G_DNL_PID        0x330d

#ifdef CONFIG_ARM64
#define ENV_MEM_LAYOUT_SETTINGS \
	"scriptaddr=0x00500000\0" \
	"pxefile_addr_r=0x00600000\0" \
	"fdt_addr_r=0x01f00000\0" \
	"kernel_addr_no_low_bl32_r=0x00280000\0" \
	"kernel_addr_r=0x00680000\0" \
	"kernel_addr_c=0x02480000\0" \
	"ramdisk_addr_r=0x04000000\0"
#else
/*
 * kernel_addr_r must keep the kernel clear of the OP-TEE secure carveout
 * when BL32 is present. RK3308 loads OP-TEE (BL32) at 0x200000 with
 * TEE_RAM+TA_RAM+SHM = 4 MiB (ends 0x600000) and firewalls it.
 *
 * The kernel is a zImage: u-boot XIP-runs it at kernel_addr_r and it
 * self-decompresses via CONFIG_AUTO_ZRELADDR to
 * (kernel_addr_r & 0xf8000000) + TEXT_OFFSET. The ~7.5 MiB decompressed
 * kernel therefore lands on the 128 MiB-aligned window containing
 * kernel_addr_r. The historical 0x58000 (and even the ARM64 branch's
 * 0x680000, which only works there because the ARM64 Image runs at its
 * load address without decompressing) both mask to 0x0 -> decompress low,
 * straight through the OP-TEE region -> secure fault / boot loop.
 *
 * So load the zImage on the 128 MiB boundary (0x8000000): AUTO_ZRELADDR then
 * decompresses to ~0x8000000, well above OP-TEE. arch/arm/mach-rockchip/
 * board.c moves kernel_addr_r back down to kernel_addr_no_low_bl32_r (the
 * historical 0x58000) when no BL32 is enabled, so non-OP-TEE firmware (the
 * current fleet) boots exactly as before. kernel_addr_c must stay defined
 * (non-zero) or android_image_set_kload() picks SDRAM_BASE+0x8000 for the
 * Image path.
 *
 * NB: the OP-TEE kernel now disables AUTO_ZRELADDR and fixes ZRELADDR at
 * 0x658000 (CONFIG_PHYS_OFFSET=0x600000, the memory-reclaim change - pairs with
 * the linux-rithum SRCREV that sets it). u-boot still XIP-loads the zImage at
 * kernel_addr_r=0x08000000 and the decompressor relocates the output down to
 * 0x658000, so PHYS_OFFSET is 0x600000, not 0x8000000 - the reclaimed low RAM
 * (0x600000-0x8000000) is back.
 *
 * ramdisk_addr_r must be (a) above PHYS_OFFSET (0x600000) or the kernel drops
 * the ramdisk as "not a memory region" and disables the initrd, and (b) well
 * below u-boot's own top-of-DRAM footprint. Recovery IS an initramfs: with its
 * ramdisk discarded the recovery kernel falls through to the baked-in
 * root=PARTUUID (rootfs) and boots the normal system instead of the flasher -
 * so updateEngine writes the BCB, u-boot enters recovery, yet nothing is ever
 * flashed and no u-boot/trust update (recovery-only) can land.
 *
 * Put it LOW at 0x03000000 (48 MiB): above the decompressed kernel (ends
 * ~0xd90000) and fdt (0x02800000), below the zImage load (0x08000000). It must
 * be low, NOT high: u-boot relocates itself to the top of detected DRAM with a
 * 10 MiB CONFIG_SYS_MALLOC_LEN arena below it, so on the 256 MiB RS (u-boot
 * ~0x0dc13000) the earlier 0x0d000000 (208 MiB) landed inside u-boot's malloc
 * and corrupted the ramdisk - it only survived on the 512 MiB RSP because there
 * u-boot sits at ~476 MiB, far above 208 MiB. The reclaim (PHYS_OFFSET low)
 * is what lets it go low again; before it, the ramdisk was forced above
 * 0x8000000, which is exactly what broke the 256 MiB part.
 */
#define ENV_MEM_LAYOUT_SETTINGS \
	"scriptaddr=0x00500000\0" \
	"pxefile_addr_r=0x00600000\0" \
	"fdt_addr_r=0x02800000\0" \
	"kernel_addr_no_low_bl32_r=0x00058000\0" \
	"kernel_addr_r=0x08000000\0" \
	"kernel_addr_c=0x2008000\0" \
	"ramdisk_addr_r=0x03000000\0"
#endif

#include <config_distro_bootcmd.h>
#define CONFIG_EXTRA_ENV_SETTINGS \
	ENV_MEM_LAYOUT_SETTINGS \
	"partitions=" PARTS_DEFAULT \
	ROCKCHIP_DEVICE_SETTINGS \
	RKIMG_DET_BOOTDEV \
	BOOTENV_SHARED_RKNAND \
	BOOTENV

#endif

#endif
