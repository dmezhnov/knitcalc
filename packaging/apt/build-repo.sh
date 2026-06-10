#!/usr/bin/env bash
# Builds a .deb from the Flutter Linux bundle and a signed apt repository tree
# under $OUT_DIR/apt, served from GitHub Pages at /knitcalc/apt. The site is
# redeployed in full each release, so the repo is regenerated from scratch and
# only ever carries the latest version — apt just needs the current Packages to
# offer an upgrade (downgrades aren't a goal here).
#
# Inputs (env):
#   VERSION        full version, e.g. 1.8.24+47 (a valid Debian upstream version)
#   BUNDLE_DIR     Flutter Linux bundle (build/linux/x64/release/bundle)
#   OUT_DIR        directory that becomes the Pages root (apt/ is created inside)
#   GPG_KEY_ID     signing key, already imported into the active keyring
#   GPG_PASSPHRASE optional passphrase for that key (omit for a CI key with none)
set -euo pipefail

: "${VERSION:?}" "${BUNDLE_DIR:?}" "${OUT_DIR:?}" "${GPG_KEY_ID:?}"

here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

# Loopback lets gpg sign non-interactively; --passphrase is a no-op when empty.
gpg_sign=(gpg --batch --yes --pinentry-mode loopback --local-user "$GPG_KEY_ID")
if [ -n "${GPG_PASSPHRASE:-}" ]; then
    gpg_sign+=(--passphrase "$GPG_PASSPHRASE")
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stage="$work/pkg"

# --- Lay out the .deb staging tree -----------------------------------------
install -d "$stage/DEBIAN" \
    "$stage/usr/lib/knitcalc" \
    "$stage/usr/bin" \
    "$stage/usr/share/applications" \
    "$stage/usr/share/icons/hicolor/256x256/apps"

cp -r "$BUNDLE_DIR"/. "$stage/usr/lib/knitcalc/"
# /proc/self/exe resolves this symlink to the real path under /usr, which the
# app uses both to find its bundled data/ and to detect the dpkg channel.
ln -s ../lib/knitcalc/knitcalc "$stage/usr/bin/knitcalc"
cp "$here/knitcalc.desktop" "$stage/usr/share/applications/knitcalc.desktop"
cp "$repo_root/snap/gui/knitcalc.png" \
    "$stage/usr/share/icons/hicolor/256x256/apps/knitcalc.png"

sed "s|{{VERSION}}|$VERSION|" "$here/control" > "$stage/DEBIAN/control"

deb="$work/knitcalc_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$stage" "$deb"

# --- Assemble the apt repository -------------------------------------------
apt_root="$OUT_DIR/apt"
dist="$apt_root/dists/stable"
comp="$dist/main/binary-amd64"
install -d "$apt_root/pool/main" "$comp"
cp "$deb" "$apt_root/pool/main/"

# Filename entries come out relative to the apt root (pool/main/…), matching the
# URL layout the deb sources.list line points at.
( cd "$apt_root" && dpkg-scanpackages --multiversion pool /dev/null \
    > dists/stable/main/binary-amd64/Packages )
gzip -9 -kf "$comp/Packages"

apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=KnitCalc" \
    -o "APT::FTPArchive::Release::Label=KnitCalc" \
    -o "APT::FTPArchive::Release::Suite=stable" \
    -o "APT::FTPArchive::Release::Codename=stable" \
    -o "APT::FTPArchive::Release::Components=main" \
    -o "APT::FTPArchive::Release::Architectures=amd64" \
    release "$dist" > "$dist/Release"

# Detached (Release.gpg) and inline (InRelease) signatures: apt accepts either.
"${gpg_sign[@]}" -abs -o "$dist/Release.gpg" "$dist/Release"
"${gpg_sign[@]}" --clearsign -o "$dist/InRelease" "$dist/Release"

# Public key for users to drop into /usr/share/keyrings (signed-by=).
gpg --export "$GPG_KEY_ID" > "$apt_root/knitcalc.gpg"
