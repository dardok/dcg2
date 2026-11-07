# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=scikit-build-core
PYPI_PN=python-soxr
PYPI_VERIFY_REPO=https://github.com/dofuuz/python-soxr
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

LICENSE="LGPL-2.1+"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~x86"

IUSE="doc test"

# Runtime dependency on numpy, system libsoxr
RDEPEND="
	dev-python/numpy[${PYTHON_USEDEP}]
	media-libs/soxr
"

# Build dependencies
DEPEND="${RDEPEND}
	dev-python/nanobind[${PYTHON_USEDEP}]
	doc? (
		dev-python/sphinx[${PYTHON_USEDEP}]
		dev-python/sphinx-book-theme[${PYTHON_USEDEP}]
		dev-python/myst-parser[${PYTHON_USEDEP}]
		dev-python/linkify-it-py[${PYTHON_USEDEP}]
	)
	test? (
		dev-python/pytest[${PYTHON_USEDEP}]
	)
"

BDEPEND="
	dev-python/setuptools-scm[${PYTHON_USEDEP}]
	dev-python/typing-extensions[${PYTHON_USEDEP}]
"

DISTUTILS_ARGS=(                                                                                                                                                              
  -Ccmake.define.USE_SYSTEM_LIBSOXR=ON
)

distutils_enable_tests pytest

python_test() {
	epytest -v
}

python_install_all() {
	distutils-r1_python_install_all
	dodoc README.md
}

src_configure() {
	export SETUPTOOLS_SCM_PRETEND_VERSION=${PV}
	distutils-r1_src_configure
}
