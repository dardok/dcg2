# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..14} )
DISTUTILS_USE_PEP517=hatchling
inherit distutils-r1

DESCRIPTION="Python bindings for Media over QUIC (MoQ)"
HOMEPAGE="https://github.com"
SRC_URI="
	https://github.com/moq-dev/moq/archive/refs/tags/moq-ffi-v${PV}.tar.gz -> ${P}.gh.tar.gz
"

S="${WORKDIR}/moq-moq-ffi-v${PV}"

RDEPEND="
	>=dev-python/moq-ffi-${PV}[${PYTHON_USEDEP}]
"

LICENSE="MIT Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

src_configure() {
	cd "${S}/py/moq-rs" || die
	distutils-r1_src_configure
}

src_compile() {
	cd "${S}/py/moq-rs" || die
	distutils-r1_src_compile
}

src_test() {
	cd "${S}/py/moq-rs" || die
	distutils-r1_src_test
}

src_install() {
	cd "${S}/py/moq-rs" || die
	distutils-r1_src_install
}
