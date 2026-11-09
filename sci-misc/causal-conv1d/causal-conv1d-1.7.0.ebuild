# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..14} )
DISTUTILS_SINGLE_IMPL=1
inherit distutils-r1

DESCRIPTION="Causal depthwise conv1d in CUDA, with a PyTorch interface"
HOMEPAGE="https://github.com/Dao-AILab/causal-conv1d
	https://pypi.org/project/causal-conv1d/"
SRC_URI="https://codeload.github.com/Dao-AILab/${PN}/tar.gz/refs/tags/v${PV} -> ${P}.tar.gz"

LICENSE="BSD-3"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	sci-ml/pytorch[${PYTHON_SINGLE_USEDEP}]
	$(python_gen_cond_dep '
		dev-python/packaging[${PYTHON_USEDEP}]
	')
	dev-build/ninja
"
BDEPEND="
	$(python_gen_cond_dep '
		dev-python/setuptools[${PYTHON_USEDEP}]
		dev-python/wheel[${PYTHON_USEDEP}]
	')
"

distutils_enable_tests pytest
