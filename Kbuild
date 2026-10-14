# SPDX-License-Identifier: GPL-2.0-only
#
# Out-of-tree Kbuild for the r8169 module shipped by r8169-dkms.
#
# src/ is the kernel's drivers/net/ethernet/realtek directory. Its own
# Makefile is not used on purpose: it would build every Realtek driver that
# is enabled in the target kernel's configuration. Only r8169.ko is built
# here, with the same object list as the in-tree build. Whether the LED
# support is compiled in follows the target kernel's CONFIG_R8169_LEDS.

obj-m := r8169.o

r8169-y := src/r8169_main.o src/r8169_firmware.o src/r8169_phy_config.o \
	   r8169_dkms.o
r8169-$(CONFIG_R8169_LEDS) += src/r8169_leds.o

# R8169_DKMS_VERSION is passed on the make command line by dkms.conf and by
# the top-level Makefile.
R8169_DKMS_VERSION ?= unknown
R8169_DKMS_UPSTREAM := $(or $(shell sed -n 's/^UPSTREAM_TAG=//p' $(src)/upstream.conf 2>/dev/null),unknown)

CFLAGS_r8169_dkms.o := -DR8169_DKMS_VERSION='"$(R8169_DKMS_VERSION)"' \
		       -DR8169_DKMS_UPSTREAM='"$(R8169_DKMS_UPSTREAM)"'
