#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${USB_ID}-part2 ]] || { echo "USB Partition /dev/disk/by-id/${USB_ID}-part2 does not exist" ; exit 1 ; }

if [[ -t 0 ]] ; then
	read -sp "Passphrase: " P ; echo
else
	P=$(cat)
fi
[[ "${#P}" -ge 1 ]] || { echo "Passphrase empty" ; exit 1 ; }

if [[ ! -d ${USB_DIR}/boot ]] ; then
	mkdir -m 0755 -p ${USB_DIR}
	mount /dev/disk/by-id/${USB_ID}-part2 ${USB_DIR}
	mkdir -m 0 -p ${USB_DIR}/boot
	mount /dev/disk/by-id/${USB_ID}-part1 ${USB_DIR}/boot
fi
KEYSTORE=${USB_DIR}/root/.keystore
if [[ ! -b /dev/mapper/keystore ]] ; then
	cryptsetup open /dev/disk/by-id/${USB_ID}-part3 keystore <<<${P}
	mkdir -m 0 -p ${KEYSTORE}
	mount /dev/mapper/keystore ${KEYSTORE}
fi

if [[ ! -e ${USB_DIR}/etc/os-release ]] ; then
	LATEST_STAGE3=${AUTOBUILDS}/$(curl -fsSLo - ${AUTOBUILDS}/latest-stage3-amd64-hardened-selinux-systemd.txt | awk '/stage3/ { print $1 }')
	curl -fsSLo - ${LATEST_STAGE3} | tar -C ${USB_DIR} -Jxf -
fi

# LATEST_QCOW2=${AUTOBUILDS}/$(curl -fsSLo - ${AUTOBUILDS}/latest-qcow2.txt | awk '/console/ { print $1 }')
# QCOW2=${LATEST_QCOW2##*/}
# curl -fsSLo /tmp/${QCOW2} ${LATEST_QCOW2}
# guestmount -a /tmp/${QCOW2} -m /dev/sda2 -o nonempty --ro /mnt/usb/mnt
# guestmount -a /tmp/${QCOW2} -m /dev/sda1 -o nonempty --ro /mnt/usb/mnt/boot

cat /run/systemd/resolve/resolv.conf > ${USB_DIR}/etc/resolv.conf

mount --bind /dev ${USB_DIR}/dev
mount --bind /dev/pts ${USB_DIR}/dev/pts
mount --bind /proc ${USB_DIR}/proc
mount --bind /sys ${USB_DIR}/sys
mount --bind /run ${USB_DIR}/run
mount -t tmpfs tmpfs ${USB_DIR}/dev/shm
mount -t tmpfs tmpfs ${USB_DIR}/tmp
mount -t tmpfs tmpfs ${USB_DIR}/var/tmp

TERM=xterm chroot ${USB_DIR} <<"EOC"
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
COMMON_FLAGS="-O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

LC_MESSAGES="C.UTF-8"

FEATURES="buildpkg binpkg-signing getbinpkg binpkg-request-signature"
BINPKG_FORMAT="gpkg"
BINPKG_GPG_SIGNING_GPG_HOME="/etc/portage/gnupg"
BINPKG_GPG_SIGNING_BASE_COMMAND="/usr/bin/flock /run/lock/portage-binpkg-gpg.lock /usr/bin/gpg --quiet --no-permission-warning --batch --sign --armor --pinentry-mode loopback --passphrase-file /etc/portage/gnupg/pass [PORTAGE_CONFIG]"
SECUREBOOT_SIGN_KEY="/root/.keystore/pki/secureboot/DCG_DB.key"
SECUREBOOT_SIGN_CERT="/root/.keystore/pki/secureboot/DCG_DB.crt"
EOF
printf "BINPKG_GPG_SIGNING_KEY=\"0x${DCG_SSB_ID}\"\n" >> /etc/portage/make.conf

emerge-webrsync && eselect news read --quiet ; eselect news purge

mkdir -p /var/db/repos/dcg2
curl -fsSLo - https://github.com/dardok/dcg2/archive/refs/heads/main.zip | \
	bsdtar -C /var/db/repos/dcg2 -xf - --strip-components=1
chown -R portage:portage /var/db/repos/dcg2

[ -h /etc/portage/make.profile ] && rm -f /etc/portage/make.profile
mkdir -p /etc/portage/make.profile
echo 8 > /etc/portage/make.profile/eapi
cat > /etc/portage/make.profile/parent <<-EOF
dcg2:dcg/bootstrap
EOF

mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/dcg2.conf <<-EOF
[dcg2]
location = /var/db/repos/dcg2
masters = gentoo
priority = 100
EOF

mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/gentoobinhost.conf <<-EOF
[gentoobinhost]
priority = 1
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
EOF

mkdir -p /etc/portage/package.use
cat > /etc/portage/package.use/targets <<EOF
*/* PYTHON_TARGETS: -* python3_14
*/* PYTHON_SINGLE_TARGET: -* python3_14
EOF

# cat > /etc/kernel/cmdline <<EOF
# root=UUID=$(blkid -o value -s UUID /dev/disk/by-label/Gentoo) rootflags=rw rw console=ttyS0 audit=1 audit_backlog_limit=8192 lsm=landlock,selinux enforcing=0
# EOF

cat > /etc/kernel/cmdline <<EOF
root=UUID=$(blkid -o value -s UUID /dev/disk/by-label/Gentoo) rootflags=rw rw console=tty0 console=ttyS1,115200n8 audit=1 audit_backlog_limit=8192 lsm=landlock,selinux enforcing=0
EOF

cat > /etc/fstab <<EOF
LABEL=Gentoo / ext4 rw,noatime 0 1
EOF

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

mkdir -p /etc/systemd/system/{,serial-}getty@.service.d

cat > /etc/systemd/system/getty@.service.d/autologin.conf <<-"EOF"
[Service]
Environment=TERM=vt-utf8
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noreset --noclear --issue-file=/etc/issue:/etc/issue.d:/run/issue.d:/usr/lib/issue.d - ${TERM}
EOF

cat > /etc/systemd/system/serial-getty@.service.d/autologin.conf <<-"EOF"
[Service]
Environment=TERM=vt-utf8
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noreset --noclear --keep-baud 115200,57600,38400,9600 - ${TERM}
EOF

systemctl enable auditd

setsebool -P systemd_tmpfiles_manage_all on
setsebool -P global_ssp on

cat > /tmp/custom.te <<EOF
module custom 4.0;

require {
	type auditd_log_t;
	type bin_t;
	type boot_t;
	type cgroup_t;
	type default_t;
	type dosfs_t;
	type fs_t;
	type getty_t;
	type init_exec_t;
	type init_runtime_t;
	type init_t;
	type initrc_runtime_t;
	type kernel_t;
	type loadkeys_t;
	type local_login_t;
	type mount_runtime_t;
	type nsfs_t;
	type ntpd_t;
	type security_t;
	type syslogd_t;
	type systemd_generator_t;
	type systemd_logind_t;
	type systemd_networkd_t;
	type systemd_nsresourced_t;
	type systemd_pcrphase_t;
	type systemd_resolved_t;
	type systemd_tmpfiles_t;
	type systemd_userdbd_t;
	type tmpfs_t;
	type udev_t;
	type unconfined_t;
	class blk_file { getattr ioctl open read };
	class capability2 perfmon;
	class dir { create getattr open read relabelfrom relabelto search };
	class file { entrypoint getattr ioctl open read setattr write };
	class filesystem { getattr mount };
	class lnk_file { getattr read setattr };
	class netlink_kobject_uevent_socket { getattr read write };
	class process transition;
	class sock_file write;
	class unix_stream_socket { connectto read write };
}

#============= getty_t ==============
allow getty_t initrc_runtime_t:dir { getattr open read search };
allow getty_t tmpfs_t:dir { getattr open read search };

#============= init_t ==============
allow init_t unconfined_t:process transition;

#============= loadkeys_t ==============
allow loadkeys_t init_t:unix_stream_socket { read write };

#============= local_login_t ==============
allow local_login_t default_t:dir search;
allow local_login_t init_runtime_t:sock_file write;
allow local_login_t systemd_logind_t:unix_stream_socket connectto;

#============= ntpd_t ==============
allow ntpd_t cgroup_t:file { getattr open read write };

#============= syslogd_t ==============
allow syslogd_t cgroup_t:file { getattr open read write };
allow syslogd_t tmpfs_t:dir search;

#============= systemd_generator_t ==============
allow systemd_generator_t tmpfs_t:filesystem mount;
allow systemd_generator_t tmpfs_t:dir read;

#============= systemd_networkd_t ==============
allow systemd_networkd_t mount_runtime_t:dir search;

#============= systemd_nsresourced_t ==============
allow systemd_nsresourced_t cgroup_t:file { getattr open read write };
allow systemd_nsresourced_t fs_t:filesystem getattr;
allow systemd_nsresourced_t self:capability2 perfmon;

#============= systemd_pcrphase_t ==============
allow systemd_pcrphase_t boot_t:dir { getattr search };
allow systemd_pcrphase_t fs_t:filesystem getattr;
allow systemd_pcrphase_t init_runtime_t:dir create;
allow systemd_pcrphase_t nsfs_t:file getattr;
allow systemd_pcrphase_t tmpfs_t:dir { open read search };
allow systemd_pcrphase_t tmpfs_t:file { getattr open read };
allow systemd_pcrphase_t dosfs_t:dir { getattr search };
allow systemd_pcrphase_t dosfs_t:file { getattr open read };
allow systemd_pcrphase_t dosfs_t:filesystem getattr;

#============= systemd_resolved_t ==============
allow systemd_resolved_t cgroup_t:file { getattr open read write };
allow systemd_resolved_t systemd_networkd_t:unix_stream_socket connectto;

#============= systemd_tmpfiles_t ==============
allow systemd_tmpfiles_t auditd_log_t:dir { relabelfrom relabelto };
allow systemd_tmpfiles_t bin_t:lnk_file { getattr read };
allow systemd_tmpfiles_t security_t:lnk_file { getattr read setattr };

#============= systemd_userdbd_t ==============
allow systemd_userdbd_t cgroup_t:file { getattr open read write };

#============= udev_t ==============
allow udev_t kernel_t:netlink_kobject_uevent_socket { getattr read write };
allow udev_t tmpfs_t:file { getattr ioctl read write };

#============= unconfined_t ==============
allow unconfined_t init_exec_t:file entrypoint;
EOF

checkmodule -M -m -o /tmp/custom.mod /tmp/custom.te
semodule_package -o /tmp/custom.pp -m /tmp/custom.mod
semodule -i /tmp/custom.pp

cp /usr/share/pam/security/faillock.conf /etc/security/faillock.conf
semanage fcontext -a -t etc_t /etc/security/faillock.conf

cat > /etc/pam.d/system-auth <<EOF
auth        required      pam_env.so
auth        required      pam_faillock.so preauth silent
auth        sufficient    pam_unix.so nullok try_first_pass
auth        [default=die] pam_faillock.so authfail
auth        required      pam_deny.so

account     required      pam_nologin.so
account     required      pam_faillock.so
account     required      pam_unix.so
account     required      pam_permit.so

password    required      pam_passwdqc.so config=/etc/security/passwdqc.conf
password    sufficient    pam_unix.so try_first_pass yescrypt shadow
password    required      pam_deny.so

session     required      pam_limits.so
session     required      pam_env.so
session     required      pam_unix.so
-session     optional      pam_systemd.so
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

semanage login -a -s root root
sed -i -e 's/^root.*/root ALL=(ALL:ALL) ROLE=sysadm_r TYPE=sysadm_t NOPASSWD: ALL/g' /etc/sudoers

setfiles -v /etc/selinux/mcs/contexts/files/file_contexts /

gpgconf --homedir /etc/portage/gnupg --kill all
gpgconf --homedir /root/.keystore/gpg --kill all

rm -fr /etc/resolv.conf
EOC

printf "${HOST}\n" > ${USB_DIR}/etc/hostname
cat > ${USB_DIR}/etc/systemd/network/mgmt.network <<EOF
[Match]
MACAddress=${MACADDRESS}

[Network]
Address=${IPADDRESS}
Gateway=${GATEWAY}

[Link]
MTUBytes=9000
EOF

sleep 1

umount -R ${USB_DIR}/{dev{/pts,/shm,},var/tmp,tmp,proc,sys,run}
umount ${USB_DIR}/root/.keystore
umount ${USB_DIR}/boot
umount ${USB_DIR}

cryptsetup close keystore
