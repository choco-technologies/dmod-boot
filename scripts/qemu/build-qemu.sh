#!/bin/bash
# Builds the Espressif QEMU fork (xtensa-softmmu only) with the patches of this directory.
#   usage: build-qemu.sh <install-dir>        -> <install-dir>/bin/qemu-system-xtensa, <install-dir>/share/qemu (ROMs)
# Needs: gcc, ninja, pkg-config, python3, libglib2.0-dev, libgcrypt20-dev, libpixman-1-dev, libslirp-dev
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$(mkdir -p "${1:?install dir}" && cd "$1" && pwd)"
REL=esp-develop-9.2.2-20261109
TAG=esp_develop_9.2.2_20261109
URL=https://github.com/espressif/qemu/releases/download/$REL
SRC_SHA256=8de22e32eccaccfdc4c3429abf9a3a546c76120fcf129ee8d66a75383e33bdc4
BIN_SHA256=fbc3bffa9fa71192847969a627a584aabe2e86d85bed4902a096ff06c2b8a815   # x86_64-linux-gnu binary release: the ROM images only
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
fetch() { curl -fsSL --retry 4 -o "$1" "$URL/$1"; echo "$2  $1" | sha256sum -c -; }

fetch qemu-esp_$TAG-src.tar.xz "$SRC_SHA256"
fetch qemu-xtensa-softmmu-esp_$TAG-x86_64-linux-gnu.tar.xz "$BIN_SHA256"
tar -xf qemu-esp_$TAG-src.tar.xz
tar -xf qemu-xtensa-softmmu-esp_$TAG-x86_64-linux-gnu.tar.xz
cd qemu-esp_$TAG-src
for p in "$HERE"/patches/*.patch; do patch -p1 < "$p"; done
mkdir build && cd build
../configure --target-list=xtensa-softmmu --disable-docs --disable-werror --disable-gtk --disable-sdl --disable-vnc \
    --disable-tools --disable-user --enable-gcrypt --prefix="$PREFIX"
ninja qemu-system-xtensa
mkdir -p "$PREFIX/bin" "$PREFIX/share"
cp qemu-system-xtensa "$PREFIX/bin/"
cp -r "$WORK"/qemu/share/qemu "$PREFIX/share/"
echo "QEMU installed in $PREFIX"
