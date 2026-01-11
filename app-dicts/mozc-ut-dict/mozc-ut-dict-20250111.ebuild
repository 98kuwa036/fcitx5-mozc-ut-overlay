# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..13} )

inherit python-any-r1

DESCRIPTION="UT Dictionary Generator for Mozc (Includes Jigyosyo)"
HOMEPAGE="https://github.com/utuhiro78/merge-ut-dictionaries"

# 辞書生成に必要なソース
SRC_URI="
	https://www.post.japanpost.jp/zipcode/dl/kogaki/zip/ken_all.zip
	https://www.post.japanpost.jp/zipcode/dl/jigyosyo/zip/jigyosyo.zip
"

# ★重要: ソースディレクトリをクローン先に指定
S="${WORKDIR}/merge-ut-dictionaries"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE=""

# ネットワークアクセス許可 (git clone等のため)
RESTRICT="network-sandbox mirror"

BDEPEND="
	${PYTHON_DEPS}
	app-arch/unzip
	app-arch/bzip2
	net-misc/curl
	net-misc/wget
	dev-vcs/git
"

src_unpack() {
	# 1. 辞書ツールの取得 (クローン)
	git clone --depth 1 https://github.com/utuhiro78/merge-ut-dictionaries.git "${S}" || die
	
	# 2. 郵便番号データの展開
	# デフォルトの挙動で ${WORKDIR} に展開されます
	unpack ${A}
}

src_prepare() {
	default
	# 既存の ebuild で行っていた mv は不要になります (S を直接指定しているため)
}

src_compile() {
	# venv作成と依存ライブラリ(jaconv)のインストール
	python -m venv "${T}/venv" || die
	source "${T}/venv/bin/activate" || die
	pip install --upgrade pip
	pip install jaconv || die

	local dict_out="${T}/dictionaries"
	mkdir -p "${dict_out}"

	# 1. UT辞書の生成
	# S が merge-ut-dictionaries を指しているため、src はその直下
	local merge_src="${S}/src"
	local dicts=(alt-cannadic edict2 jawiki neologd skk-jisyo sudachidict)

	einfo "Generating UT dictionaries..."
	for d in "${dicts[@]}"; do
		cd "${merge_src}/${d}" || die
		if [[ -f make.sh ]]; then
			sed -i 's/sudo //g' make.sh
			bash make.sh || die "Failed to generate ${d}"
			find . -name "mozcdic-ut-${d}.txt*" -exec cp {} "${dict_out}/" \;
		fi
	done

	# personal-names
	cd "${merge_src}/common" || die
	bash make.sh && find . -name "mozcdic-ut-personal-names.txt*" -exec cp {} "${dict_out}/" \;

	# 2. 住所+事業所辞書の生成 (カスタムスクリプト)
	einfo "Generating Place/Jigyosyo dictionary..."
	# unpack された CSV は WORKDIR 直下にある
	local ken_csv=$(find "${WORKDIR}" -maxdepth 1 -iname 'ken_all.csv' | head -n1)
	local jigyo_csv=$(find "${WORKDIR}" -maxdepth 1 -iname 'jigyosyo.csv' | head -n1)
	
	# filesディレクトリにあるスクリプトを使用
	cp "${FILESDIR}/generate_place_names_full.py" . || die
	
	python generate_place_names_full.py \
		"${ken_csv}" "${jigyo_csv}" \
		-o "${dict_out}/mozcdic-ut-place-names.txt" || die

	# 3. 全辞書のマージ
	einfo "Merging all dictionaries..."
	cd "${dict_out}" || die
	find . -name "*.bz2" -exec bunzip2 {} \;
	
	# 最終的な辞書ファイルを作成
	cat mozcdic-ut-*.txt > dictionary00.txt || die
}

src_install() {
	insinto /usr/share/mozc-ut-dict
	doins "${T}/dictionaries/dictionary00.txt"
}
