# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..14} )
DISTUTILS_USE_PEP517=setuptools

inherit distutils-r1

DESCRIPTION="Python library for audio and music signal processing"
HOMEPAGE="https://librosa.org https://github.com/librosa/librosa"
SRC_URI="https://github.com/librosa/librosa/archive/refs/tags/${PV}.tar.gz -> ${P}.gh.tar.gz"

LICENSE="ISC"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~x86"

IUSE="doc test display"

# Core dependencies from setup.cfg install_requires
RDEPEND="
	dev-python/numba[${PYTHON_USEDEP}]
	dev-python/numpy[${PYTHON_USEDEP}]
	dev-python/scipy[${PYTHON_USEDEP}]
	dev-python/scikit-learn[${PYTHON_USEDEP}]
	dev-python/joblib[${PYTHON_USEDEP}]
	dev-python/decorator[${PYTHON_USEDEP}]
	dev-python/soundfile[${PYTHON_USEDEP}]
	dev-python/pooch[${PYTHON_USEDEP}]
	dev-python/soxr[${PYTHON_USEDEP}]
	dev-python/lazy-loader[${PYTHON_USEDEP}]
	dev-python/msgpack[${PYTHON_USEDEP}]
	display? ( dev-python/matplotlib[${PYTHON_USEDEP}] )
"

# Optional dependencies
DEPEND="${RDEPEND}
	doc? (
		dev-python/numpydoc[${PYTHON_USEDEP}]
		dev-python/sphinx[${PYTHON_USEDEP}]
		dev-python/matplotlib[${PYTHON_USEDEP}]
		dev-python/pydata-sphinx-theme[${PYTHON_USEDEP}]
		dev-python/sphinx-gallery[${PYTHON_USEDEP}]
		dev-python/sphinx-design[${PYTHON_USEDEP}]
		dev-python/mir-eval[${PYTHON_USEDEP}]
		dev-python/ipython[${PYTHON_USEDEP}]
		dev-python/sphinxcontrib-svg2pdfconverter[${PYTHON_USEDEP}]
		dev-python/sphinxcontrib-googleanalytics[${PYTHON_USEDEP}]
		dev-python/presets[${PYTHON_USEDEP}]
		dev-python/sphinx-copybutton[${PYTHON_USEDEP}]
		dev-python/myst-parser[${PYTHON_USEDEP}]
		dev-python/pandas[${PYTHON_USEDEP}]
		dev-python/umap-learn[${PYTHON_USEDEP}]
	)
	test? (
		dev-python/matplotlib[${PYTHON_USEDEP}]
		dev-python/packaging[${PYTHON_USEDEP}]
		dev-python/pytest-mpl[${PYTHON_USEDEP}]
		dev-python/pytest-cov[${PYTHON_USEDEP}]
		dev-python/pytest[${PYTHON_USEDEP}]
		dev-python/samplerate[${PYTHON_USEDEP}]
		dev-python/resampy[${PYTHON_USEDEP}]
		dev-python/scipy-stubs[${PYTHON_USEDEP}]
		dev-python/types-decorator[${PYTHON_USEDEP}]
	)
"

BDEPEND="
	test? (
		dev-python/pytest[${PYTHON_USEDEP}]
	)
"

distutils_enable_tests pytest

python_test() {
	local -a pytest_args=(
		-v
		--ignore=tests/test_display.py
		--ignore=tests/test_display_integration.py
		--ignore=tests/test_display_submodules.py
		-k "not display"
	)

	if use test; then
		pytest_args+=(
			-m "not display"
		)
	fi

	epytest "${pytest_args[@]}"
}

python_install_all() {
	distutils-r1_python_install_all
	dodoc README.md
}
