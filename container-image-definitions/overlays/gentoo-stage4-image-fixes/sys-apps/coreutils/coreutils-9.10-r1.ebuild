# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Try to keep an eye on Fedora's packaging: https://src.fedoraproject.org/rpms/coreutils
# The upstream coreutils maintainers also maintain the package in Fedora and may
# backport fixes which we want to pick up.
#
# Also recommend subscribing to the coreutils and bug-coreutils MLs.

PYTHON_COMPAT=( python3_{11..13} )
VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/coreutils.asc
inherit branding flag-o-matic python-any-r1 toolchain-funcs verify-sig

MY_PATCH="${PN}-9.6-patches"
DESCRIPTION="Standard GNU utilities (chmod, cp, dd, ls, sort, tr, head, wc, who,...)"
HOMEPAGE="https://www.gnu.org/software/coreutils/"

if [[ ${PV} == 9999 ]] ; then
	EGIT_REPO_URI="https://git.savannah.gnu.org/git/coreutils.git"
	inherit git-r3
elif [[ ${PV} == *_p* ]] ; then
	# Note: could put this in devspace, but if it's gone, we don't want
	# it in tree anyway. It's just for testing.
	MY_SNAPSHOT="$(ver_cut 1-2).327-71a8c"
	SRC_URI="https://www.pixelbeat.org/cu/coreutils-${MY_SNAPSHOT}.tar.xz -> ${P}.tar.xz"
	SRC_URI+=" verify-sig? ( https://www.pixelbeat.org/cu/coreutils-${MY_SNAPSHOT}.tar.xz.sig -> ${P}.tar.xz.sig )"
	S="${WORKDIR}"/${PN}-${MY_SNAPSHOT}
else
	SRC_URI="
		mirror://gnu/${PN}/${P}.tar.xz
		verify-sig? ( mirror://gnu/${PN}/${P}.tar.xz.sig )
	"

	KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~m68k ~mips ppc ppc64 ~riscv ~s390 ~sparc x86"
fi

SRC_URI+=" !vanilla? ( https://dev.gentoo.org/~sam/distfiles/${CATEGORY}/${PN}/${MY_PATCH}.tar.xz )"

LICENSE="GPL-3+"
SLOT="0"
IUSE="acl caps gmp hostname kill multicall nls +openssl selinux +split-usr static test test-full vanilla xattr"
RESTRICT="!test? ( test )"

LIB_DEPEND="
	acl? ( sys-apps/acl[static-libs] )
	caps? ( sys-libs/libcap )
	gmp? ( dev-libs/gmp:=[static-libs] )
	openssl? ( dev-libs/openssl:=[static-libs] )
	xattr? ( sys-apps/attr[static-libs] )
"
RDEPEND="
	!static? ( ${LIB_DEPEND//\[static-libs]} )
	selinux? ( sys-libs/libselinux )
	nls? ( virtual/libintl )
"
DEPEND="
	${RDEPEND}
	static? ( ${LIB_DEPEND} )
"
BDEPEND="
	app-arch/xz-utils
	dev-lang/perl
	test? (
		dev-debug/strace
		dev-lang/perl
		dev-perl/Expect
		${PYTHON_DEPS}
	)
	verify-sig? ( sec-keys/openpgp-keys-coreutils )
"
RDEPEND+="
	hostname? ( !sys-apps/net-tools[hostname] )
	kill? (
		!sys-apps/util-linux[kill]
		!sys-process/procps[kill]
	)
	!<sys-apps/util-linux-2.13
	!<sys-apps/sandbox-2.10-r4
	!sys-apps/stat
	!net-mail/base64
	!sys-apps/mktemp
	!<app-forensics/tct-1.18-r1
	!<net-fs/netatalk-2.0.3-r4
	!<sys-apps/shadow-4.19.0_rc1
"

QA_CONFIG_IMPL_DECL_SKIP=(
	# gnulib FPs (bug #898370)
	unreachable MIN alignof static_assert
)

pkg_setup() {
	if use test ; then
		python-any-r1_pkg_setup
	fi
}

src_unpack() {
	if [[ ${PV} == 9999 ]] ; then
		git-r3_src_unpack

		cd "${S}" || die
		./bootstrap || die

		sed -i -e "s:submodule-checks ?= no-submodule-changes public-submodule-commit:submodule-checks ?= no-submodule-changes:" gnulib/top/maint.mk || die
	elif use verify-sig ; then
		# Needed for downloaded patch (which is unsigned, which is fine)
		verify-sig_verify_detached "${DISTDIR}"/${P}.tar.xz{,.sig}
	fi

	default
}

src_prepare() {
	# TODO: past 2025, we may need to add our own hack for bug #907474.
	local PATCHES=(
		"${FILESDIR}"/${PN}-9.5-skip-readutmp-test.patch
		# Upstream patches
		"${FILESDIR}"/${PN}-9.10-dash-tests.patch
	)

	if ! use vanilla && [[ -d "${WORKDIR}"/${MY_PATCH} ]] ; then
		PATCHES+=( "${WORKDIR}"/${MY_PATCH} )
	fi

	default

	# Since we've patched many .c files, the make process will try to
	# re-build the manpages by running `./bin --help`.  When doing a
	# cross-compile, we can't do that since 'bin' isn't a native bin.
	#
	# Also, it's not like we changed the usage on any of these things,
	# so let's just update the timestamps and skip the help2man step.
	set -- man/*.x
	touch ${@/%x/1} || die

	# Avoid perl dep for compiled in dircolors default (bug #348642)
	if ! has_version dev-lang/perl ; then
		touch src/dircolors.h || die
		touch ${@/%x/1} || die
	fi
}

src_configure() {
	# Running Valgrind in an ebuild is too unreliable. Skip such tests.
	cat <<-EOF >> init.cfg || die
	require_valgrind_()
	{
		skip_ "requires a working valgrind"
	}
	EOF

	# TODO: in future (>9.4?), we may want to wire up USE=systemd:
	# still experimental at the moment, but:
	# https://git.savannah.gnu.org/cgit/coreutils.git/commit/?id=85edb4afbd119fb69a0d53e1beb71f46c9525dd0
	local myconf=(
		--with-packager-version="${PVR} (p${PATCH_VER:-0})"
		# kill/uptime - procps
		# hostname    - net-tools
		--enable-install-program="arch,$(usev hostname),$(usev kill)"
		--enable-no-install-program="$(usev !hostname),$(usev !kill),su,uptime"
		$(usev !caps --disable-libcap)
		$(use_enable nls)
		$(use_enable acl)
		$(use_enable multicall single-binary)
		$(use_enable xattr)
		$(use_with gmp libgmp)
		$(use_with openssl)
		$(use_with selinux)
	)

	if use gmp ; then
		myconf+=( --with-libgmp-prefix="${ESYSROOT}"/usr )
	fi

	if tc-is-cross-compiler && [[ ${CHOST} == *linux* ]] ; then
		# bug #311569
		export fu_cv_sys_stat_statfs2_bsize=yes
		# bug #416629
		export gl_cv_func_realpath_works=yes
	fi

	# bug #409919
	export gl_cv_func_mknod_works=yes

	if use static ; then
		append-ldflags -static
		# bug #321821
		sed -i '/elf_sys=yes/s:yes:no:' configure || die
	fi

	# TODO: Drop CONFIG_SHELL for bash after 9.10
	# https://cgit.git.savannah.gnu.org/cgit/coreutils.git/commit/?id=a72ad1216d8cf96be542e2e7a4dd1d6151d6087b
	CONFIG_SHELL="${BROOT}"/bin/bash econf "${myconf[@]}"
}

src_test() {
	# Non-root tests will fail if the full path isn't
	# accessible to non-root users
	chmod -R go-w "${WORKDIR}" || die
	chmod a+rx "${WORKDIR}" || die

	# coreutils tests like to do `mount` and such with temp dirs,
	# so make sure:
	# - /etc/mtab is writable (bug #265725)
	# - /dev/loop* can be mounted (bug #269758)
	mkdir -p "${T}"/mount-wrappers || die
	mkwrap() {
		local w ww
		for w in "${@}" ; do
			ww="${T}/mount-wrappers/${w}"
			cat <<-EOF > "${ww}"
				#!${EPREFIX}/bin/sh
				exec env SANDBOX_WRITE="\${SANDBOX_WRITE}:/etc/mtab:/dev/loop" $(type -P ${w}) "\$@"
			EOF
			chmod a+rx "${ww}" || die
		done
	}
	mkwrap mount umount

	addwrite /dev/full

	local -x RUN_{VERY_,}EXPENSIVE_TESTS=$(usex test-full yes no)
	local -x PATH="${T}/mount-wrappers:${PATH}"
	local -x gl_public_submodule_commit=

	local xfail_tests=()

	if [[ -n ${SANDBOX_ACTIVE} ]]; then
		xfail_tests+=(
			tests/env/env-S
			tests/env/env-S.pl
		)
	fi

	cat > tests/tty/tty-eof.pl <<-EOF || die
	#!/usr/bin/perl
	exit 77;
	EOF

	emake -k check \
		VERBOSE=yes \
		DISABLE_HARD_ERRORS=yes \
		XFAIL_TESTS="${xfail_tests[*]}"
}

src_install() {
	default

	insinto /etc
	newins src/dircolors.hin DIR_COLORS

	local merged_usr=0
	if [[ -L "${ROOT%/}/bin" ]] && [[ "$(readlink -f "${ROOT%/}/bin")" == "$(readlink -f "${ROOT%/}/usr/bin")" ]]; then
		merged_usr=1
	fi

	# On merged-usr build roots, upstream and Portage can both materialize
	# /bin and /usr/bin entries for the same utility during host-side BDEPEND
	# installs. Normalize that image tree back to /usr/bin before merge.
	if [[ ${merged_usr} -eq 1 ]] && [[ -d "${ED}/bin" ]]; then
		dodir /usr/bin
		shopt -s nullglob
		local merged_bin_entry merged_bin_name
		for merged_bin_entry in "${ED}"/bin/* ; do
			merged_bin_name="${merged_bin_entry##*/}"
			if [[ -e "${ED}/usr/bin/${merged_bin_name}" ]]; then
				rm -f "${merged_bin_entry}" || die "failed to drop duplicate /bin/${merged_bin_name}"
			else
				mv "${merged_bin_entry}" "${ED}/usr/bin/${merged_bin_name}" || die "failed to normalize /bin/${merged_bin_name}"
			fi
		done
		shopt -u nullglob
		rmdir "${ED}/bin" 2>/dev/null || true
	fi

	if use split-usr ; then
		cd "${ED}"/usr/bin || die
		dodir /bin

		# Move critical binaries into /bin (required by FHS)
		local fhs="cat chgrp chmod chown cp date dd df echo false ln ls
		           mkdir mknod mv pwd rm rmdir stty sync true uname"
		mv ${fhs} ../../bin/ || die "Could not move FHS bins!"

		if use hostname ; then
			mv hostname ../../bin/ || die
		fi

		if use kill ; then
			mv kill ../../bin/ || die
		fi

		# Move critical binaries into /bin (common scripts)
		local com="basename chroot cut dir dirname du env expr head mkfifo
		           mktemp readlink seq sleep sort tail touch tr tty vdir wc yes"
		mv ${com} ../../bin/ || die "Could not move common bins!"

		local x
		for x in ${com} uname ; do
			dosym ../../bin/${x} /usr/bin/${x}
		done
	fi
}

pkg_postinst() {
	ewarn "Make sure you run 'hash -r' in your active shells."
	ewarn "You should also re-source your shell settings for LS_COLORS"
	ewarn "  changes, such as: source /etc/profile"
}
