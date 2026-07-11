#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${DISK_ID} ]] || { echo "Disk Device /dev/disk/by-id/${DISK_ID} does not exist" ; exit 1 ; }

if [[ -t 0 ]] ; then
	read -sp "Passphrase: " P ; echo
	read -sp "Passphrase again: " P2 ; echo
else
	P=$(cat)
	P2=${P}
fi
[[ "${#P}" -ge 1 && "${P}" == "${P2}" ]] || { echo "Passphrase empty or does not match" ; exit 1 ; }

blockdev --rereadpt /dev/disk/by-id/${DISK_ID}
dd if=/dev/zero of=/dev/disk/by-id/${DISK_ID} bs=512c count=2048 status=noxfer
dd if=/dev/zero of=/dev/disk/by-id/${DISK_ID} bs=512c seek=$(($(lsblk -n -b -d -o SIZE /dev/disk/by-id/${DISK_ID}) / 512 - 32)) bs=512 count=32 status=noxfer
udevadm trigger && udevadm settle
blockdev --rereadpt /dev/disk/by-id/${DISK_ID}

parted /dev/disk/by-id/${DISK_ID} mklabel gpt
parted /dev/disk/by-id/${DISK_ID} mkpart primary 0% 512M
parted /dev/disk/by-id/${DISK_ID} name 1 "'EFI System Partition'"
parted /dev/disk/by-id/${DISK_ID} toggle 1 boot
parted /dev/disk/by-id/${DISK_ID} mkpart primary 512M 100%
parted /dev/disk/by-id/${DISK_ID} name 2 "'Gentoo GNU/Linux'"
udevadm trigger && udevadm settle && sleep 1
blockdev --rereadpt /dev/disk/by-id/${DISK_ID}

while [[ ! -b /dev/disk/by-id/${DISK_ID}-part1 ]] ; do
	echo "Waiting for /dev/disk/by-id/${DISK_ID}-part1"
	sleep 1
done
sleep 1
mkfs.vfat -F 32 /dev/disk/by-id/${DISK_ID}-part1

SN=$(cat /sys/class/dmi/id/product_serial | tr '[A-Z]' ['a-z'])

while [[ ! -b /dev/disk/by-id/${DISK_ID}-part2 ]] ; do
	echo "Waiting for /dev/disk/by-id/${DISK_ID}-part2"
	sleep 1
done
sleep 1
pvcreate -y /dev/disk/by-id/${DISK_ID}-part2
vgcreate -y vg.${SN} /dev/disk/by-id/${DISK_ID}-part2
lvcreate -y -l 50%FREE vg.${SN} -n root
lvcreate -y -l 40%FREE vg.${SN} -n var
lvcreate -y -l 10%FREE vg.${SN} -n log
lvcreate -y -l 10%FREE vg.${SN} -n audit

cryptsetup -q luksFormat /dev/vg.${SN}/audit <<<${P}
cryptsetup -q luksFormat /dev/vg.${SN}/log <<<${P}
cryptsetup -q luksFormat /dev/vg.${SN}/var <<<${P}
cryptsetup -q luksFormat /dev/vg.${SN}/root <<<${P}

UUID4=$(blkid -o value -s UUID /dev/vg.${SN}/audit)
cryptsetup -q open /dev/vg.${SN}/audit luks-${UUID4} <<<${P}
UUID3=$(blkid -o value -s UUID /dev/vg.${SN}/log)
cryptsetup -q open /dev/vg.${SN}/log luks-${UUID3} <<<${P}
UUID2=$(blkid -o value -s UUID /dev/vg.${SN}/var)
cryptsetup -q open /dev/vg.${SN}/var luks-${UUID2} <<<${P}
UUID1=$(blkid -o value -s UUID /dev/vg.${SN}/root)
cryptsetup -q open /dev/vg.${SN}/root luks-${UUID1} <<<${P}

PASSWORD="${P}" systemd-cryptenroll --tpm2-device=auto /dev/vg.${SN}/audit
PASSWORD="${P}" systemd-cryptenroll --tpm2-device=auto /dev/vg.${SN}/log
PASSWORD="${P}" systemd-cryptenroll --tpm2-device=auto /dev/vg.${SN}/var
PASSWORD="${P}" systemd-cryptenroll --tpm2-device=auto /dev/vg.${SN}/root

mkfs.xfs -m crc=0 -L root -f /dev/mapper/luks-${UUID1}
mount /dev/mapper/luks-${UUID1} /mnt
mkdir -p -m 0 /mnt/var
mkfs.xfs -m crc=0 -L var -f /dev/mapper/luks-${UUID2}
mount /dev/mapper/luks-${UUID2} /mnt/var
mkdir -p -m 0 /mnt/var/log
mkfs.xfs -m crc=0 -L log -f /dev/mapper/luks-${UUID3}
mount /dev/mapper/luks-${UUID3} /mnt/var/log
mkdir -p -m 0 /mnt/var/log/audit
mkfs.xfs -m crc=0 -L audit -f /dev/mapper/luks-${UUID4}
mount /dev/mapper/luks-${UUID4} /mnt/var/log/audit

umount -R /mnt

cryptsetup close luks-${UUID4}
cryptsetup close luks-${UUID3}
cryptsetup close luks-${UUID2}
cryptsetup close luks-${UUID1}
