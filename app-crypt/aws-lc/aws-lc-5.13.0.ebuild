EAPI=8

inherit cmake

DESCRIPTION="A general-purpose cryptographic library"
HOMEPAGE="https://github.com/aws/aws-lc"
SRC_URI="https://github.com/aws/${PN}/refs/tags/v${PV}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

DEPEND=""
RDEPEND="${DEPEND}"
