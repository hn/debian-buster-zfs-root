# debian-buster-zfs-root
Installs Debian GNU/Linux 10 Buster to a native ZFS root filesystem using a [Debian Live CD](https://www.debian.org/CD/live/). The resulting system is a fully updateable debian system with no quirks or workarounds.

## Warning

Due to [problems with grub-efi-amd64-signed](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=925309) UEFI secure boot has been disabled until a proper fix is available (reported by [SoerenBusse](https://github.com/hn/debian-buster-zfs-root/issues/3#issuecomment-537257899) ).

## Usage

1. Boot [Debian Live CD](https://www.debian.org/CD/live/)
1. Login (user: `user`, password: `live`) and become root
1. Setup network and export `http_proxy` environment variable (if needed)
1. Run [this script](https://raw.githubusercontent.com/hn/debian-buster-zfs-root/master/debian-buster-zfs-root.sh)
1. User interface: Select disks and RAID level
1. User interface: Decide if you want Legacy BIOS or EFI boot (only if your hardware supports EFI)
1. Let the installer do the work
1. User interface: install grub to *all* disks participating in the array (only if you're using Legacy BIOS boot)
1. User interface: enter root password and select timezone
1. Reboot
1. Star [this repository](https://github.com/hn/debian-buster-zfs-root) :)

## Fixes included

* Some mountpoints, notably `/var`, need to be mounted via fstab as the ZFS mount script runs too late during boot.
* The EFI System Partition (ESP) is a single point of failure on one disk, [this is arguably a mis-design in the UEFI specification](https://wiki.debian.org/UEFI#RAID_for_the_EFI_System_Partition). This script installs an ESP partition to every RAID disk, accompanied with a corresponding EFI boot menu.

## Bugs

* `grub-install` sometimes mysteriously fails for disk numbers >= 4 (`grub-install: error: cannot find a GRUB drive for /dev/disk/by-id/...`).

## Credits

* https://github.com/hn/debian-stretch-zfs-root
* https://github.com/zfsonlinux/zfs/wiki/Ubuntu-16.04-Root-on-ZFS
* https://janvrany.github.io/2016/10/fun-with-zfs-part-1-installing-debian-jessie-on-zfs-root.html

