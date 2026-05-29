# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3

DESCRIPTION="Oracle Coherence Community Edition placeholder package"
HOMEPAGE="https://github.com/oracle/coherence"
EGIT_REPO_URI="https://github.com/oracle/coherence.git"

LICENSE="UPL-1.0"
SLOT="0"
KEYWORDS=""
RESTRICT="mirror test network-sandbox"

BDEPEND="
	virtual/jdk
	dev-java/maven-bin
"
RDEPEND="
	virtual/jre
"

src_compile() {
	die "oracle-coherence-ce is a placeholder; use the pinned Jenkins build workflow before unmasking"
}
