#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${DISK_ID}-part2 ]] || { echo "Disk Partition /dev/disk/by-id/${DISK_ID}-part2 does not exist" ; exit 1 ; }
[[ -b /dev/disk/by-id/${USB_ID}-part3 ]] || { echo "USB Partition /dev/disk/by-id/${USB_ID}-part3 does not exist" ; exit 1 ; }

SYS_DISK=/dev/disk/by-id/${DISK_ID}

if [[ -t 0 ]] ; then
	read -sp "Passphrase: " P ; echo
else
	P=$(cat)
fi
[[ "${#P}" -ge 1 ]] || { echo "Passphrase empty" ; exit 1 ; }

SN=$(cat /sys/class/dmi/id/product_serial | tr '[A-Z]' ['a-z'])
UUID=$(blkid -o value -s UUID ${SYS_DISK}-part2)
cryptsetup -q open ${SYS_DISK}-part2 luks-${UUID} <<<${P}
udevadm trigger && udevadm settle
vgchange -ay

mkdir -m 0755 -p /mnt
mount /dev/vg.${SN}/root /mnt
mount /dev/vg.${SN}/var /mnt/var
mount /dev/vg.${SN}/log /mnt/var/log
mount /dev/vg.${SN}/audit /mnt/var/log/audit
mkdir -m 0 -p /mnt/boot
mount ${SYS_DISK}-part1 /mnt/boot

KEYSTORE=/mnt/root/.keystore
cryptsetup open /dev/disk/by-id/${USB_ID}-part3 keystore <<<${P}
mkdir -m 0 -p ${KEYSTORE}
mount /dev/mapper/keystore ${KEYSTORE}

if [ ! -e /mnt/etc/os-release ] ; then
	LATEST_STAGE3=${AUTOBUILDS}/$(curl -fsSLo - ${AUTOBUILDS}/latest-stage3-amd64-hardened-selinux-systemd.txt | awk '/stage3/ { print $1 }')
	curl -fsSLo - ${LATEST_STAGE3} | tar -C /mnt -Jxf -
fi

cat /run/systemd/resolve/resolv.conf > /mnt/etc/resolv.conf

mkdir -m 0 -p /mnt/{dev,proc,sys,run,tmp,var/tmp}
mount --bind /dev /mnt/dev
mount --bind /dev/pts /mnt/dev/pts
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run
mount -t tmpfs tmpfs /mnt/dev/shm
mount -t tmpfs tmpfs /mnt/tmp
mount -t tmpfs tmpfs /mnt/var/tmp

git -C /mnt/var/db/repos clone https://github.com/dardok/dcg2.git
chown -R portage:portage /mnt/var/db/repos/dcg2

TERM=xterm SYS_DISK=${SYS_DISK} SN=${SN} UUID=${UUID} chroot /mnt <<"EOC"
export PROMPT_DIRTRIM=
set -euo pipefail

ln -sfn ../usr/share/zoneinfo/UTC /etc/localtime
printf "C\nen_US\n" > /etc/locale.gen
locale-gen && eselect locale set "en_US.UTF-8"
. /etc/profile

kill_gpg_agents() {
	gpgconf --homedir /etc/portage/gnupg --kill all
	gpgconf --homedir /root/.keystore/gpg --kill all
}
trap kill_gpg_agents EXIT

getuto

DCG_SEC_ID=$(gpg --homedir /root/.keystore/gpg --quiet --no-permission-warning --list-secret-keys --keyid-format long --with-colons | grep -A1 "^sec" | tail -1 | awk -F: '{ print $10 }')
DCG_SSB_ID=$(gpg --homedir /root/.keystore/gpg --quiet --no-permission-warning --list-secret-keys --keyid-format long --with-colons | grep -A1 "^ssb" | tail -1 | awk -F: '{ print $10 }')
gpg --quiet --no-permission-warning --homedir /root/.keystore/gpg --batch --export-secret-key --armor --pinentry-mode loopback --passphrase-file /root/.keystore/gpg/pass ${DCG_SEC_ID} | \
	gpg --quiet --no-permission-warning --homedir /etc/portage/gnupg --batch --import --pinentry-mode loopback --passphrase-file /etc/portage/gnupg/pass
cat /root/.keystore/gpg/pass /etc/portage/gnupg/pass /etc/portage/gnupg/pass | \
	gpg --quiet --no-permission-warning --homedir /etc/portage/gnupg --batch --command-fd 0 --pinentry-mode loopback --edit-key ${DCG_SEC_ID} passwd save
printf "5\ny\n" | gpg --quiet --no-permission-warning --homedir /etc/portage/gnupg --batch --command-fd 0 --pinentry-mode loopback --edit-key ${DCG_SEC_ID} trust save
gpg --quiet --no-permission-warning --homedir /etc/portage/gnupg --batch --yes --no-tty --passphrase-file /etc/portage/gnupg/pass --pinentry-mode loopback --quick-lsign-key ${DCG_SEC_ID}
printf "y\ny\n" | gpg --quiet --no-permission-warning --homedir /etc/portage/gnupg --batch --yes --no-tty --passphrase-file /etc/portage/gnupg/pass --pinentry-mode loopback --lsign-key ${DCG_SSB_ID}
DCG_SSB_ID=$(gpg --homedir /etc/portage/gnupg --quiet --no-permission-warning --list-secret-keys --keyid-format long | grep -A2 "DCG GPG" | tail -1 | xargs)

cat > /etc/portage/make.conf <<-"EOF"
WARNING_FLAGS="-Werror=odr -Werror=lto-type-mismatch -Werror=strict-aliasing"

COMMON_FLAGS="-O2 -pipe -march=znver3 -flto ${WARNING_FLAGS}"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

LC_MESSAGES="C.UTF-8"

CPU_FLAGS_X86="aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3 sse4a sha vpclmulqdq"

MAKEOPTS="-j8 -l7"
EMERGE_DEFAULT_OPTS="--keep-going --with-bdeps y -j6 --load-average=6"

USE="${USE} lto pgo"

FEATURES="buildpkg binpkg-signing binpkg-request-signature"
BINPKG_FORMAT="gpkg"
BINPKG_GPG_SIGNING_GPG_HOME="/etc/portage/gnupg"
BINPKG_GPG_SIGNING_BASE_COMMAND="/usr/bin/flock /run/lock/portage-binpkg-gpg.lock /usr/bin/gpg --quiet --no-permission-warning --batch --sign --armor --pinentry-mode loopback --passphrase-file /etc/portage/gnupg/pass [PORTAGE_CONFIG]"
SECUREBOOT_SIGN_KEY="/root/.keystore/pki/secureboot/DCG_DB.key"
SECUREBOOT_SIGN_CERT="/root/.keystore/pki/secureboot/DCG_DB.crt"
EOF
printf "BINPKG_GPG_SIGNING_KEY=\"0x${DCG_SSB_ID}\"\n" >> /etc/portage/make.conf

emerge-webrsync && eselect news read --quiet ; eselect news purge

[ -h /etc/portage/make.profile ] && rm -f /etc/portage/make.profile
mkdir -p /etc/portage/make.profile
echo 8 > /etc/portage/make.profile/eapi
cat > /etc/portage/make.profile/parent <<-EOF
dcg2:dcg/hosts/actor
EOF

mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/dcg2.conf <<-EOF
[dcg2]
location = /var/db/repos/dcg2
masters = gentoo
sync-type = git
sync-uri = https://github.com/dardok/dcg2.git
priority = 100
EOF

mkdir -p /var/cache/binhost
semanage fcontext -a -t portage_ebuild_t /var/cache/binhost

mkdir -p /etc/portage/package.use
cat > /etc/portage/package.use/targets <<EOF
*/* PYTHON_TARGETS: -* python3_14
*/* PYTHON_SINGLE_TARGET: -* python3_14
EOF

ROOT_UUID=$(blkid -o value -s UUID /dev/vg.${SN}/root)
cat > /etc/kernel/cmdline <<EOF
root=UUID=${ROOT_UUID} rd.luks.uuid=${UUID} rd.luks.options=tpm2-device=auto rd.lvm.lv=vg.${SN}/root rootflags=rw,relatime rw console=tty1 console=ttyS1,115200n8 crashkernel=1024M,high audit=1 audit_backlog_limit=8192 lsm=landlock,selinux enforcing=1 fips=1
EOF

cat > /etc/crypttab <<EOF
luks-${UUID} UUID=${UUID} none luks,tpm2-device=auto
EOF

cat > /etc/fstab <<EOF
UUID=$(blkid -o value -s UUID ${SYS_DISK}-part1) /boot vfat defaults,umask=0077,shortname=winnt,nodev,nosuid 0 0
/dev/vg.${SN}/root / xfs defaults,x-systemd.device-timeout=0 0 0
/dev/vg.${SN}/var /var xfs defaults,x-systemd.device-timeout=0 0 0
/dev/vg.${SN}/log /var/log xfs defaults,x-systemd.device-timeout=0 0 0
/dev/vg.${SN}/audit /var/log/audit xfs defaults,x-systemd.device-timeout=0 0 0
EOF

cat > /etc/kernel/uki.conf <<EOF
[UKI]
SecureBootSigningTool=sbsign
SecureBootPrivateKey=/root/.keystore/pki/secureboot/DCG_DB.key
SecureBootCertificate=/root/.keystore/pki/secureboot/DCG_DB.crt
EOF

USE="-openldap" emerge -jvbkUDut --keep-going @world && emerge -jvbkUDut --keep-going @world || exit 1
emerge -jvbk1 $(qlist -IU | grep " python_targets_python3_13" | awk '{ print $1 }' | tr '\n' ' ')
CLEAN_DELAY=0 emerge -c
eselect news read --quiet ; eselect news purge
eselect editor set vim

systemctl enable auditd

mkdir -p /etc/systemd/system/systemd-tpm2-setup.service.d
cat > /etc/systemd/system/systemd-tpm2-setup.service.d/env.conf <<EOF
[Service]
Environment=SYSTEMD_RELAX_XBOOTLDR_CHECKS=1
EOF

setsebool -P systemd_tmpfiles_manage_all on
setsebool -P global_ssp on

cp /usr/share/pam/security/faillock.conf /etc/security/faillock.conf
semanage fcontext -a -t etc_t /etc/security/faillock.conf

cat > /etc/pam.d/system-auth <<EOF
# %PAM-1.0
auth        required      pam_env.so
auth        optional      pam_group.so
auth        required      pam_faillock.so preauth silent
auth        sufficient    pam_unix.so nullok try_first_pass
-auth       sufficient    pam_sss.so forward_pass
auth        [default=die] pam_faillock.so authfail
auth        required      pam_deny.so

account     required      pam_nologin.so
account     required      pam_faillock.so
account     required      pam_unix.so
-account    [default=bad success=ok user_unknown=ignore] pam_sss.so
account     required      pam_permit.so

password    required      pam_passwdqc.so config=/etc/security/passwdqc.conf
password    sufficient    pam_unix.so try_first_pass yescrypt shadow use_authtok
-password   sufficient    pam_sss.so use_authtok
password    required      pam_deny.so

session     required      pam_limits.so
session     required      pam_env.so
session     required      pam_unix.so
-session    optional      pam_systemd.so
-session    optional      pam_sss.so
EOF

systemctl enable systemd-networkd

cat > /etc/systemd/timesyncd.conf <<EOF
[Time]
NTP=192.168.180.1
EOF
systemctl enable systemd-timesyncd

cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=192.168.180.1
DNS=192.168.181.13
Domains=largedata.net
DNSSEC=no
DNSOverTLS=no
LLMNR=no
EOF
systemctl enable systemd-resolved

systemctl enable sshd.socket
ssh-keygen -A
mkdir -p -m 0750 /root/.ssh && cat > /root/.ssh/authorized_keys <<EOF                                                                                                                                                            
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6fabrxoskifxFtfW/9U9pr2xHsTCcdb1nhzgYm1m6t dkleiner@briar
EOF

useradd -G wheel toor
semanage login -a -s staff_u toor
printf "toor:$(openssl rand -base64 32)" | chpasswd
mkdir -m 0750 /home/toor/.ssh && cat > /home/toor/.ssh/authorized_keys <<EOF                                                                                                                                                            
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6fabrxoskifxFtfW/9U9pr2xHsTCcdb1nhzgYm1m6t dkleiner@briar
EOF
chown -R toor:toor /home/toor/.ssh

semanage login -a -s root root
sed -i -e 's/^root.*/root ALL=(ALL:ALL) ROLE=sysadm_r TYPE=sysadm_t NOPASSWD: ALL/g' /etc/sudoers

setfiles -v /etc/selinux/mcs/contexts/files/file_contexts /

gpgconf --homedir /etc/portage/gnupg --kill all
gpgconf --homedir /root/.keystore/gpg --kill all

### EMERGE, BUILD, INSTALL KERNEL

rm -fr /etc/resolv.conf
EOC

printf "${HOST}\n" > /mnt/etc/hostname
cat > /mnt/etc/systemd/network/mgmt.network <<EOF
[Match]
MACAddress=${MACADDRESS}

[Network]
Address=${IPADDRESS}
Gateway=${GATEWAY}

[Link]
MTUBytes=9000
EOF

sleep 1

umount -R /mnt/{dev{/pts,/shm,},var/tmp,tmp,proc,sys,run}
umount /mnt/root/.keystore
umount /mnt/boot
umount -R /mnt

cryptsetup close keystore

# efibootmgr -v -c -b 0 -d /dev/sda -L Gentoo -l \\EFI\\Linux\\gentoo-6.18.35-gentoo-dist-bin.efi