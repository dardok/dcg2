#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${USB_ID} ]] || { echo "USB Device /dev/disk/by-id/${USB_ID} does not exist" ; exit 1 ; }

USB_DISK=/dev/disk/by-id/${USB_ID}

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

blockdev --rereadpt ${USB_DISK}
dd if=/dev/zero of=${USB_DISK} bs=512c count=2048 status=noxfer
dd if=/dev/zero of=${USB_DISK} bs=512c seek=$(($(lsblk -n -b -d -o SIZE ${USB_DISK}) / 512 - 32)) bs=512 count=32 status=noxfer
udevadm trigger && udevadm settle
blockdev --rereadpt ${USB_DISK}

parted ---pretend-input-tty ${USB_DISK} <<EOF
mklabel gpt
mkpart primary 0% 512M
name 1 "Bootstrap EFI System Partition"
toggle 1 boot
mkpart primary 512M 90%
name 2 "Bootstrap Gentoo GNU/Linux"
mkpart primary 90% 100%
name 3 "Bootstrap Keystore"
EOF
udevadm trigger && udevadm settle && sleep 1
blockdev --rereadpt ${USB_DISK} && sleep 1

while [[ ! -b ${USB_DISK}-part1 ]] ; do
	echo "Waiting for ${USB_DISK}-part1"
	sleep 1
done
mkfs.vfat -F 32 ${USB_DISK}-part1

while [[ ! -b ${USB_DISK}-part2 ]] ; do
	echo "Waiting for ${USB_DISK}-part2"
	sleep 1
done
mkfs.ext4 -F -L "DCG-Bootstrap" ${USB_DISK}-part2

while [[ ! -b ${USB_DISK}-part3 ]] ; do
	echo "Waiting for ${USB_DISK}-part3"
	sleep 1
done

cryptsetup -q luksFormat ${USB_DISK}-part3 <<<${P}
cryptsetup open ${USB_DISK}-part3 keystore <<<${P}
mkfs.ext4 -F -L "DCG-Keystore" /dev/mapper/keystore
udevadm trigger && udevadm settle

sleep 1

cryptsetup close keystore

# CLIENT
# usbip detach -p 0
# SERVER
# systemctl stop usbip-bind@${USB}
