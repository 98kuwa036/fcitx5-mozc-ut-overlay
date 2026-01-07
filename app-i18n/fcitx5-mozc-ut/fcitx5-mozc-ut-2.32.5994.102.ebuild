# Copyright 2024-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..13} )

inherit check-reqs cmake desktop python-any-r1 xdg

# 最新版を取得するための設定
if [[ ${PV} == *9999* ]]; then
	MOZC_TAG="master"
else
	MOZC_TAG="${PV}"
fi

# Bazel 8以降の破壊的変更(Bzlmod強制)を回避するため、
# 安定してビルドできる 7.x 系を明示的に指定します。
export USE_BAZEL_VERSION=7.4.1

DESCRIPTION="Mozc with Fcitx5 support and all UT dictionaries (Ken_all + Jigyosyo)"
HOMEPAGE="https://github.com/google/mozc"

# ソースはすべてGitから取得するため空
SRC_URI=""

S="${WORKDIR}/mozc"

LICENSE="BSD-3 Apache-2.0 CC-BY-SA-4.0 GPL-2+ LGPL-2.1+ MIT public-domain"
SLOT="0"
KEYWORDS="~amd64"
IUSE="emacs gui renderer test"

# 辞書データのダウンロードとBazelによるビルドのためネットワーク必須
RESTRICT="!test? ( test ) mirror"

BDEPEND="
	${PYTHON_DEPS}
	dev-build/bazelisk
	app-arch/unzip
	app-arch/bzip2
	dev-build/ninja
	dev-vcs/git
	net-misc/curl
	net-misc/wget
	virtual/pkgconfig
"

RDEPEND="
	>=app-i18n/fcitx-5.0.0:5
	dev-cpp/abseil-cpp:=
	dev-libs/protobuf:=
	emacs? ( app-editors/emacs:* )
	gui? ( dev-qt/qtbase:6[gui,widgets] )
	renderer? (
		dev-qt/qtbase:6[gui,widgets]
		x11-libs/gtk+:3
	)
"
DEPEND="${RDEPEND}"

pkg_pretend() {
	if [[ ${MERGE_TYPE} != binary ]]; then
		CHECKREQS_MEMORY="8G"
		CHECKREQS_DISK_BUILD="16G"
		check-reqs_pkg_pretend
	fi
}

pkg_setup() {
	python-any-r1_pkg_setup
}

src_unpack() {
	# 1. Google Mozc (本体)
	einfo "Cloning Google Mozc..."
	git clone --depth 1 --branch "${MOZC_TAG}" \
		https://github.com/google/mozc.git "${S}" || die

	# サブモジュール (abseil, protobuf等) の初期化
	cd "${S}" || die
	git submodule update --init --recursive --depth 1 || die

	# 2. Fcitx5 パッチ
	einfo "Cloning Fcitx5 Mozc patches..."
	git clone --depth 1 --branch fcitx \
		https://github.com/fcitx/mozc.git "${WORKDIR}/fcitx5-mozc" || die

	# 3. UT辞書生成スクリプト
	einfo "Cloning merge-ut-dictionaries..."
	git clone --depth 1 \
		https://github.com/utuhiro78/merge-ut-dictionaries.git \
		"${WORKDIR}/merge-ut-dictionaries" || die
}

# 住所・事業所辞書の生成関数 (カスタム)
_generate_full_place_names() {
	local workdir="${1}"
	local dict_output="${2}"
	
	einfo "Generating FULL place-names dictionary (Residential + Business)..."
	mkdir -p "${workdir}/place-names-work"
	cd "${workdir}/place-names-work" || die

	# 日本郵便データのダウンロード
	local ken_url="https://www.post.japanpost.jp/zipcode/dl/kogaki/zip/ken_all.zip"
	local jigyo_url="https://www.post.japanpost.jp/zipcode/dl/jigyosyo/zip/jigyosyo.zip"

	wget -N "${ken_url}" || die "Failed to download ken_all"
	wget -N "${jigyo_url}" || die "Failed to download jigyosyo"

	unzip -o ken_all.zip || die
	unzip -o jigyosyo.zip || die

	local ken_csv=$(find . -iname 'ken_all.csv' | head -n1)
	local jigyo_csv=$(find . -iname 'jigyosyo.csv' | head -n1)

	# カスタムスクリプトの実行
	cp "${FILESDIR}/generate_place_names_full.py" . || die
	"${EPYTHON}" generate_place_names_full.py \
		"${ken_csv}" "${jigyo_csv}" \
		-o "${dict_output}/mozcdic-ut-place-names.txt" || die
}

src_prepare() {
	default

	# Fcitx5パッチの適用
	if [[ -d "${WORKDIR}/fcitx5-mozc/scripts/patches" ]]; then
		for p in "${WORKDIR}/fcitx5-mozc/scripts/patches"/*.patch; do
			eapply "${p}"
		done
	fi
	
	# Fcitx5ソースのコピー
	cp -r "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5" "${S}/src/unix/" || die

	# WORKSPACEファイルへのFcitx5定義追加 (重要)
	cat >> "${S}/src/WORKSPACE" <<EOF
new_local_repository(
    name = "fcitx5",
    path = "/usr/include/fcitx5",
    build_file_content = """
cc_library(
    name = "fcitx5",
    hdrs = glob(["**/*.h"]),
    visibility = ["//visibility:public"],
)
""",
)
EOF

	# --- 辞書生成プロセス (venv内で実行) ---
	local dict_out="${WORKDIR}/dictionaries"
	mkdir -p "${dict_out}"

	# venv作成
	python -m venv "${T}/venv" || die
	source "${T}/venv/bin/activate" || die
	
	# 依存パッケージインストール (jaconv必須)
	pip install --upgrade pip
	pip install jaconv || die

	# 各UT辞書の生成
	local merge_src="${WORKDIR}/merge-ut-dictionaries/src"
	local dicts=(alt-cannadic edict2 jawiki neologd skk-jisyo sudachidict)

	for d in "${dicts[@]}"; do
		einfo "Generating ${d}..."
		cd "${merge_src}/${d}" || die
		if [[ -f make.sh ]]; then
			# make.sh 内の sudo を無効化しつつ実行
			sed -i 's/sudo //g' make.sh
			bash make.sh || die "Failed to generate ${d}"
			
			# 生成物のコピー (.txt または .bz2)
			find . -name "mozcdic-ut-${d}.txt*" -exec cp {} "${dict_out}/" \;
		fi
	done
	
	# personal-names (common内)
	einfo "Generating personal-names..."
	cd "${merge_src}/common" || die
	if [[ -f make.sh ]]; then
		bash make.sh
		find . -name "mozcdic-ut-personal-names.txt*" -exec cp {} "${dict_out}/" \;
	fi

	# 住所+事業所辞書 (カスタム関数呼び出し)
	_generate_full_place_names "${WORKDIR}" "${dict_out}"

	deactivate

	# --- 辞書のマージ ---
	einfo "Merging all dictionaries..."
	cd "${dict_out}" || die
	# bzip2圧縮されているものを展開
	find . -name "*.bz2" -exec bunzip2 {} \;

	local target_dict="${S}/src/data/dictionary_oss/dictionary00.txt"
	
	for f in mozcdic-ut-*.txt; do
		if [[ -f "${f}" ]]; then
			einfo "  Appending ${f}..."
			cat "${f}" >> "${target_dict}" || die
		fi
	done
}

src_configure() { :; }

src_compile() {
	cd "${S}/src" || die

	local args=(
		"--config=linux"
		"--compilation_mode=opt"
		"--copt=-Wno-error"
		"--host_copt=-Wno-error"
		"--jobs=$(nproc)"
	)

	# サーバービルド
	bazelisk build "${args[@]}" server:mozc_server || die
	
	# Fcitx5モジュールビルド (.soターゲット指定)
	bazelisk build "${args[@]}" unix/fcitx5:fcitx5-mozc.so || die
	
	# ツール類
	use gui && bazelisk build "${args[@]}" gui/tool:mozc_tool
	use renderer && bazelisk build "${args[@]}" renderer:mozc_renderer
}

src_install() {
	cd "${S}/src" || die
	local out="bazel-out/k8-opt/bin"

	exeinto /usr/libexec/mozc
	doexe "${out}/server/mozc_server"
	
	insinto /usr/$(get_libdir)/fcitx5
	doins "${out}/unix/fcitx5/fcitx5-mozc.so"
	
	insinto /usr/share/fcitx5/addon
	doins "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5/mozc-addon.conf"
	insinto /usr/share/fcitx5/inputmethod
	doins "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5/mozc.conf"
	
	# アイコン
	for s in 32 48 128; do
		newicon -s ${s} "data/images/product_icon_${s}.png" fcitx5-mozc.png
	done

	if use gui; then
		doexe "${out}/gui/tool/mozc_tool"
		make_desktop_entry "/usr/libexec/mozc/mozc_tool --mode=config_dialog" "Mozc Setup" fcitx5-mozc "Settings;"
		make_desktop_entry "/usr/libexec/mozc/mozc_tool --mode=dictionary_tool" "Mozc Dictionary" fcitx5-mozc "Settings;"
	fi
	
	if use renderer; then
		doexe "${out}/renderer/mozc_renderer"
	fi
}
