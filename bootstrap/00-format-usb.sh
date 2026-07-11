#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${USB_ID} ]] || { echo "USB Device /dev/disk/by-id/${USB_ID} does not exist" ; exit 1 ; }

if [[ -t 0 ]] ; then
	read -sp "Passphrase: " P ; echo
	read -sp "Passphrase again: " P2 ; echo
else
	P=$(cat)
	P2=${P}
fi
[[ "${#P}" -ge 1 && "${P}" == "${P2}" ]] || { echo "Passphrase empty or does not match" ; exit 1 ; }

# SERVER
# USB=$(usbip list -l | grep -B1 Verbatim | awk '/busid/ { print $3 }')
# systemctl start usbip-bind@${USB}

# CLIENT
# modprobe vhci-hcd
# usbip list -r 192.168.181.20
# usbip attach -r 192.168.181.20 -b 3-1

## PREPARE USB DRIVE

blockdev --rereadpt /dev/disk/by-id/${USB_ID}
dd if=/dev/zero of=/dev/disk/by-id/${USB_ID} bs=512c count=2048 status=noxfer
dd if=/dev/zero of=/dev/disk/by-id/${USB_ID} bs=512c seek=$(($(lsblk -n -b -d -o SIZE /dev/disk/by-id/${USB_ID}) / 512 - 32)) bs=512 count=32 status=noxfer
udevadm trigger && udevadm settle
blockdev --rereadpt /dev/disk/by-id/${USB_ID}

parted /dev/disk/by-id/${USB_ID} mklabel gpt
parted /dev/disk/by-id/${USB_ID} mkpart primary 0% 512M
parted /dev/disk/by-id/${USB_ID} name 1 "'EFI System Partition'"
parted /dev/disk/by-id/${USB_ID} toggle 1 boot
parted /dev/disk/by-id/${USB_ID} mkpart primary 512M 90%
parted /dev/disk/by-id/${USB_ID} name 2 "'Gentoo GNU/Linux Bootstrap'"
parted /dev/disk/by-id/${USB_ID} mkpart primary 90% 100%
parted /dev/disk/by-id/${USB_ID} name 3 "'Encrypted Keystore'"
udevadm trigger && udevadm settle && sleep 1
blockdev --rereadpt /dev/disk/by-id/${USB_ID}

while [[ ! -b /dev/disk/by-id/${USB_ID}-part1 ]] ; do
	echo "Waiting for /dev/disk/by-id/${USB_ID}-part1"
	sleep 1
done
sleep 1
mkfs.vfat -F 32 /dev/disk/by-id/${USB_ID}-part1

while [[ ! -b /dev/disk/by-id/${USB_ID}-part2 ]] ; do
	echo "Waiting for /dev/disk/by-id/${USB_ID}-part2"
	sleep 1
done
sleep 1
mkfs.ext4 -F -L "Gentoo" /dev/disk/by-id/${USB_ID}-part2

while [[ ! -b /dev/disk/by-id/${USB_ID}-part3 ]] ; do
	echo "Waiting for /dev/disk/by-id/${USB_ID}-part3"
	sleep 1
done
sleep 1
cryptsetup -q luksFormat /dev/disk/by-id/${USB_ID}-part3 <<<${P}
cryptsetup open /dev/disk/by-id/${USB_ID}-part3 keystore <<<${P}
mkfs.ext4 -F -L Keystore /dev/mapper/keystore
udevadm trigger && udevadm settle

sleep 1

cryptsetup close keystore

# CLIENT
# usbip detach -p 0
# SERVER
# systemctl stop usbip-bind@${USB}
