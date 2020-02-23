#!/bin/bash -e
#
# debian-buster-zfs-root.sh V1.00
#
# Install Debian GNU/Linux 10 Buster to a native ZFS root filesystem
#
# (C) 2018-2019 Hajo Noerenberg
#
#
# http://www.noerenberg.de/
# https://github.com/hn/debian-buster-zfs-root
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3.0 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.txt>.
#

### Static settings

ZPOOL=rpool
TARGETDIST=buster

PARTBIOS=1
PARTEFI=2
PARTZFS=3

SIZESWAP=2G
SIZETMP=3G
SIZEVARTMP=3G

NEWHOST="" #Manually specify hostname of new install, otherwise it will be generated
NEWDNS="nameserver 8.8.8.8\nnameserver 8.8.4.4"
NOSWAP="" #Set NOSWAP to be something other than "" and no SWAP dataset will be created/used
NEWPATH=$PATH

### User settings

declare -A BYID
while read -r IDLINK; do
	BYID["$(basename "$(readlink "$IDLINK")")"]="$IDLINK"
done < <(find /dev/disk/by-id/ -type l)

for DISK in $(lsblk -I8,254,259 -dn -o name); do
	if [ -z "${BYID[$DISK]}" ]; then
		SELECT+=("$DISK" "(no /dev/disk/by-id persistent device name available)" off)
	else
		SELECT+=("$DISK" "${BYID[$DISK]}" off)
	fi
done

TMPFILE=$(mktemp)
whiptail --backtitle "$0" --title "Drive selection" --separate-output \
	--checklist "\nPlease select ZFS drives\n" 20 74 8 "${SELECT[@]}" 2>"$TMPFILE"

if [ $? -ne 0 ]; then
	exit 1
fi

while read -r DISK; do
	if [ -z "${BYID[$DISK]}" ]; then
		DISKS+=("/dev/$DISK")
		ZFSPARTITIONS+=("/dev/$DISK$PARTZFS")
		EFIPARTITIONS+=("/dev/$DISK$PARTEFI")
	else
		DISKS+=("${BYID[$DISK]}")
		ZFSPARTITIONS+=("${BYID[$DISK]}-part$PARTZFS")
		EFIPARTITIONS+=("${BYID[$DISK]}-part$PARTEFI")
	fi
done < "$TMPFILE"

whiptail --backtitle "$0" --title "RAID level selection" --separate-output \
	--radiolist "\nPlease select ZFS RAID level\n" 20 74 8 \
	"RAID0" "Striped disks or single disk" off \
	"RAID1" "Mirrored disks (RAID10 for n>=4)" on \
	"RAIDZ" "Distributed parity, one parity block" off \
	"RAIDZ2" "Distributed parity, two parity blocks" off \
	"RAIDZ3" "Distributed parity, three parity blocks" off 2>"$TMPFILE"

if [ $? -ne 0 ]; then
	exit 1
fi

RAIDLEVEL=$(head -n1 "$TMPFILE" | tr '[:upper:]' '[:lower:]')

case "$RAIDLEVEL" in
  raid0)
	RAIDDEF="${ZFSPARTITIONS[*]}"
  	;;
  raid1)
	if [ $((${#ZFSPARTITIONS[@]} % 2)) -ne 0 ]; then
		echo "Need an even number of disks for RAID level '$RAIDLEVEL': ${ZFSPARTITIONS[@]}" >&2
		exit 1
	fi
	I=0
	for ZFSPARTITION in "${ZFSPARTITIONS[@]}"; do
		if [ $((I % 2)) -eq 0 ]; then
			RAIDDEF+=" mirror"
		fi
		RAIDDEF+=" $ZFSPARTITION"
		((I++)) || true
	done
  	;;
  *)
	if [ ${#ZFSPARTITIONS[@]} -lt 3 ]; then
		echo "Need at least 3 disks for RAID level '$RAIDLEVEL': ${ZFSPARTITIONS[@]}" >&2
		exit 1
	fi
	RAIDDEF="$RAIDLEVEL ${ZFSPARTITIONS[*]}"
  	;;
esac

GRUBPKG=grub-pc
if [ -d /sys/firmware/efi ]; then
	whiptail --backtitle "$0" --title "EFI boot" --separate-output \
		--menu "\nYour hardware supports EFI. Which boot method should be used in the new to be installed system?\n" 20 74 8 \
		"EFI" "Extensible Firmware Interface boot" \
		"BIOS" "Legacy BIOS boot" 2>"$TMPFILE"

	if [ $? -ne 0 ]; then
		exit 1
	fi
	if grep -qi EFI $TMPFILE; then
		GRUBPKG=grub-efi-amd64
	fi
fi

whiptail --backtitle "$0" --title "Confirmation" \
	--yesno "\nAre you sure to destroy ZFS pool '$ZPOOL' (if existing), wipe all data of disks '${DISKS[*]}' and create a RAID '$RAIDLEVEL'?\n" 20 74

if [ $? -ne 0 ]; then
	exit 1
fi

### Start the real work

# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=595790
if [ "$(hostid | cut -b-6)" == "007f01" ]; then
	dd if=/dev/urandom of=/etc/hostid bs=1 count=4
fi

DEBRELEASE=$(head -n1 /etc/debian_version)
case $DEBRELEASE in
	9*)
		echo "deb http://deb.debian.org/debian/ stretch contrib non-free" >/etc/apt/sources.list.d/contrib-non-free.list
		test -f /var/lib/apt/lists/deb.debian.org_debian_dists_stretch_non-free_binary-amd64_Packages || apt-get update
		if [ ! -d /usr/share/doc/zfs-dkms ]; then NEED_PACKAGES+=(zfs-dkms); fi
		;;
	10*)
		echo "deb http://deb.debian.org/debian/ buster contrib non-free" >/etc/apt/sources.list.d/contrib-non-free.list
		test -f /var/lib/apt/lists/deb.debian.org_debian_dists_buster_non-free_binary-amd64_Packages || apt-get update
		if [ ! -d /usr/share/doc/zfs-dkms ]; then NEED_PACKAGES+=(zfs-dkms); fi
		;;
	*)
		echo "Unsupported Debian Live CD release" >&2
		exit 1
		;;
esac
if [ ! -f /sbin/zpool ]; then NEED_PACKAGES+=(zfsutils-linux); fi
if [ ! -f /usr/sbin/debootstrap ]; then NEED_PACKAGES+=(debootstrap); fi
if [ ! -f /sbin/sgdisk ]; then NEED_PACKAGES+=(gdisk); fi
if [ ! -f /sbin/mkdosfs ]; then NEED_PACKAGES+=(dosfstools); fi
echo "Need packages: ${NEED_PACKAGES[@]}"
if [ -n "${NEED_PACKAGES[*]}" ]; then DEBIAN_FRONTEND=noninteractive apt-get install --yes "${NEED_PACKAGES[@]}"; fi

modprobe zfs
if [ $? -ne 0 ]; then
	echo "Unable to load ZFS kernel module" >&2
	exit 1
fi
test -d /proc/spl/kstat/zfs/$ZPOOL && zpool destroy $ZPOOL

for DISK in "${DISKS[@]}"; do
	echo -e "\nPartitioning disk $DISK"

	sgdisk --zap-all $DISK

	sgdisk -a1 -n$PARTBIOS:34:2047   -t$PARTBIOS:EF02 \
	           -n$PARTEFI:2048:+512M -t$PARTEFI:EF00 \
                   -n$PARTZFS:0:0        -t$PARTZFS:BF01 $DISK
done

sleep 2

zpool create -f -o ashift=12 -o altroot=/target -O atime=off -O mountpoint=none $ZPOOL $RAIDDEF
if [ $? -ne 0 ]; then
	echo "Unable to create zpool '$ZPOOL'" >&2
	exit 1
fi

zfs set compression=lz4 $ZPOOL
# The two properties below improve performance but reduce compatibility with non-Linux ZFS implementations
# Commented out by default
#zfs set xattr=sa $ZPOOL
#zfs set acltype=posixacl $ZPOOL

zfs create $ZPOOL/ROOT
zfs create -o mountpoint=/ $ZPOOL/ROOT/debian-$TARGETDIST
zpool set bootfs=$ZPOOL/ROOT/debian-$TARGETDIST $ZPOOL

zfs create -o mountpoint=/tmp -o setuid=off -o exec=off -o devices=off -o com.sun:auto-snapshot=false -o quota=$SIZETMP $ZPOOL/tmp
chmod 1777 /target/tmp

# /var needs to be mounted via fstab, the ZFS mount script runs too late during boot
zfs create -o mountpoint=legacy $ZPOOL/var
mkdir -v /target/var
mount -t zfs $ZPOOL/var /target/var

# /var/tmp needs to be mounted via fstab, the ZFS mount script runs too late during boot
zfs create -o mountpoint=legacy -o com.sun:auto-snapshot=false -o quota=$SIZEVARTMP $ZPOOL/var/tmp
mkdir -v -m 1777 /target/var/tmp
mount -t zfs $ZPOOL/var/tmp /target/var/tmp
chmod 1777 /target/var/tmp

if [ "NOSWAP" == "" ] ; then 
zfs create -V $SIZESWAP -b "$(getconf PAGESIZE)" -o primarycache=metadata -o com.sun:auto-snapshot=false -o logbias=throughput -o sync=always $ZPOOL/swap
# sometimes needed to wait for /dev/zvol/$ZPOOL/swap to appear
sleep 2
mkswap -f /dev/zvol/$ZPOOL/swap
fi

zpool status
zfs list

debootstrap --include=openssh-server,locales,linux-headers-amd64,linux-image-amd64,joe,rsync,sharutils,psmisc,htop,patch,less --components main,contrib,non-free $TARGETDIST /target http://deb.debian.org/debian/
if [ "$NEWHOST" == "" ]; then
	NEWHOST=debian-$(hostid)
fi
echo "$NEWHOST" >/target/etc/hostname
sed -i "1s/^/127.0.1.1\t$NEWHOST\n/" /target/etc/hosts

# Copy hostid as the target system will otherwise not be able to mount the misleadingly foreign file system
cp -va /etc/hostid /target/etc/
if [ "NOSWAP" == "" ] ; then 
cat << EOF >/target/etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system>         <mount point>   <type>  <options>       <dump>  <pass>
/dev/zvol/$ZPOOL/swap     none            swap    defaults        0       0
$ZPOOL/var                /var            zfs     defaults        0       0
$ZPOOL/var/tmp            /var/tmp        zfs     defaults        0       0
EOF
else
cat << EOF >/target/etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system>         <mount point>   <type>  <options>       <dump>  <pass>
$ZPOOL/var                /var            zfs     defaults        0       0
$ZPOOL/var/tmp            /var/tmp        zfs     defaults        0       0
EOF
fi

mount --rbind /dev /target/dev
mount --rbind /proc /target/proc
mount --rbind /sys /target/sys
ln -s /proc/mounts /target/etc/mtab

perl -i -pe 's/# (en_US.UTF-8)/$1/' /target/etc/locale.gen
echo 'LANG="en_US.UTF-8"' > /target/etc/default/locale
chroot /target /usr/sbin/locale-gen

chroot /target /usr/bin/apt-get update

chroot /target /usr/bin/apt-get install --yes grub2-common $GRUBPKG zfs-initramfs zfs-dkms
grep -q zfs /target/etc/default/grub || perl -i -pe 's/quiet/boot=zfs quiet/' /target/etc/default/grub 
chroot /target /usr/sbin/update-grub

if [ "${GRUBPKG:0:8}" == "grub-efi" ]; then

	# "This is arguably a mis-design in the UEFI specification - the ESP is a single point of failure on one disk."
	# https://wiki.debian.org/UEFI#RAID_for_the_EFI_System_Partition
	mkdir -pv /target/boot/efi
	I=0
	for EFIPARTITION in "${EFIPARTITIONS[@]}"; do
		mkdosfs -F 32 -n EFI-$I $EFIPARTITION
		mount $EFIPARTITION /target/boot/efi
		chroot /target /usr/sbin/grub-install --target=x86_64-efi --no-uefi-secure-boot --efi-directory=/boot/efi --bootloader-id="Debian $TARGETDIST (RAID disk $I)" --recheck --no-floppy
		umount $EFIPARTITION
		if [ $I -gt 0 ]; then
			EFIBAKPART="#"
		fi
		echo "${EFIBAKPART}PARTUUID=$(blkid -s PARTUUID -o value $EFIPARTITION) /boot/efi vfat defaults 0 1" >> /target/etc/fstab
		((I++)) || true
	done
fi

if [ -d /proc/acpi ]; then
	chroot /target /usr/bin/apt-get install --yes acpi acpid
	chroot /target service acpid stop
fi
ETHDEV=$(udevadm info -e | grep "ID_NET_NAME_ONBOARD=" | head -n1 | cut -d= -f2) #Selects 1st onboard NIC, if present
if [ "$ETHDEV" == "" ] ; then
	ETHDEV=$(udevadm info -e | grep "ID_NET_NAME_PATH=" | head -n1 | cut -d= -f2) #Selects 1st addin NIC, if present
fi
test -n "$ETHDEV" || ETHDEV=enp0s1
echo -e "\nauto $ETHDEV\niface $ETHDEV inet dhcp\n" >>/target/etc/network/interfaces
echo -e "$NEWDNS" >> /target/etc/resolv.conf

until chroot /target /usr/bin/passwd
do
  echo "Try again"
  sleep 2
done

chroot /target /bin/bash -c "export PATH=$NEWPATH" #Exporting root PATH to root on new system
chroot /target /usr/sbin/dpkg-reconfigure tzdata

sync

#zfs umount -a

## chroot /target /bin/bash --login
## zpool import -R /target rpool

