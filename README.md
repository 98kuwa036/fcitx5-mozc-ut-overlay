# fcitx5-mozc-ut Gentoo Overlay

This overlay provides `fcitx5-mozc-ut` - Mozc with Fcitx5 support and **all** UT dictionaries from [utuhiro78's merge-ut-dictionaries](https://github.com/utuhiro78/merge-ut-dictionaries).

**Key Features:**
- **100% source build** - Everything is cloned from git and built from scratch
- Google Mozc: cloned from `google/mozc` repository
- Fcitx5 patches: cloned from `fcitx/mozc` repository
- UT dictionaries: generated from source via `merge-ut-dictionaries`
- Includes both residential (ken_all) AND business (jigyosyo) addresses

## Included UT Dictionaries

All 8 dictionaries are built from source:

| Dictionary | Description | Source |
|------------|-------------|--------|
| alt-cannadic | Alternative Cannadic dictionary | [mozcdic-ut-alt-cannadic](https://github.com/utuhiro78/mozcdic-ut-alt-cannadic) |
| edict2 | Japanese-English dictionary | [mozcdic-ut-edict2](https://github.com/utuhiro78/mozcdic-ut-edict2) |
| jawiki | Japanese Wikipedia dictionary | [mozcdic-ut-jawiki](https://github.com/utuhiro78/mozcdic-ut-jawiki) |
| neologd | Neologism dictionary (mecab-ipadic-NEologd) | [mozcdic-ut-neologd](https://github.com/utuhiro78/mozcdic-ut-neologd) |
| personal-names | Personal name dictionary | [mozcdic-ut-personal-names](https://github.com/utuhiro78/mozcdic-ut-personal-names) |
| **place-names** | Place name dictionary **(ken_all + jigyosyo)** | Custom build |
| skk-jisyo | SKK Japanese dictionary | [mozcdic-ut-skk-jisyo](https://github.com/utuhiro78/mozcdic-ut-skk-jisyo) |
| sudachidict | Sudachi morphological dictionary | [mozcdic-ut-sudachidict](https://github.com/utuhiro78/mozcdic-ut-sudachidict) |

## Place-Names Dictionary (Enhanced)

Unlike the upstream version, this overlay's place-names dictionary includes **both** data sources from [Japan Post](https://www.post.japanpost.jp/zipcode/download.html):

| Data Source | File | Description |
|-------------|------|-------------|
| Residential addresses | ken_all.zip | Standard postal code to address mapping |
| Business addresses | jigyosyo.zip | Business/office individual postal codes |

This means you can convert:
- Regular postal codes (e.g., 100-0001 -> Chiyoda-ku, Tokyo)
- Business-specific postal codes (e.g., major corporations, government offices)

## Installation

### 1. Add the overlay

Create the overlay configuration file:

```bash
sudo mkdir -p /etc/portage/repos.conf
```

Create `/etc/portage/repos.conf/fcitx5-mozc-ut.conf`:

```ini
[fcitx5-mozc-ut]
location = /var/db/repos/fcitx5-mozc-ut
sync-type = git
sync-uri = https://github.com/YOUR_USERNAME/fcitx5-mozc-ut-overlay.git
auto-sync = yes
```

Or manually clone:

```bash
sudo mkdir -p /var/db/repos
sudo git clone https://github.com/YOUR_USERNAME/fcitx5-mozc-ut-overlay.git /var/db/repos/fcitx5-mozc-ut
```

### 2. Unmask the package (if needed)

```bash
echo "app-i18n/fcitx5-mozc-ut ~amd64" | sudo tee -a /etc/portage/package.accept_keywords/fcitx5-mozc-ut
```

### 3. Install

```bash
sudo emerge -av app-i18n/fcitx5-mozc-ut
```

## USE Flags

| Flag | Description |
|------|-------------|
| `emacs` | Enable Emacs support |
| `gui` | Build mozc_tool GUI configuration tool |
| `renderer` | Build mozc_renderer for candidate window |

## Requirements

- Gentoo Linux (amd64)
- Fcitx5
- Bazel >= 6.4.0
- Git
- Qt6 (for gui/renderer USE flags)
- Network access during build
- **~15GB disk space** for full source build
- **~8GB RAM** recommended

## Build Notes

This ebuild performs a **full source build**, which means:
- All sources are cloned fresh from git repositories
- Google Mozc is built from the official repository with submodules
- Fcitx5 patches are applied from the fcitx/mozc repository
- All UT dictionaries are generated from their original sources
- Build time is significantly longer than binary packages
- Requires network access during emerge (uses `RESTRICT="network-sandbox"`)

### What Gets Cloned

| Repository | Branch/Tag | Purpose |
|------------|------------|---------|
| google/mozc | `${PV}` tag | Mozc core |
| fcitx/mozc | `fcitx` branch | Fcitx5 patches |
| utuhiro78/merge-ut-dictionaries | `main` | Dictionary generation |

## Configuration

After installation, add Mozc to your Fcitx5 input methods:

1. Run `fcitx5-configtool`
2. Add "Mozc" to your input method list
3. If using GUI tools: `mozc_tool --mode=config_dialog`

## Version

- Mozc: 2.32.5994.102 (cloned from git tag at emerge time)
- Fcitx5 patches: Latest from fcitx branch
- UT Dictionaries: Built from source at emerge time
- Japan Post Data: Downloaded fresh at emerge time

## License

- Mozc: BSD-3-Clause
- UT Dictionaries: Various (see individual repositories)
- Japan Post ZIP code data: Public domain (no copyright claimed by Japan Post)

## Credits

- [Google Mozc](https://github.com/google/mozc)
- [Fcitx Mozc](https://github.com/fcitx/mozc)
- [utuhiro78's UT Dictionaries](https://github.com/utuhiro78/merge-ut-dictionaries)
- [Japan Post ZIP Code Data](https://www.post.japanpost.jp/zipcode/download.html)
