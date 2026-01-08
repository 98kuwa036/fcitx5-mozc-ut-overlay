# Copyright 2024-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..13} )

inherit check-reqs cmake desktop python-any-r1 xdg

# 最新版ビルドのためのタグ設定
if [[ ${PV} == *9999* ]]; then
	MOZC_TAG="master"
else
	MOZC_TAG="${PV}"
fi

# Bazel 8 の Bzlmod 問題を回避するため 7.x に固定
export USE_BAZEL_VERSION=7.4.1

DESCRIPTION="Mozc with Fcitx5 support and UT dictionaries (Ken_all + Jigyosyo)"
HOMEPAGE="https://github.com/google/mozc"
SRC_URI=""
S="${WORKDIR}/mozc"

LICENSE="BSD-3 Apache-2.0 CC-BY-SA-4.0 GPL-2+ LGPL-2.1+ MIT public-domain"
SLOT="0"
KEYWORDS="~amd64"
IUSE="emacs gui renderer test"

# ネットワークアクセス制限を解除
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
		CHECKREQS_DISK_BUILD="12G"
		check-reqs_pkg_pretend
	fi
}

pkg_setup() {
	python-any-r1_pkg_setup
}

src_unpack() {
	einfo "Cloning Google Mozc..."
	git clone --depth 1 --branch "${MOZC_TAG}" https://github.com/google/mozc.git "${S}" || die
	cd "${S}" || die
	git submodule update --init --recursive --depth 1 || die

	einfo "Cloning external resources..."
	git clone --depth 1 --branch fcitx https://github.com/fcitx/mozc.git "${WORKDIR}/fcitx5-mozc" || die
	git clone --depth 1 https://github.com/utuhiro78/merge-ut-dictionaries.git "${WORKDIR}/merge-ut-dictionaries" || die
}

_generate_full_place_names() {
	local workdir="${1}"
	local dict_output="${2}"
	
	einfo "Generating full place-names dictionary..."
	mkdir -p "${workdir}/place-names-work"
	cd "${workdir}/place-names-work" || die

	wget -N "https://www.post.japanpost.jp/zipcode/dl/kogaki/zip/ken_all.zip" || die
	wget -N "https://www.post.japanpost.jp/zipcode/dl/jigyosyo/zip/jigyosyo.zip" || die

	unzip -o ken_all.zip || die
	unzip -o jigyosyo.zip || die

	local ken_csv=$(find . -iname 'ken_all.csv' | head -n1)
	local jigyo_csv=$(find . -iname 'jigyosyo.csv' | head -n1)

	cp "${FILESDIR}/generate_place_names_full.py" . || die
	"${EPYTHON}" generate_place_names_full.py "${ken_csv}" "${jigyo_csv}" -o "${dict_output}/mozcdic-ut-place-names.txt" || die
}

src_prepare() {
	default

	# Fcitx5 パッチ適用
	if [[ -d "${WORKDIR}/fcitx5-mozc/scripts/patches" ]]; then
		for p in "${WORKDIR}/fcitx5-mozc/scripts/patches"/*.patch; do
			eapply "${p}"
		done
	fi
	cp -r "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5" "${S}/src/unix/" || die

	# ★ 重要: Bazel Visibility 文法エラーの強制的修正 ★
	# client/BUILD.bazel 内の不完全なリスト定義を完全に public に置き換える
	einfo "Forcing fix for Bazel visibility syntax errors..."
	# "Implicit string concatenation" と "expected ]" を防ぐため、
	# visibility 指定行を検索し、中身を単純化する
	sed -i '/visibility = \[/,/\]/c\    visibility = ["//visibility:public"],' "${S}/src/client/BUILD.bazel" || die
	# 念の為、他の主要なBUILDファイルも同様の処理を行う
	sed -i '/visibility = \[/,/\]/c\    visibility = ["//visibility:public"],' "${S}/src/session/BUILD.bazel" || die
	# --------------------------------------------------

	# WORKSPACE への Fcitx5 定義追加
	einfo "Updating WORKSPACE..."
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

	# 辞書生成 (venv使用)
	local dict_out="${WORKDIR}/dictionaries"
	mkdir -p "${dict_out}"

	python -m venv "${T}/venv" || die
	source "${T}/venv/bin/activate" || die
	pip install --upgrade pip
	pip install jaconv || die

	local merge_src="${WORKDIR}/merge-ut-dictionaries/src"
	local dicts=(alt-cannadic edict2 jawiki neologd skk-jisyo sudachidict)

	for d in "${dicts[@]}"; do
		cd "${merge_src}/${d}" || die
		[[ -f make.sh ]] && sed -i 's/sudo //g' make.sh && bash make.sh
		find . -name "mozcdic-ut-${d}.txt*" -exec cp {} "${dict_out}/" \;
	done
	
	cd "${merge_src}/common" || die
	[[ -f make.sh ]] && bash make.sh && find . -name "mozcdic-ut-personal-names.txt*" -exec cp {} "${dict_out}/" \;

	_generate_full_place_names "${WORKDIR}" "${dict_out}"
	deactivate

	# 辞書マージ
	cd "${dict_out}" || die
	find . -name "*.bz2" -exec bunzip2 {} \;
	local target_dict="${S}/src/data/dictionary_oss/dictionary00.txt"
	for f in mozcdic-ut-*.txt; do
		[[ -f "${f}" ]] && cat "${f}" >> "${target_dict}"
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

	bazelisk build "${args[@]}" server:mozc_server || die
	bazelisk build "${args[@]}" unix/fcitx5:fcitx5-mozc.so || die
	
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
	
	for s in 32 48 128; do
		newicon -s ${s} "data/images/product_icon_${s}.png" fcitx5-mozc.png
	done

	if use gui; then
		doexe "${out}/gui/tool/mozc_tool"
		make_desktop_entry "/usr/libexec/mozc/mozc_tool --mode=config_dialog" "Mozc Setup" fcitx5-mozc "Settings;"
		make_desktop_entry "/usr/libexec/mozc/mozc_tool --mode=dictionary_tool" "Mozc Dictionary" fcitx5-mozc "Settings;"
	fi
	
	use renderer && doexe "${out}/renderer/mozc_renderer"
}
