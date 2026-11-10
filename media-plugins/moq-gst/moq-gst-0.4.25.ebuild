# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Media over QUIC (MoQ) GStreamer plugin (Official Binary Release)"
HOMEPAGE="https://github.com/moq-dev/moq"
SRC_URI="https://github.com/moq-dev/moq/releases/download/moq-gst-v0.4.25/moq-gst-v0.4.25-x86_64-unknown-linux-gnu.tar.gz -> ${P}.tar.gz"

LICENSE="MIT Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	>=media-libs/gstreamer-1.20:1.0
"

S="${WORKDIR}"

QA_PREBUILT="/usr/lib.*/gstreamer-1.0/libgstmoq.so"

src_install() {
	exeinto /usr/$(get_libdir)/gstreamer-1.0
	newexe "libgstmoq.so" "libgstmoq.so"
}
