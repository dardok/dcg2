#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${DISK_ID} ]] || { echo "Disk Device /dev/disk/by-id/${DISK_ID} does not exist" ; exit 1 ; }

SYS_DISK=/dev/disk/by-id/${DISK_ID}

if [[ -t 0 ]] ; then
	read -sp "Passphrase: " P ; echo
	read -sp "Passphrase again: " P2 ; echo
else
	P=$(cat)
	P2=${P}
fi
[[ "${#P}" -ge 1 && "${P}" == "${P2}" ]] || { echo "Passphrase empty or does not match" ; exit 1 ; }

dmsetup remove_all -f
blockdev --rereadpt ${SYS_DISK}
dd if=/dev/zero of=${SYS_DISK} bs=512c count=2048 status=noxfer
dd if=/dev/zero of=${SYS_DISK} bs=512c seek=$(($(lsblk -n -b -d -o SIZE ${SYS_DISK}) / 512 - 32)) bs=512 count=32 status=noxfer
udevadm trigger && udevadm settle
blockdev --rereadpt ${SYS_DISK}

parted ---pretend-input-tty ${SYS_DISK} <<EOF
mklabel gpt
mkpart primary 0% 512M
name 1 "EFI System Partition"
toggle 1 boot
mkpart primary 512M 100%
name 2 "Gentoo GNU/Linux"
EOF
udevadm trigger && udevadm settle && sleep 1
blockdev --rereadpt ${SYS_DISK} && sleep 1

while [[ ! -b ${SYS_DISK}-part1 ]] ; do
	echo "Waiting for ${SYS_DISK}-part1"
	sleep 1
done
sleep 1
mkfs.vfat -F 32 ${SYS_DISK}-part1

SN=$(cat /sys/class/dmi/id/product_serial | tr '[A-Z]' ['a-z'])

while [[ ! -b ${SYS_DISK}-part2 ]] ; do
	echo "Waiting for ${SYS_DISK}-part2"
	sleep 1
done
sleep 1

UUID=$(blkid -o value -s UUID ${SYS_DISK}-part2)
cryptsetup -q luksFormat ${SYS_DISK}-part2 <<<${P}
cryptsetup -q open ${SYS_DISK}-part2 luks-${UUID} <<<${P}

pvcreate -ff -y /dev/mapper/luks-${UUID}
vgcreate -y vg.${SN} /dev/mapper/luks-${UUID}
lvcreate -y -l 50%FREE vg.${SN} -n root
lvcreate -y -l 40%FREE vg.${SN} -n var
lvcreate -y -l 10%FREE vg.${SN} -n log
lvcreate -y -l 10%FREE vg.${SN} -n audit
udevadm trigger && udevadm settle && sleep 1

PASSWORD="${P}" systemd-cryptenroll --tpm2-device=auto ${SYS_DISK}-part2

mkfs.xfs -L root -f /dev/mapper/vg.${SN}-root
mount /dev/mapper/vg.${SN}-root /mnt
mkdir -p -m 0 /mnt/var
mkfs.xfs -L var -f /dev/mapper/vg.${SN}-var
mount /dev/mapper/vg.${SN}-var /mnt/var
mkdir -p -m 0 /mnt/var/log
mkfs.xfs -L log -f /dev/mapper/vg.${SN}-log
mount /dev/mapper/vg.${SN}-log /mnt/var/log
mkdir -p -m 0 /mnt/var/log/audit
mkfs.xfs -L audit -f /dev/mapper/vg.${SN}-audit
mount /dev/mapper/vg.${SN}-audit /mnt/var/log/audit

umount -R /mnt
dmsetup remove_all -f
