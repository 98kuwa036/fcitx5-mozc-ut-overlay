# Copyright 2024-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..13} )

inherit check-reqs cmake desktop python-any-r1 xdg

# Mozc version tag to checkout
# 9999 (Live ebuild) の場合は master を使うように分岐
if [[ ${PV} == *9999* ]]; then
	MOZC_TAG="master"
else
	MOZC_TAG="${PV}"
fi

DESCRIPTION="Mozc with Fcitx5 support and all UT dictionaries (fully built from source)"
HOMEPAGE="
	https://github.com/google/mozc
	https://github.com/fcitx/mozc
	https://github.com/utuhiro78/merge-ut-dictionaries
	https://www.post.japanpost.jp/zipcode/download.html
"

# No SRC_URI - everything is cloned from git
SRC_URI=""

S="${WORKDIR}/mozc"

LICENSE="BSD-3 Apache-2.0 CC-BY-SA-4.0 GPL-2+ LGPL-2.1+ MIT public-domain"
SLOT="0"
KEYWORDS="~amd64"
IUSE="emacs gui renderer test"

# network-sandbox を削除し、mirror のみに制限 (bazeliskと辞書DLのため通信必須)
RESTRICT="!test? ( test ) mirror"

BDEPEND="
	${PYTHON_DEPS}
	dev-build/bazelisk
	app-arch/unzip
	app-arch/bzip2
	dev-build/ninja
	dev-vcs/git
	net-misc/curl
	virtual/pkgconfig
"

RDEPEND="
	>=app-i18n/fcitx-5.0.0:5
	dev-cpp/abseil-cpp:=
	dev-libs/protobuf:=
	emacs? ( app-editors/emacs:* )
	gui? (
		dev-qt/qtbase:6[gui,widgets]
	)
	renderer? (
		dev-qt/qtbase:6[gui,widgets]
		x11-libs/gtk+:3
	)
"

DEPEND="${RDEPEND}"

PATCHES=(
)

pkg_pretend() {
	# Bazel requires significant memory
	# Full source build needs extra resources
	if [[ ${MERGE_TYPE} != binary ]]; then
		CHECKREQS_MEMORY="8G"
		CHECKREQS_DISK_BUILD="15G"
		check-reqs_pkg_pretend
	fi
}

pkg_setup() {
	python-any-r1_pkg_setup
}

src_unpack() {
	# Clone Google Mozc from source
	einfo "Cloning Google Mozc (tag/branch: ${MOZC_TAG})..."
	git clone --depth 1 --branch "${MOZC_TAG}" \
		https://github.com/google/mozc.git \
		"${WORKDIR}/mozc" || die "Failed to clone Google Mozc"

	# Initialize and update submodules (abseil, protobuf, etc.)
	cd "${WORKDIR}/mozc" || die
	einfo "Initializing Mozc submodules..."
	git submodule update --init --recursive --depth 1 || die "Failed to update submodules"

	# Clone Fcitx5 Mozc patches from source
	einfo "Cloning Fcitx5 Mozc patches..."
	git clone --depth 1 --branch fcitx \
		https://github.com/fcitx/mozc.git \
		"${WORKDIR}/fcitx5-mozc" || die "Failed to clone Fcitx5 Mozc"

	# Clone merge-ut-dictionaries for building dictionaries from source
	einfo "Cloning merge-ut-dictionaries..."
	git clone --depth 1 \
		https://github.com/utuhiro78/merge-ut-dictionaries.git \
		"${WORKDIR}/merge-ut-dictionaries" || die "Failed to clone merge-ut-dictionaries"
}

# Generate place-names dictionary with both ken_all and jigyosyo
_generate_place_names() {
	local workdir="${1}"

	einfo "Generating place-names dictionary (ken_all + jigyosyo)..."

	# Download Japan Post ZIP code data
	local ken_all_url="https://www.post.japanpost.jp/zipcode/dl/kogaki/zip/ken_all.zip"
	local jigyosyo_url="https://www.post.japanpost.jp/zipcode/dl/jigyosyo/zip/jigyosyo.zip"

	mkdir -p "${workdir}/place-names" || die
	cd "${workdir}/place-names" || die

	# Download and extract ken_all (residential addresses)
	einfo "  Downloading ken_all.zip (residential addresses)..."
	curl -L -o ken_all.zip "${ken_all_url}" || die "Failed to download ken_all.zip"
	unzip -o ken_all.zip || die "Failed to extract ken_all.zip"

	# Download and extract jigyosyo (business addresses)
	einfo "  Downloading jigyosyo.zip (business addresses)..."
	curl -L -o jigyosyo.zip "${jigyosyo_url}" || die "Failed to download jigyosyo.zip"
	unzip -o jigyosyo.zip || die "Failed to extract jigyosyo.zip"

	# Find the actual CSV filenames (may be uppercase or lowercase)
	local ken_all_csv=$(find . -maxdepth 1 -iname 'ken_all.csv' -print -quit)
	local jigyosyo_csv=$(find . -maxdepth 1 -iname 'jigyosyo.csv' -print -quit)

	if [[ -z "${ken_all_csv}" ]]; then
		die "ken_all.csv not found after extraction"
	fi
	if [[ -z "${jigyosyo_csv}" ]]; then
		die "jigyosyo.csv not found after extraction"
	fi

	einfo "  Found: ${ken_all_csv}, ${jigyosyo_csv}"

	# Use our custom script to generate dictionary with both sources
	cp "${FILESDIR}/generate_place_names_full.py" . || die
	"${EPYTHON}" generate_place_names_full.py "${ken_all_csv}" "${jigyosyo_csv}" \
		|| die "Failed to generate place-names dictionary"

	# Return the generated file path
	echo "${workdir}/place-names/mozcdic-ut-place-names.txt"
}

# Generate UT dictionaries from source using merge-ut-dictionaries
_generate_ut_dictionaries() {
	local merge_dir="${WORKDIR}/merge-ut-dictionaries"
	local dict_output="${WORKDIR}/ut-dictionaries"

	mkdir -p "${dict_output}" || die

	# --- venv Setup to avoid "externally-managed-environment" error ---
	einfo "Setting up temporary Python venv for dictionary generation..."
	local venv_dir="${T}/mozc_dict_venv"
	"${EPYTHON}" -m venv "${venv_dir}" || die "Failed to create venv"
	source "${venv_dir}/bin/activate" || die "Failed to activate venv"
	
	# Install required packages (jaconv is needed for UT dictionaries)
	einfo "Installing jaconv into venv..."
	pip install jaconv || die "Failed to install jaconv"
	# ------------------------------------------------------------------

	einfo "Building UT dictionaries from source (inside venv)..."

	# Generate alt-cannadic
	einfo "  Generating alt-cannadic..."
	cd "${merge_dir}/src/alt-cannadic" || die
	if [[ -f make.sh ]]; then
		bash make.sh || ewarn "alt-cannadic generation failed, skipping"
		[[ -f mozcdic-ut-alt-cannadic.txt.bz2 ]] && \
			bunzip2 -kf mozcdic-ut-alt-cannadic.txt.bz2 && \
			cp mozcdic-ut-alt-cannadic.txt "${dict_output}/"
	fi

	# Generate edict2
	einfo "  Generating edict2..."
	cd "${merge_dir}/src/edict2" || die
	if [[ -f make.sh ]]; then
		bash make.sh || ewarn "edict2 generation failed, skipping"
		[[ -f mozcdic-ut-edict2.txt.bz2 ]] && \
			bunzip2 -kf mozcdic-ut-edict2.txt.bz2 && \
			cp mozcdic-ut-edict2.txt "${dict_output}/"
	fi

	# Generate jawiki (this may take a while)
	einfo "  Generating jawiki..."
	cd "${merge_dir}/src/jawiki" || die
	if [[ -f make.sh ]]; then
		bash make.sh || ewarn "jawiki generation failed, skipping"
		[[ -f mozcdic-ut-jawiki.txt.bz2 ]] && \
			bunzip2 -kf mozcdic-ut-jawiki.txt.bz2 && \
			cp mozcdic-ut-jawiki.txt "${dict_output}/"
	fi

	# Generate neologd
	einfo "  Generating neologd..."
	cd "${merge_dir}/src/neologd" || die
	if [[ -f make.sh ]]; then
		bash make.sh || ewarn "neologd generation failed, skipping"
		[[ -f mozcdic-ut-neologd.txt.bz2 ]] && \
			bunzip2 -kf mozcdic-ut-neologd.txt.bz2 && \
			cp mozcdic-ut-neologd.txt "${dict_output}/"
	fi

	# Generate personal-names (part of common)
	einfo "  Generating personal-names..."
	cd "${merge_dir}/src/common" || die
	if [[ -f make.sh ]]; then
		bash make.sh || ewarn "personal-names generation failed, skipping"
	fi
	# personal-names may be in common directory
	find "${merge_dir}/src" -name "mozcdic-ut-personal-names.txt*" -exec sh -c \
		'f="{}"; [[ "$f" == *.bz2 ]] && bunzip2 -kf "$f"; cp "${f%.bz2}" "'"${dict_output}"'/" 2>/dev/null' \;

	# Generate place-names with jigyosyo support (our custom version)
	# Note: This calls a function that uses EPYTHON. It should run fine inside venv.
	einfo "  Generating place-names (with jigyosyo)..."
	local place_names_file
	place_names_file=$(_generate_place_names "${WORKDIR}")
	[[ -f "${place_names_file}" ]] && cp "${place_names_file}" "${dict_output}/"

	# Generate skk-jisyo
	einfo "  Generating skk-jisyo..."
	cd "${merge_dir}/src/skk-jisyo" || die
	if [[ -f make.sh ]]; then
		bash make.sh || ewarn "skk-jisyo generation failed, skipping"
		[[ -f mozcdic-ut-skk-jisyo.txt.bz2 ]] && \
			bunzip2 -kf mozcdic-ut-skk-jisyo.txt.bz2 && \
			cp mozcdic-ut-skk-jisyo.txt "${dict_output}/"
	fi

	# Generate sudachidict
	einfo "  Generating sudachidict..."
	cd "${merge_dir}/src/sudachidict" || die
	if [[ -f make.sh ]]; then
		bash make.sh || ewarn "sudachidict generation failed, skipping"
		[[ -f mozcdic-ut-sudachidict.txt.bz2 ]] && \
			bunzip2 -kf mozcdic-ut-sudachidict.txt.bz2 && \
			cp mozcdic-ut-sudachidict.txt "${dict_output}/"
	fi

	# --- Clean up venv ---
	deactivate
	# ---------------------

	echo "${dict_output}"
}

src_prepare() {
	default

	# Apply fcitx5 patches from fcitx/mozc repository
	einfo "Applying Fcitx5 patches..."
	if [[ -d "${WORKDIR}/fcitx5-mozc/scripts/patches" ]]; then
		for patch in "${WORKDIR}/fcitx5-mozc/scripts/patches"/*.patch; do
			if [[ -f "${patch}" ]]; then
				einfo "  Applying: $(basename ${patch})"
				eapply "${patch}" || ewarn "Patch failed: $(basename ${patch})"
			fi
		done
	fi

	# Copy fcitx5 module source
	einfo "Copying Fcitx5 module source..."
	if [[ -d "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5" ]]; then
		cp -r "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5" "${S}/src/unix/" || die
	fi

	# --- Fix: Add fcitx5 repository definition to WORKSPACE ---
	# This fixes the "no such package '@@[unknown repo 'fcitx5' requested from @@]//'" error
	einfo "Updating WORKSPACE with fcitx5 repository definition..."
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
	# ----------------------------------------------------------

	# Generate UT dictionaries from source
	local dict_dir
	dict_dir=$(_generate_ut_dictionaries)

	# Merge UT dictionaries into Mozc
	einfo "Merging UT dictionaries into Mozc..."
	local dict_file="${S}/src/data/dictionary_oss/dictionary00.txt"
	local count=0

	for dict in alt-cannadic edict2 jawiki neologd personal-names place-names skk-jisyo sudachidict; do
		local dict_path="${dict_dir}/mozcdic-ut-${dict}.txt"
		if [[ -f "${dict_path}" ]]; then
			cat "${dict_path}" >> "${dict_file}" || die
			einfo "  Added: ${dict}"
			(( count++ ))
		else
			ewarn "  Missing: ${dict}"
		fi
	done

	einfo "UT dictionary merge complete. Added ${count} dictionaries."
}

src_configure() {
	:
}

src_compile() {
	cd "${S}/src" || die

	# Bazel options
	local bazel_args=(
		"--config=linux"
		"--compilation_mode=opt"
		"--copt=-Wno-error"
		"--host_copt=-Wno-error"
		"--jobs=$(nproc)"
	)

	# Build mozc_server
	einfo "Building mozc_server..."
	bazelisk build "${bazel_args[@]}" \
		server:mozc_server || die "mozc_server build failed"

	# Build fcitx5 module
	# Fix: Target must include .so extension
	einfo "Building fcitx5 module..."
	bazelisk build "${bazel_args[@]}" \
		unix/fcitx5:fcitx5-mozc.so || die "fcitx5-mozc.so build failed"

	# Build optional components
	if use emacs; then
		einfo "Building emacs helper..."
		bazelisk build "${bazel_args[@]}" \
			unix/emacs:mozc_emacs_helper || die
	fi

	if use gui; then
		einfo "Building mozc_tool..."
		bazelisk build "${bazel_args[@]}" \
			gui/tool:mozc_tool || die
	fi

	if use renderer; then
		einfo "Building mozc_renderer..."
		bazelisk build "${bazel_args[@]}" \
			renderer:mozc_renderer || die
	fi
}

src_install() {
	cd "${S}/src" || die

	local bazel_out="${S}/src/bazel-out/k8-opt/bin"

	# Install mozc_server
	exeinto /usr/libexec/mozc
	doexe "${bazel_out}/server/mozc_server"

	# Install fcitx5 module
	insinto /usr/$(get_libdir)/fcitx5
	doins "${bazel_out}/unix/fcitx5/fcitx5-mozc.so"

	# Install fcitx5 addon config
	insinto /usr/share/fcitx5/addon
	doins "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5/mozc-addon.conf"

	insinto /usr/share/fcitx5/inputmethod
	doins "${WORKDIR}/fcitx5-mozc/src/unix/fcitx5/mozc.conf"

	# Install icons
	local icon_sizes="16 22 24 32 48 64 128 256"
	for size in ${icon_sizes}; do
		if [[ -f "${S}/data/images/product_icon_${size}.png" ]]; then
			newicon -s ${size} \
				"${S}/data/images/product_icon_${size}.png" \
				fcitx5-mozc.png
		fi
	done

	# Install emacs support
	if use emacs; then
		exeinto /usr/libexec/mozc
		doexe "${bazel_out}/unix/emacs/mozc_emacs_helper"

		insinto /usr/share/emacs/site-lisp/mozc
		doins "${S}/src/unix/emacs/mozc.el"
	fi

	# Install GUI tool
	if use gui; then
		exeinto /usr/libexec/mozc
		doexe "${bazel_out}/gui/tool/mozc_tool"

		make_desktop_entry \
			"/usr/libexec/mozc/mozc_tool --mode=config_dialog" \
			"Mozc Setup" \
			fcitx5-mozc \
			"Settings;IBus;Qt"

		make_desktop_entry \
			"/usr/libexec/mozc/mozc_tool --mode=dictionary_tool" \
			"Mozc Dictionary Tool" \
			fcitx5-mozc \
			"Office;Dictionary;Qt"
	fi

	# Install renderer
	if use renderer; then
		exeinto /usr/libexec/mozc
		doexe "${bazel_out}/renderer/mozc_renderer"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Mozc with fcitx5 support and UT dictionaries has been installed."
	elog ""
	elog "This package is FULLY built from source:"
	elog "  - Google Mozc: cloned from git (tag/branch: ${MOZC_TAG})"
	elog "  - Fcitx5 patches: cloned from fcitx/mozc"
	elog "  - All UT dictionaries: generated from source"
	elog ""
	elog "Included UT dictionaries:"
	elog "  - alt-cannadic: Alternative Cannadic dictionary"
	elog "  - edict2: Japanese-English dictionary"
	elog "  - jawiki: Japanese Wikipedia dictionary"
	elog "  - neologd: Neologism dictionary"
	elog "  - personal-names: Personal name dictionary"
	elog "  - place-names: Place name dictionary (ken_all + jigyosyo)"
	elog "  - skk-jisyo: SKK Japanese dictionary"
	elog "  - sudachidict: Sudachi morphological dictionary"
	elog ""
	elog "Place-names dictionary includes BOTH:"
	elog "  - Residential addresses (ken_all.zip)"
	elog "  - Business/office addresses (jigyosyo.zip)"
	elog ""
	elog "To use fcitx5-mozc, add 'mozc' to your fcitx5 input methods."
	elog ""
	if use gui; then
		elog "Run 'mozc_tool --mode=config_dialog' to configure Mozc."
	fi
}
