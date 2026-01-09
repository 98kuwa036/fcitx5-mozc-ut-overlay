# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3 go-module

DESCRIPTION="User-friendly launcher for Bazel"
HOMEPAGE="https://github.com/bazelbuild/bazelisk"
EGIT_REPO_URI="https://github.com/bazelbuild/bazelisk.git"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS=""
IUSE=""
# Goモジュールのダウンロードのためにネットワーク制限を解除
RESTRICT="network-sandbox mirror"

# Go言語が必要です
BDEPEND=">=dev-lang/go-1.18"

src_unpack() {
	git-r3_src_unpack
	cd "${S}" || die
	# ネットワークアクセス可能なunpackフェーズで依存解決
	ebegin "Vendoring Go modules"
	go mod vendor
	eend $? || die "go mod vendor failed"
}

src_compile() {
	# バージョン情報を埋め込んでビルド
	local my_ldflags="-X main.BazeliskVersion=git-${EGIT_VERSION}"
	ego build -ldflags "${my_ldflags}"
}

src_install() {
	dobin bazelisk
	einstalldocs
    # bazelシンボリックリンクは作成しない（競合回避のため賢明な判断です）
}
