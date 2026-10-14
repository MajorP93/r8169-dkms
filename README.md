# r8169-dkms

The Linux kernel's own `r8169` driver for Realtek RTL8169/8168/8101/8125/8126/8127
Ethernet controllers, **as shipped with the Proxmox 7.0 kernel plus newer fixes and
device support from mainline Linux and the stable trees**, packaged as a DKMS Debian
package.

This is **not** Realtek's vendor driver (`r8168`/`r8125`/`r8126`). It's the in-tree
driver, so you get fixes without changing your kernel.

The target is **Proxmox VE and Proxmox Backup Server** with their 7.0 kernels
(`7.0.14-22-pve` and later), which are based on the Ubuntu 26.04 kernel.

## What's inside

| | |
|---|---|
| Upstream base | `drivers/net/ethernet/realtek` from Ubuntu kernel tag `Ubuntu-7.0.0-41.41` |
| Proxmox patches | the Proxmox kernel's `r8169` patches, see [below](#why-the-proxmox-patches) |
| Fixes | see [Fixes on top of the Proxmox driver](#fixes-on-top-of-the-proxmox-driver) |
| Built for | Proxmox kernels `7.0.x-y-pve` from `7.0.14-22-pve` on, with `CONFIG_R8169` enabled (see `dkms.conf`) |
| Installed to | `/lib/modules/<kernel>/updates/dkms/r8169.ko*`, which takes precedence over the in-tree module |

### Why the Proxmox patches

Since `Ubuntu-7.0.0-39.39`, Ubuntu's kernel includes a linux-next series that
converts `r8169` to phylink and adds RTL8116af/RTL8127atf fiber support (several
`UBUNTU: SAUCE` commits). It caused a regression: RTL8125B NICs get no link after a
UEFI boot ([Proxmox bug #8110](https://bugzilla.proxmox.com/show_bug.cgi?id=8110)).
So the Proxmox kernel reverts the whole series, as of `7.0.14-22-pve` (pve-kernel
commit `803fe655`).

This repository carries the same `r8169` patches, as commits authored by their
original author. With them, `src/` is identical to the Proxmox kernel's
`drivers/net/ethernet/realtek`. The parts of those patches outside this directory
(Realtek PHY driver, phylink core) are already in the Proxmox kernel itself.

Because of this, the driver doesn't fit Ubuntu's own 7.0 kernels, which carry
the phylink series, or Proxmox kernels before `7.0.14-22-pve`.

### Fixes on top of the Proxmox driver

| Commit | Origin |
|---|---|
| r8169: add support for RTL8125cp | mainline `a90e3029f20d` |
| r8169: give RTL_GIGA_MAC_VER_EXTENDED a distinct value | mainline `d77f3f016826` |
| r8169: keep LED device name valid after setup | mainline `3f33a2d2ea92` |
| r8169: disable EEE on RTL8168h/8111h | linux-7.2.y `c5c096b13445` (v7.2.10), upstream `3cdeaef1754a` |

All of them are unmodified cherry-picks. With them, all `r8169` sources except
`r8169_main.c` are identical to mainline. `r8169_main.c` additionally keeps Ubuntu's
non-phylink `r8169` patches (RTL8116af SerDes quirk, ASPM on Dell platforms), and
lacks a cosmetic PCI ID table cleanup from mainline.

`git log upstream..main -- src/` lists all changes on top of the upstream base, with
full details.

## Installation

Install the kernel headers for each kernel the module should be built for.
`proxmox-default-headers` tracks the default kernel:

```sh
apt install proxmox-default-headers
apt install ./r8169-dkms_<version>_all.deb
reboot
```

The package's postinst regenerates the initramfs of every kernel that got the
module, because `r8169` is normally loaded from the initramfs at boot.
`proxmox-boot-tool` copies the new images to the ESPs automatically.

Kernels installed later are handled automatically: DKMS builds the module before
their initramfs is generated.

### Checking that it works

```sh
dkms status r8169
modinfo -F filename r8169      # .../updates/dkms/r8169.ko*
modinfo -F version r8169       # package version, e.g. 7.0.0.41.41+2
modinfo -F upstream r8169      # Ubuntu-7.0.0-41.41
cat /sys/module/r8169/version  # loaded module; the in-tree r8169 has no version
```

### Secure Boot

DKMS signs the module with its own key (`/var/lib/dkms/mok.pub`). Enroll that key
once with `mokutil --import /var/lib/dkms/mok.pub` and confirm it on the next boot.
Do this **before** rebooting into the new module: if the key isn't enrolled, the
kernel rejects the module and the NIC has no driver.

### Removal

`apt remove r8169-dkms` removes the module and regenerates the initramfs, so the
in-tree driver is used again after a reboot.

### Realtek vendor drivers

Packages such as `r8168-dkms` or `realtek-r8125-dkms` usually blacklist `r8169`.
Remove them, and any `blacklist r8169` line in `/etc/modprobe.d/`, before you use
this package.

## Building

```sh
apt install build-essential debhelper dh-dkms
make deb                     # or: dpkg-buildpackage -b -us -uc
```

The package ends up in the parent directory. Nothing is compiled at package build
time; DKMS compiles the module on the target system.

For development, you can build the module directly against the running kernel (or
`KVER=...`):

```sh
make
make clean
```

You can also install it into DKMS from a checkout without building a package:

```sh
sudo make dkms-install
sudo make dkms-remove
```

## Repository layout

```
src/                  drivers/net/ethernet/realtek with its kernel history
Kbuild                builds r8169.ko from src/ (and only that)
r8169_dkms.c          adds version/upstream info to modinfo
dkms.conf             DKMS configuration (version filled in at build time)
upstream.conf         where src/ comes from (repository, path, tag, commit)
Makefile              helper targets: build, deb, dkms-install, install-src
debian/               Debian packaging (native, debhelper 13, dh-dkms)
scripts/              maintenance: import a new upstream tag, backport commits
```

`src/` is a complete copy of the kernel directory, including the other Realtek
drivers (`8139cp`, `8139too`, `rtase`). Keeping the directory complete preserves the
upstream history and keeps future imports simple. Only the `r8169*` files are
shipped and built.

### Branches and history

- `upstream`: the history of `drivers/net/ethernet/realtek` from the Ubuntu kernel,
  filtered with `git filter-repo` and moved to `src/`. Each import is tagged
  `upstream/<kernel tag>`. Commit messages are untouched, so `Fixes:` tags and
  `commit ... upstream` lines still refer to kernel commits.
- `main`: `upstream`, plus the Proxmox kernel's `r8169` patches, plus fixes, plus the
  packaging.

Package releases are tagged `debian/<version>`.

## Maintenance

### Versioning

The package version is `<kernel version>.<Ubuntu ABI>.<Ubuntu upload>+<n>`,
following the Ubuntu linux-meta style. For example, `7.0.0.41.41+2` is based on
`Ubuntu-7.0.0-41.41`. Increase `<n>` for new fixes or packaging changes. When
rebasing onto a new upstream tag, start again at `+1`. The DKMS module version is the
same as the package version.

### Adding a fix

```sh
scripts/backport.sh <commit>                       # mainline commit, from git.kernel.org
scripts/backport.sh -n linux-7.2.y <commit>        # stable commit, naming its branch
scripts/backport.sh -t netdev/net-next <commit>    # from another git.kernel.org tree
scripts/backport.sh -C ~/src/linux <commit>        # from a local Linux checkout
dch -i "<subject> (<commit>)"
```

The script rewrites the patch paths to `src/` and applies it with `git am`, which
keeps author, date and message, and records `(cherry picked from commit ...)`. If the
patch doesn't apply as-is, adapt it, document the adaptation in the commit message,
and use `(backported from commit ...)` instead.

Prefer fixes that apply to the Proxmox kernel's `r8169` without phylink, such as
mainline or stable commits. net-next has the phylink conversion, so its
`r8169` changes may not fit.

### Moving to a newer upstream tag

```sh
scripts/import-upstream.sh Ubuntu-7.0.0-45.45   # optionally: -r <local kernel clone>
git merge upstream/Ubuntu-7.0.0-45.45
```

Then:

- compare the Proxmox kernel's `r8169` patches (`patches/kernel/` in
  [pve-kernel](https://git.proxmox.com/?p=pve-kernel.git)) for the matching release
  with the ones in `main`, and adjust;
- update `UPSTREAM_TAG` and `UPSTREAM_COMMIT` in `upstream.conf`;
- drop fixes that the new base already contains;
- check `BUILD_EXCLUSIVE_KERNEL` and `BUILD_EXCLUSIVE_KERNEL_MIN` in `dkms.conf`, and
  the object list in `Kbuild`;
- add a changelog entry.

`git filter-repo` is deterministic, so the new import shares every commit with the
previous one, and the merge brings in only the new upstream changes.

## License

GPL-2.0-only, like the Linux kernel driver it contains. See `LICENSE` and
`debian/copyright`.
