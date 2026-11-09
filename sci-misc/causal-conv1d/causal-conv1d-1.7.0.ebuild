# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{9..12} )
DISTUTILS_USE_PEP517=setuptools
inherit distutils-r1

DESCRIPTION="Causal depthwise conv1d in CUDA, with a PyTorch interface"
HOMEPAGE="https://github.com/Dao-AILab/causal-conv1d
	https://pypi.org/project/causal-conv1d/"
SRC_URI="https://codeload.github.com/Dao-AILab/${PN}/tar.gz/refs/tags/v${PV} -> ${P}.tar.gz"

LICENSE="BSD-3"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="
	dev-python/torch[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
	dev-python/ninja[${PYTHON_USEDEP}]
"
RDEPEND="${DEPEND}
	dev-python/torch[${PYTHON_USEDEP}]
"
BDEPEND="
	${PYTHON_DEPS}
	dev-python/setuptools[${PYTHON_USEDEP}]
	dev-python/wheel[${PYTHON_USEDEP}]
	dev-python/torch[${PYTHON_USEDEP}]
"

distutils_enable_tests pytest
