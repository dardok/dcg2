# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Official ODBC driver for PostgreSQL"
HOMEPAGE="https://odbc.postgresql.org/"
SRC_URI="https://codeload.github.com/postgresql-interfaces/psqlodbc/tar.gz/refs/tags/REL-18_00_0006 -> ${P}.tar.gz"
LICENSE="LGPL-2"
SLOT="0"
KEYWORDS="amd64 x86"
IUSE="iodbc ssl threads"

S="${WORKDIR}/psqlodbc-REL-17_00_0006"

DEPEND="dev-db/postgresql:*[ssl?]
		!iodbc? ( dev-db/unixODBC )
		iodbc? ( dev-db/libiodbc )
"
RDEPEND="${DEPEND}"

# Tests require installation and a server setup for the purpose.
RESTRICT="test"

DOCS=( readme.txt )
HTML_DOCS=(
	docs/config.html
	docs/config-opt.html
	docs/editConfiguration.jpg
	docs/release-7.3.html
	docs/release.html
)

src_configure() {
	econf \
		$(use_with iodbc) \
		$(use_with !iodbc unixodbc) \
		$(use_enable threads pthreads)
}
