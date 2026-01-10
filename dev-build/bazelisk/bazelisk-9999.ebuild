# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3 go-module

DESCRIPTION="User-friendly launcher for Bazel"
HOMEPAGE="https://github.com/bazelbuild/bazelisk"
EGIT_REPO_URI="https://github.com/bazelbuild/bazelisk.git"

LICENSE="Apache-2.0"
SLOT="0"
# マスク解除のためにキーワードを設定
KEYWORDS="~amd64"
IUSE=""

# ネットワークサンドボックスを無効化 (Goモジュール取得のため)
RESTRICT="network-sandbox mirror"

# 新しめのGoを指定
BDEPEND=">=dev-lang/go-1.22"

src_unpack() {
	git-r3_src_unpack
	cd "${S}" || die
	
	# 依存関係の整合性を確保してからvendorディレクトリを作成
	ebegin "Tidying and vendoring Go modules"
	go mod tidy
	go mod vendor
	eend $? || die "go mod vendor failed"
}

src_compile() {
	# CGOを無効化して安定性を向上
	export CGO_ENABLED=0
	
	# バージョン情報を埋め込み、出力ファイル名を'bazelisk'に固定
	local my_ldflags="-X main.BazeliskVersion=git-${EGIT_VERSION}"
	
	# -mod=vendor: vendorディレクトリを強制使用
	# -o bazelisk: 出力バイナリ名を指定 (src_installでのdobin用)
	ego build -mod=vendor -o bazelisk -ldflags "${my_ldflags}"
}

src_install() {
	dobin bazelisk
	einstalldocs
}
