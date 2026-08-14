# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..14} )
DISTUTILS_USE_PEP517=standalone
inherit distutils-r1

DESCRIPTION="Vectorized spatial vector file format I/O using GDAL/OGR"
HOMEPAGE="
	https://github.com/geopandas/pyogrio
	https://pyogrio.readthedocs.io/
"
SRC_URI="https://github.com/geopandas/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.gh.tar.gz"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64 ~x86"

BDEPEND="
	dev-python/cython
"
RDEPEND="
	dev-python/certifi
	dev-python/numpy
	dev-python/packaging
	sci-libs/gdal
"
