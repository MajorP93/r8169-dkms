// SPDX-License-Identifier: GPL-2.0-only
/*
 * Build metadata for the r8169 module built by r8169-dkms.
 *
 * This lives in its own translation unit so that the driver sources in src/
 * stay identical to the kernel tree they were taken from. Both values are
 * provided by Kbuild and show up in "modinfo r8169":
 *
 *   version:   r8169-dkms package version
 *   upstream:  kernel tag the driver sources are based on
 *
 * Note that the in-tree r8169 has no MODULE_VERSION(), so DKMS' version
 * sanity check always treats this module as the newer one.
 */
#include <linux/module.h>

MODULE_VERSION(R8169_DKMS_VERSION);
MODULE_INFO(upstream, R8169_DKMS_UPSTREAM);
