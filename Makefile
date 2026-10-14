# SPDX-License-Identifier: GPL-2.0-only
#
# Helper targets for r8169-dkms. The module itself is described in Kbuild,
# which is what DKMS (and the "modules" target below) hand to the kernel
# build system.
#
#   make [KVER=<kernel>]       build r8169.ko against <kernel> (default: running)
#   make clean                 remove build artefacts
#   make deb                   build the Debian package (../r8169-dkms_*.deb)
#   make dkms-install          install the sources into DKMS without a .deb
#   make dkms-remove           undo "make dkms-install"
#   make install-src DESTDIR=  install the DKMS source tree (used by debian/rules)

DKMS_NAME := r8169
VERSION ?= $(shell sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' debian/changelog)
DKMS_SRC := /usr/src/$(DKMS_NAME)-$(VERSION)

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

# Files shipped in the DKMS source tree. Only the r8169 driver is taken from
# src/; the other Realtek drivers there are kept to mirror the kernel tree.
TOP_FILES := Kbuild r8169_dkms.c upstream.conf
DRV_FILES := $(wildcard src/r8169*.c src/r8169*.h)

# r8169 is usually part of the initramfs; refresh it so the module that is
# loaded at boot is the one now installed.
UPDATE_INITRAMFS = if command -v update-initramfs >/dev/null 2>&1; then \
		update-initramfs -u -k $(KVER); fi

.PHONY: all modules clean deb install-src dkms-install dkms-remove

all: modules

modules:
	$(MAKE) -C $(KDIR) M=$(CURDIR) R8169_DKMS_VERSION=$(VERSION) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

deb:
	dpkg-buildpackage -b -us -uc

install-src:
	$(if $(DRV_FILES),,$(error no r8169 sources found in src/))
	install -d $(DESTDIR)$(DKMS_SRC)/src
	install -m 0644 $(TOP_FILES) $(DESTDIR)$(DKMS_SRC)/
	install -m 0644 $(DRV_FILES) $(DESTDIR)$(DKMS_SRC)/src/

dkms-install: install-src
	sed 's/#MODULE_VERSION#/$(VERSION)/' dkms.conf > $(DESTDIR)$(DKMS_SRC)/dkms.conf
	dkms install $(DKMS_NAME)/$(VERSION) -k $(KVER)
	$(UPDATE_INITRAMFS)

dkms-remove:
	-dkms remove $(DKMS_NAME)/$(VERSION) --all
	rm -rf $(DESTDIR)$(DKMS_SRC)
	$(UPDATE_INITRAMFS)
