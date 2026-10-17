#!/usr/bin/env bash
# Points the AUR recipe at a released version: downloads the tag tarball, updates pkgver,
# pkgrel and sha256sums, and regenerates .SRCINFO (needs makepkg, so run it on Arch).
# Usage: packaging/aur/update.sh 0.8.1
set -euo pipefail
version=${1:?usage: update.sh <version without v>}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
url="https://github.com/joaovitor-dv/universal-joystick-manager/archive/refs/tags/v$version.tar.gz"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/src.tar.gz" "$url"
sum=$(sha256sum "$tmp/src.tar.gz" | cut -d' ' -f1)
sed -i -e "s/^pkgver=.*/pkgver=$version/" -e "s/^pkgrel=.*/pkgrel=1/" -e "s/^sha256sums=.*/sha256sums=('$sum')/" "$here/PKGBUILD"
(cd "$here" && makepkg --printsrcinfo >.SRCINFO)
printf 'PKGBUILD and .SRCINFO now point at v%s (%s)\n' "$version" "$sum"
