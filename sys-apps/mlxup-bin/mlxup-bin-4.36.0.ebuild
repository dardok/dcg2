# Copyright 2020-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN="${PN%-bin}"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Mellanox Update and Query Utility"
HOMEPAGE="https://www.mellanox.com/support/firmware/mlxup-mft"

SRC_URI="
	amd64? ( https://www.mellanox.com/downloads/firmware/${MY_PN}/${PV}/SFX/linux_x64/${MY_PN} -> ${MY_P}-amd64.elf )
	arm64? ( https://www.mellanox.com/downloads/firmware/${MY_PN}/${PV}/SFX/linux_arm64/${MY_PN} -> ${MY_P}-arm64.elf )
"

S="${WORKDIR}"
RESTRICT="strip"

LICENSE="Mellanox-AS-IS"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE=""

QA_PREBUILT="usr/sbin/${MY_PN}"

src_install() {
	if use amd64; then
		newsbin "${DISTDIR}/${MY_P}-amd64.elf" ${MY_PN}
	elif use arm64; then
		newsbin "${DISTDIR}/${MY_P}-arm64.elf" ${MY_PN}
	fi
}
