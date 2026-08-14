# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..14} )
DISTUTILS_USE_PEP517=setuptools
inherit distutils-r1 optfeature

DESCRIPTION="Python tools for geographic data"
HOMEPAGE="
	https://github.com/geopandas/geopandas
	https://pypi.org/project/geopandas/
"
SRC_URI="https://github.com/geopandas/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.gh.tar.gz"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64 ~x86"
RESTRICT="test" # 10 tests fail for 1.0.1

# upstream order
RDEPEND="
	>=dev-python/numpy-2[${PYTHON_USEDEP}]
	>=dev-python/pyogrio-0.8[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
	>=dev-python/pandas-2.2.0[${PYTHON_USEDEP}]
	>=dev-python/pyproj-3.7.0[${PYTHON_USEDEP}]
	>=dev-python/shapely-2.1.0[${PYTHON_USEDEP}]
"

EPYTEST_DESELECT=(
	# violates network sandbox
	geopandas/io/tests/test_file.py::test_read_file_url
	# fails with RuntimeError thrown by matplotlib
	geopandas/tests/test_plotting.py::TestGeoplotAccessor::test_pandas_kind

	# rtree results are known to be unordered, see False-expected1
	geopandas/tests/test_sindex.py::TestShapelyInterface::test_query_bulk_sorting
	geopandas/tests/test_sindex.py::TestShapelyInterface::test_query_sorting
)
distutils_enable_tests pytest

pkg_postinst() {
	optfeature "plotting" >=dev-python/matplotlib-3.5.0
	optfeature "geocoding" sci-geosciences/geopy
	elog "For full optional dependencies list visit"
	elog "https://geopandas.org/en/stable/getting_started/install.html#dependencies"
}
