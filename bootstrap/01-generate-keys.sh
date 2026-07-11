#!/bin/bash

[[ ${BOOTSTRAP_DEBUG} ]] && set -x
[[ $(whoami) == 'root' ]] || { echo "${0} must be run as root!" ; exit 100 ; }

set -euo pipefail

DIR=$(dirname ${0})
. ${DIR}/vars.sh
[[ -e ${DIR}/.vars.sh ]] && . ${DIR}/.vars.sh

[[ -b /dev/disk/by-id/${USB_ID}-part3 ]] || { echo "USB Partition /dev/disk/by-id/${USB_ID}-part3 does not exist" ; exit 1 ; }

if [[ -t 0 ]] ; then
	read -sp "Passphrase: " P ; echo
else
	P=$(cat)
fi
[[ "${#P}" -ge 1 ]] || { echo "Passphrase empty" ; exit 1 ; }

if [[ ! -d ${USB_DIR}/boot ]] ; then
	mkdir -m 0755 -p ${USB_DIR}
	mount /dev/disk/by-id/${USB_ID}-part2 ${USB_DIR}
	# mkdir -m 0 -p ${USB_DIR}/boot
	# mount /dev/disk/by-id/${USB_ID}-part1 ${USB_DIR}/boot
fi
KEYSTORE=${USB_DIR}/root/.keystore
if [[ ! -b /dev/mapper/keystore ]] ; then
	cryptsetup open /dev/disk/by-id/${USB_ID}-part3 keystore <<<${P}
	mkdir -m 0 -p ${KEYSTORE}
	mount /dev/mapper/keystore ${KEYSTORE}
fi

## PKI

PKI_HOME=${KEYSTORE}/pki
if [[ ! -d ${PKI_HOME} ]] ; then
	URI=$(python -c "from urllib.parse import quote ; print(quote(','.join('${DN}'[1:].split('/')[::-1]).lower()))")

	mkdir -m 0700 ${PKI_HOME}

	cat > ${PKI_HOME}/openssl.cnf <<-EOF
	RANDFILE = /tmp/.rnd
	SAN = ""

	[ ca ]
	default_ca = DCG_ROOT_CA
	EOF

	N=1
	for CA in DCG_ROOT_CA DCG_ID_CA DCG_SW_CA ; do
		mkdir -p -m 700 ${PKI_HOME}/${CA}
		mkdir -p ${PKI_HOME}/${CA}/newcerts ${PKI_HOME}/${CA}/private
		chmod 750 ${PKI_HOME}/${CA}/private
		touch ${PKI_HOME}/${CA}/index.txt
		echo ${N}000000000 > ${PKI_HOME}/${CA}/serial
		echo ${N}000000000 > ${PKI_HOME}/${CA}/crlnumber
		N=$((N+1))

	[ "${CA}" == "DCG_ROOT_CA" ] && CERT=DCG_Root_CA_2
	[ "${CA}" == "DCG_ID_CA" ] && CERT=DCG_ID_CA_10
	[ "${CA}" == "DCG_SW_CA" ] && CERT=DCG_SW_CA_11

	cat >> ${PKI_HOME}/openssl.cnf <<-EOF

		[ ${CA} ]
		unique_subject = yes
		database = ${PKI_HOME}/${CA}/index.txt
		new_certs_dir = ${PKI_HOME}/${CA}/newcerts
		certificate = ${PKI_HOME}/${CA}/${CERT}.crt
		serial = ${PKI_HOME}/${CA}/serial
		crlnumber = ${PKI_HOME}/${CA}/crlnumber
		crl = ${PKI_HOME}/${CA}/${CERT}.crl
		private_key = ${PKI_HOME}/${CA}/private/${CERT}.key
		email_in_dn = no
		name_opt = ca_default
		cert_opt = ca_default
		default_days = 365
		default_crl_days = 30
		default_md = sha384
		preserve = no
		policy = policy_match
		EOF
	done

	cat >> ${PKI_HOME}/openssl.cnf <<-EOF

	[ policy_match ]
	countryName = match
	organizationName = match
	organizationalUnitName = match
	commonName = supplied

	####################################################################

	[ req ]
	distinguished_name = req_distinguished_name
	string_mask = utf8only

	[ req_distinguished_name ]
	countryName = Country Name
	countryName_default = US
	countryName_min = 2
	countryName_max = 2
	organizationName = Organization Name
	organizationName_default = Naval Research Laboratory
	0.organizationalUnitName = Organizational Unit Name #1
	0.organizationalUnitName_default = Center for Computational Science
	1.organizationalUnitName = Organizational Unit Name #2
	1.organizationalUnitName_default = Distributed Computing Group
	commonName = Common Name
	commonName_max = 64

	[ dcg_ca ]
	basicConstraints = critical, CA:true
	keyUsage = digitalSignature, keyCertSign, cRLSign

	[ dcg_id_ca ]
	basicConstraints = critical, CA:true, pathlen:0
	keyUsage = critical, digitalSignature, keyCertSign, cRLSign
	authorityKeyIdentifier = keyid:always, issuer
	policyConstraints = requireExplicitPolicy:0
	crlDistributionPoints = URI:http://crl.largedata.net/crl/DCG_ROOT_CA_2.crl,URI:ldap://ldap.largedata.net/${URI}%3Fcertificaterevocationlist%3Bbinary
	certificatePolicies = 2.16.840.1.101.2.1.11.39

	[ dcg_id_cert ]
	basicConstraints = CA:false
	keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
	extendedKeyUsage = clientAuth, codeSigning, emailProtection
	authorityKeyIdentifier = keyid:always, issuer
	crlDistributionPoints = URI:http://crl.largedata.net/crl/DCG_ID_CA_10.crl,URI:ldap://ldap.largedata.net/${URI}%3Fcertificaterevocationlist%3Bbinary
	certificatePolicies = 2.16.840.1.101.2.1.11.39
	subjectAltName = \${ENV::SAN}

	[ dcg_sw_ca ]
	basicConstraints = critical, CA:true, pathlen:0
	keyUsage = critical, digitalSignature, keyCertSign, cRLSign
	authorityKeyIdentifier = keyid:always, issuer
	policyConstraints = requireExplicitPolicy:0
	crlDistributionPoints = URI:http://crl.largedata.net/crl/DCG_ROOT_CA_2.crl,URI:ldap://ldap.largedata.net/${URI}%3Fcertificaterevocationlist%3Bbinary
	certificatePolicies = 2.16.840.1.101.2.1.11.36

	[ dcg_db_cert ]
	basicConstraints = critical, CA:FALSE
	keyUsage = critical, digitalSignature
	extendedKeyUsage = critical, codeSigning
	authorityKeyIdentifier = keyid:always, issuer

	[ dcg_sw_cert ]
	basicConstraints = CA:false
	keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
	extendedKeyUsage = serverAuth
	authorityKeyIdentifier = keyid:always, issuer
	crlDistributionPoints = URI:http://crl.largedata.net/crl/DCG_SW_CA_11.crl,URI:ldap://ldap.largedata.net/${URI}%3Fcertificaterevocationlist%3Bbinary
	certificatePolicies = 2.16.840.1.101.2.1.11.36
	subjectAltName = \${ENV::SAN}

	[ dcg_id_sw_cert ]
	basicConstraints = CA:false
	keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
	extendedKeyUsage = serverAuth, clientAuth
	authorityKeyIdentifier = keyid:always, issuer
	crlDistributionPoints = URI:http://crl.largedata.net/crl/DCG_SW_CA_11.crl,URI:ldap://ldap.largedata.net/${URI}%3Fcertificaterevocationlist%3Bbinary
	certificatePolicies = 2.16.840.1.101.2.1.11.36
	subjectAltName = \${ENV::SAN}
	EOF

	## CA cert
	openssl req -new -utf8 -config ${PKI_HOME}/openssl.cnf \
		-days 3650 -out ${PKI_HOME}/DCG_ROOT_CA/DCG_Root_CA_2.crt -extensions dcg_ca \
		-passout pass:"${P}" -newkey rsa:4096 -sha384 -x509 -quiet \
		-keyout ${PKI_HOME}/DCG_ROOT_CA/private/DCG_Root_CA_2.key -subj "${DN}/CN=DCG Root CA 2"
	( cd ${KEYSTORE} && ln -sfn DCG_ROOT_CA/DCG_Root_CA_2.crt ${PKI_HOME}/DCG_Root_CA_2.crt )

	## ID intermediate CA cert
	openssl ca -config ${PKI_HOME}/openssl.cnf -name DCG_ROOT_CA \
		-days 3650 -batch -out ${PKI_HOME}/DCG_ID_CA/DCG_ID_CA_10.crt -extensions dcg_id_ca \
		-passin pass:"${P}" -quiet -infiles <(
		openssl req -new -utf8 -config ${PKI_HOME}/openssl.cnf \
			-nodes -newkey rsa:4096 -sha384 -quiet \
			-keyout ${PKI_HOME}/DCG_ID_CA/private/DCG_ID_CA_10.key -subj "${DN}/CN=DCG ID CA-10" \
	)
	( cd ${KEYSTORE} && ln -sfn DCG_ID_CA/DCG_ID_CA_10.crt ${PKI_HOME}/DCG_ID_CA_10.crt )

	## ID SW intermediate CA cert
	openssl ecparam -name secp384r1 -genkey -out ${PKI_HOME}/DCG_SW_CA/private/DCG_SW_CA_11.key
	openssl ca -config ${PKI_HOME}/openssl.cnf -name DCG_ROOT_CA \
		-days 3650 -batch -out ${PKI_HOME}/DCG_SW_CA/DCG_SW_CA_11.crt -extensions dcg_sw_ca \
		-passin pass:"${P}" -quiet -infiles <(
		openssl req -new -utf8 -config ${PKI_HOME}/openssl.cnf \
			-key ${PKI_HOME}/DCG_SW_CA/private/DCG_SW_CA_11.key -sha384 -quiet \
			-subj "${DN}/CN=DCG SW CA-11"
	)
	( cd ${KEYSTORE} && ln -sfn DCG_SW_CA/DCG_SW_CA_11.crt ${PKI_HOME}/DCG_SW_CA_11.crt )

	### SECURE BOOT

	mkdir -p ${PKI_HOME}/secureboot

	## Secure Boot PK cert
	openssl req -new -utf8 -config ${PKI_HOME}/openssl.cnf \
		-days 3650 -out ${PKI_HOME}/secureboot/DCG_PK.crt \
		-nodes -newkey rsa:4096 -sha384 -x509 -quiet \
		-keyout ${PKI_HOME}/secureboot/DCG_PK.key -subj "${DN}/CN=DCG Secure Boot PK"

	## Secure Boot KEK cert
	openssl req -new -utf8 -config ${PKI_HOME}/openssl.cnf \
		-days 3650 -out ${PKI_HOME}/secureboot/DCG_KEK.crt \
		-nodes -newkey rsa:4096 -sha384 -x509 -quiet \
		-keyout ${PKI_HOME}/secureboot/DCG_KEK.key -subj "${DN}/CN=DCG Secure Boot KEK"

	## Secure Boot DB
	openssl ca -config ${PKI_HOME}/openssl.cnf -name DCG_SW_CA \
		-days 3650 -batch -out ${PKI_HOME}/secureboot/DCG_DB.crt -extensions dcg_db_cert \
		-quiet -infiles <(
		openssl req -new -utf8 -config ${PKI_HOME}/openssl.cnf \
			-nodes -newkey rsa:4096 -sha384 -quiet \
			-keyout ${PKI_HOME}/secureboot/DCG_DB.key -subj "${DN}/CN=DCG Secure Boot DB" \
	)
fi

## GPG

GNUPGHOME=${KEYSTORE}/gpg
if [[ ! -d ${GNUPGHOME} ]] ; then
	mkdir -m 0750 -p ${GNUPGHOME}

	kill_gpg_agent() {
		gpgconf --homedir ${GNUPGHOME} --kill all
	}
	trap kill_gpg_agent EXIT

	cat > ${GNUPGHOME}/dirmngr.conf <<-EOF
	honor-http-proxy
	no-use-tor
	standard-resolver
	resolver-timeout 90
	connect-timeout 90
	EOF

	cat > ${GNUPGHOME}/gpg-agent.conf <<-EOF
	disable-scdaemon
	EOF

	cat > ${GNUPGHOME}/gpg.conf <<-EOF
	no-greeting
	EOF

	PASS="$(openssl rand -base64 32)"

	gpg --homedir ${GNUPGHOME} --quiet --no-permission-warning --batch --generate-key <(cat <<-EOF
	Key-Type: RSA
	Key-Length: 3072
	Subkey-Type: RSA
	Subkey-Length: 3072
	Name-Real: DCG GPG Key
	Name-Email: dc-dev@cmf.nrl.navy.mil
	Expire-Date: 0
	Passphrase: ${PASS}
	%commit
	EOF
	)

	touch "${GNUPGHOME}/pass"
	chmod 600 "${GNUPGHOME}/pass"
	echo "${PASS}" > "${GNUPGHOME}/pass"

	gpgconf --homedir ${GNUPGHOME} --kill all
fi

sleep 1

umount ${USB_DIR}/root/.keystore
umount ${USB_DIR}

cryptsetup close keystore
