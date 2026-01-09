# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10..12} )
GO_IMPORT_PATH="github.com/utuhiro78/merge-ut-dictionaries"

inherit git-r3 go-module python-any-r1 xdg

DESCRIPTION="Fcitx5 Mozc wrapper with UT dictionary (including Jigyosyo)"
HOMEPAGE="https://github.com/google/mozc"

# Mozcの公式リポジトリ
EGIT_REPO_URI="https://github.com/google/mozc.git"

# 辞書生成ツールのリポジトリ
UT_REPO_URI="https://github.com/utuhiro78/merge-ut-dictionaries.git"

# 辞書のシードデータ（UT辞書の生成に必要な安定版データソース）
# Gentooのサンドボックス内でgit cloneを多用すると不安定になるため、主要な辞書データはtarballで取得します
NEOLOGD_URI="https://github.com/neologd/mozc-dict-neologd-ut/archive/refs/heads/master.tar.gz -> neologd-ut-master.tar.gz"
SUDACHI_URI="https://github.com/WorksApplications/SudachiDict/archive/refs/tags/v20241021.tar.gz -> sudachidict-v20241021.tar.gz"

# 日本郵便の住所データ (Shift-JIS)
JP_ZIP_URI="https://www.post.japanpost.jp/zipcode/dl/kogaki/zip/ken_all.zip"
JP_JIGYOSYO_URI="https://www.post.japanpost.jp/zipcode/dl/jigyosyo/zip/jigyosyo.zip"

SRC_URI="${NEOLOGD_URI}
	${SUDACHI_URI}
	${JP_ZIP_URI}
	${JP_JIGYOSYO_URI}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="" # Live ebuild
IUSE=""

# 依存関係
RDEPEND="
	app-i18n/fcitx5
	dev-qt/qtbase:6[gui,widgets]
	dev-qt/qtwayland:6
"
DEPEND="${RDEPEND}"
BDEPEND="
	${PYTHON_DEPS}
	>=dev-lang/go-1.18
	dev-build/bazelisk
	app-i18n/nkf
	sys-devel/clang
	virtual/pkgconfig
"

# Mozcはソースディレクトリ構造が特殊なため、抽出先を調整
src_unpack() {
	# 1. Mozcソースの取得
	git-r3_src_unpack

	# 2. UT辞書ツールのソース取得 (サブディレクトリへ)
	# git-r3を使ってツール自体も最新を取得します
	local EGIT_REPO_URI="${UT_REPO_URI}"
	local EGIT_CHECKOUT_DIR="${WORKDIR}/merge-ut-dictionaries"
	git-r3_src_unpack

	# 3. その他のアーカイブ（辞書データ・郵便データ）を展開
	default
}

src_prepare() {
	default

	# --- UT辞書ツールの準備 ---
	cd "${WORKDIR}/merge-ut-dictionaries" || die
	# 依存モジュールの準備
	go mod vendor || die

	# --- 郵便データの処理 (Shift-JIS -> UTF-8 & Jigyosyo統合) ---
	cd "${WORKDIR}" || die
	
	ebegin "Converting Japan Post CSVs to UTF-8"
	nkf -w --overwrite KEN_ALL.CSV || die
	nkf -w --overwrite JIGYOSYO.CSV || die
	eend $?

	ebegin "Merging Jigyosyo data into KEN_ALL format"
	# JIGYOSYO.CSVはKEN_ALL.CSVとカラム数が異なるため、単純結合できません。
	# merge-ut-dictionariesが期待するフォーマット(KEN_ALL互換)にawkで変換します。
	# KEN_ALL format: Code(1), OldZip(2), Zip(3), PrefKana(4), CityKana(5), TownKana(6), Pref(7), City(8), Town(9)...
	# JIGYOSYO format: Code(1), Kana(2), Kanji(3), Pref(4), City(5), Town(6), Banchi(7), Zip(8)...
	# ※ここでは簡易的に事業所名(Kanji)を町域部分にマッピングして辞書ツールに認識させます。
	
	awk -F',' 'BEGIN {OFS=","} {
		# Jigyosyoのカラムから必要な情報を抽出
		zip = $8
		pref_kana = "" # 事業所データには都道府県カナがない場合があるため空で代用または補完
		city_kana = ""
		town_kana = $2 # 事業所名カナ
		pref = $4
		city = $5
		town = $3 # 事業所名漢字
		
		# KEN_ALL形式に合わせて出力 (引用符 " を考慮)
		print $1, "000", zip, "\"\"", "\"\"", town_kana, pref, city, town, $9, $10, $11, $12, $13, $14
	}' JIGYOSYO.CSV > JIGYOSYO_CONVERTED.CSV
	
	# 結合
	cat KEN_ALL.CSV JIGYOSYO_CONVERTED.CSV > combined_zip.csv
	eend $?

	# --- Mozcソースの準備 ---
	cd "${S}" || die
	
	# BazelがPythonを見つけられるようにする
	python_setup
}

src_compile() {
	# --- 1. UT辞書の生成 ---
	ebegin "Building and running merge-ut-dictionaries"
	cd "${WORKDIR}/merge-ut-dictionaries" || die
	
	# ツール自体のビルド (-mod=vendorで依存解決)
	ego build -mod=vendor -o merge-ut-dictionaries src/main.go
	
	# 辞書生成の実行
	# Gentooサンドボックス内ではネットワークアクセスができないため、
	# ダウンロード済みデータを引数やパスで渡す必要がありますが、
	# このツールは特定のディレクトリ構造を期待することがあります。
	# ここでは、ツールが期待する入力ファイルを作成・配置して実行します。
	
	# データの配置 (ツールの仕様に合わせて調整)
	mkdir -p mozcdic-ut-neologd/seed
	cp "${WORKDIR}/mozc-dict-neologd-ut-master/seed/mozcdic-ut-neologd-ba.txt" mozcdic-ut-neologd/seed/
	
	mkdir -p sudachidict
	cp "${WORKDIR}/SudachiDict-v20241021/small_lex.csv" sudachidict/
	
	# 生成コマンド
	# --zipcodeフラグで作成した統合CSVを指定します
	./merge-ut-dictionaries \
		--mode=neologd \
		--zipcode="${WORKDIR}/combined_zip.csv" \
		--output="${WORKDIR}/mozcdic-ut.txt"
		
	eend $? || die "Failed to generate UT dictionary"

	# --- 2. 辞書の注入 ---
	ebegin "Injecting UT dictionary into Mozc source"
	# Mozcのデフォルト辞書を上書きします
	cp "${WORKDIR}/mozcdic-ut.txt" "${S}/src/data/dictionary_oss/dictionary00.txt" || die
	eend $?

	# --- 3. Mozcのビルド (Bazelisk使用) ---
	cd "${S}" || die
	
	# Bazelのオプション設定
	# 最新のMozc/AbseilはC++17以上を要求します
	export BAZEL_CXXOPTS="-std=c++17"
	
	# コンパイル
	# server: Mozcサーバー
	# gui/tool: 設定ツールなど
	# unix/fcitx5: Fcitx5モジュール
	bazelisk build \
		--config=oss_linux \
		--compilation_mode=opt \
		//src/server:mozc_server \
		//src/gui/tool:mozc_tool \
		//src/unix/fcitx5:fcitx5-mozc.so \
		|| die "Bazel build failed"
}

src_install() {
	cd "${S}" || die
	
	# 1. バイナリのインストール
	# bazel-bin はシンボリックリンクになっているため、実体を参照
	local BAZEL_BIN="bazel-bin"
	
	dobin "${BAZEL_BIN}/src/server/mozc_server"
	dobin "${BAZEL_BIN}/src/gui/tool/mozc_tool"
	
	# 2. Fcitx5モジュールのインストール
	exeinto /usr/lib/fcitx5
	doexe "${BAZEL_BIN}/src/unix/fcitx5/fcitx5-mozc.so"
	
	# 3. リソース・アイコンのインストール
	# Mozcはアイコンパスがハードコードされている場合があるため、標準的な場所に配置
	insinto /usr/share/icons/hicolor/128x128/apps
	newins src/data/images/product_icon_128bpp.png org.fcitx.Fcitx5.fcitx5-mozc.png
	newins src/data/images/product_icon_128bpp.png mozc.png
	
	insinto /usr/share/icons/hicolor/scalable/apps
	newins src/data/images/product_icon_32bpp.svg org.fcitx.Fcitx5.fcitx5-mozc.svg
	
	# 4. メタデータのインストール (Fcitx5が認識するために必要)
	insinto /usr/share/fcitx5/addon
	doins src/unix/fcitx5/fcitx5-mozc.conf
	
	insinto /usr/share/fcitx5/inputmethod
	doins src/unix/fcitx5/mozc.conf

	# 5. ドキュメント
	einstalldocs
}
