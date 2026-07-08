#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${DISK_ID}-part2 ]] || { echo "Disk Partition /dev/disk/by-id/${DISK_ID}-part2 does not exist" ; exit 1 ; }
[[ -b /dev/disk/by-id/${USB_ID}-part3 ]] || { echo "USB Partition /dev/disk/by-id/${USB_ID}-part3 does not exist" ; exit 1 ; }

if [[ -t 0 ]] ; then
	read -sp "Passphrase: " P ; echo
else
	P=$(cat)
fi
[[ "${#P}" -ge 1 ]] || { echo "Passphrase empty" ; exit 1 ; }

SN=$(cat /sys/class/dmi/id/product_serial | tr '[A-Z]' ['a-z'])

UUID4=$(blkid -o value -s UUID /dev/vg.${SN}/audit)
cryptsetup -q open /dev/vg.${SN}/audit luks-${UUID4} <<<${P}
UUID3=$(blkid -o value -s UUID /dev/vg.${SN}/log)
cryptsetup -q open /dev/vg.${SN}/log luks-${UUID3} <<<${P}
UUID2=$(blkid -o value -s UUID /dev/vg.${SN}/var)
cryptsetup -q open /dev/vg.${SN}/var luks-${UUID2} <<<${P}
UUID1=$(blkid -o value -s UUID /dev/vg.${SN}/root)
cryptsetup -q open /dev/vg.${SN}/root luks-${UUID1} <<<${P}

if [[ ! -d /mnt/boot ]] ; then
	mkdir -m 0755 -p /mnt
	mount /dev/mapper/luks-${UUID1} /mnt
	mount /dev/mapper/luks-${UUID2} /mnt/var
	mount /dev/mapper/luks-${UUID3} /mnt/var/log
	mount /dev/mapper/luks-${UUID4} /mnt/var/log/audit
	mkdir -m 0 -p /mnt/boot
	mount /dev/disk/by-id/${DISK_ID}-part1 /mnt/boot
fi
KEYSTORE=/mnt/root/.keystore
if [[ ! -b /dev/mapper/keystore ]] ; then
	cryptsetup open /dev/disk/by-id/${USB_ID}-part3 keystore <<<${P}
	mkdir -m 0 -p ${KEYSTORE}
	mount /dev/mapper/keystore ${KEYSTORE}
fi

if [[ ! -e /mnt/etc/os-release ]] ; then
	LATEST_STAGE3=${AUTOBUILDS}/$(curl -fsSLo - ${AUTOBUILDS}/latest-stage3-amd64-hardened-selinux-systemd.txt | awk '/stage3/ { print $1 }')
	curl -fsSLo - ${LATEST_STAGE3} | tar -C /mnt -Jxf -
fi

cat /run/systemd/resolve/resolv.conf > /mnt/etc/resolv.conf

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

TERM=xterm chroot /mnt <<"EOC"
ln -sfn ../usr/share/zoneinfo/UTC /etc/localtime
printf "C\nen_US\n" > /etc/locale.gen
locale-gen && eselect locale set "en_US.UTF-8"
. /etc/profile

kill_gpg_agents() {
	gpgconf --homedir /etc/portage/gnupg --kill all
	gpgconf --homedir /root/.keystore/gpg --kill all
}
trap kill_gpg_agents EXIT

if [[ ! -d /etc/portage/gnupg ]] ; then
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
fi
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

FEATURES="buildpkg binpkg-signing getbinpkg binpkg-request-signature"
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

mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/gentoobinhost.conf <<-EOF
[gentoobinhost]
priority = 1
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
EOF

mkdir -p /var/cache/binhost
semanage fcontext -a -t portage_ebuild_t /var/cache/binhost

mkdir -p /etc/portage/package.use
cat > /etc/portage/package.use/targets <<EOF
*/* PYTHON_TARGETS: -* python3_14
*/* PYTHON_SINGLE_TARGET: -* python3_14
EOF

SN=$(cat /sys/class/dmi/id/product_serial | tr '[A-Z]' ['a-z'])

cat > /etc/kernel/cmdline <<EOF
root=UUID=$(blkid -o value -s UUID /dev/mapper/luks-$(blkid -o value -s UUID /dev/vg.${SN}/root)) rd.luks.uuid=$(blkid -o value -s UUID /dev/vg.${SN}/root) rd.luks.options=tpm2-device=auto rd.lvm.lv=vg.${SN}/root rootflags=rw rw console=tty0 console=ttyS1,115200n8 audit=1 audit_backlog_limit=8192 lsm=landlock,selinux enforcing=0
EOF

cat > /etc/fstab <<EOF
UUID=$(blkid -o value -s UUID /dev/sda1) /boot vfat defaults,umask=0077,shortname=winnt,nodev,nosuid 0 0
/dev/mapper/luks-$(blkid -o value -s UUID /dev/vg.${SN}/root) /              xfs defaults,x-systemd.device-timeout=0 0 0
/dev/mapper/luks-$(blkid -o value -s UUID /dev/vg.${SN}/var) /var           xfs defaults,nodev 0 0
/dev/mapper/luks-$(blkid -o value -s UUID /dev/vg.${SN}/log) /var/log       xfs defaults,nodev,noexec,nosuid 0 0
/dev/mapper/luks-$(blkid -o value -s UUID /dev/vg.${SN}/audit) /var/log/audit xfs defaults,nodev,noexec,nosuid 0 0
EOF

cat > /etc/crypttab <<EOF
luks-$(blkid -o value -s UUID /dev/vg.${SN}/root) UUID=$(blkid -o value -s UUID /dev/vg.${SN}/root) none luks,tpm2-device=auto
luks-$(blkid -o value -s UUID /dev/vg.${SN}/var) UUID=$(blkid -o value -s UUID /dev/vg.${SN}/var) none luks,tpm2-device=auto
luks-$(blkid -o value -s UUID /dev/vg.${SN}/log) UUID=$(blkid -o value -s UUID /dev/vg.${SN}/log) none luks,tpm2-device=auto
luks-$(blkid -o value -s UUID /dev/vg.${SN}/audit) UUID=$(blkid -o value -s UUID /dev/vg.${SN}/audit) none luks,tpm2-device=auto
EOF
ln -sfn crypttab /etc/crypttab.initramfs

cat > /etc/kernel/uki.conf <<EOF
[UKI]
SecureBootSigningTool=sbsign
SecureBootPrivateKey=/root/.keystore/pki/secureboot/DCG_DB.key
SecureBootCertificate=/root/.keystore/pki/secureboot/DCG_DB.crt
EOF

emerge -jvbkUDut --keep-going @world || emerge -jvbkUDut --keep-going @world
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
FallbackNTP=134.207.14.235 134.207.14.236
EOF
systemctl enable systemd-timesyncd

cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=192.168.181.13
DNS=192.168.180.1
FallbackDNS=134.207.14.160 134.207.14.161
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

efibootmgr -v -c -b 0 -d /dev/sda -L Gentoo -l \\EFI\\Linux\\gentoo-6.18.35-gentoo-dist-bin.efi