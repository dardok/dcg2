# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( pypy3 python3_{12..14} )

inherit distutils-r1

DESCRIPTION="Kubernetes Client for Python"
HOMEPAGE="https://kubernetes.io/"
SRC_URI="https://github.com/kubernetes-client/python/archive/refs/tags/v${PV}.tar.gz"
S=${WORKDIR}/python-${PV}

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="amd64"
IUSE=""

DEPEND="
	>=dev-python/certifi-2026.7.22
	>=dev-python/python-dateutil-2.8.2
	>=dev-python/pydantic-2.13.4
	>=dev-python/setuptools-84.0.0
	>=dev-python/pyyaml-6.0.3
	>=dev-python/websocket-client-0.32.0
	!~dev-python/websocket-client-0.40.0
	!<dev-python/websocket-client-0.42.0
	dev-python/requests
	dev-python/requests-oauthlib
	>=dev-python/typing-extensions-4.16.0
	&& ( >=dev-python/urllib3-2.7.0 <dev-python/urllib3-3.0.0 )
	>=dev-python/durationpy-0.7
	&& ( >=dev-python/aiohttp-3.14.3 <dev-python/aiohttp-4.0.0 )
	aiohttp-retry>=2.9.1
"

python_install_all() {
	distutils-r1_python_install_all
}
