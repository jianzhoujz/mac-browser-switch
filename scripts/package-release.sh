#!/usr/bin/env bash
# Package and release script for mac-browser-switch
# Usage: ./scripts/package-release.sh <version>
#
# This script:
#   1. Builds a DMG package
#   2. Updates the Cask in the homebrew tap with the new version + sha256
#   3. Prints the gh release create command for the maintainer to run
#
# Run from the mac-browser-switch project root (or anywhere — paths are
# resolved relative to the script).

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TAP_ROOT="$(cd "${PROJECT_ROOT}/../homebrew-tap" 2>/dev/null && pwd || echo '')"
DIST_DIR="${PROJECT_ROOT}/dist"

if [[ -z "${TAP_ROOT}" ]]; then
  echo "Error: homebrew tap not found at ../homebrew-tap" >&2
  exit 1
fi

CASK_FILE="${TAP_ROOT}/Casks/mac-browser-switch.rb"
if [[ ! -f "${CASK_FILE}" ]]; then
  echo "Error: Cask not found at ${CASK_FILE}" >&2
  exit 1
fi

cd "${PROJECT_ROOT}"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

APP_VERSION="${VERSION}" APP_BUILD="${VERSION}" ./package-dmg.sh >/dev/null

DMG="${DIST_DIR}/BrowserSwitch-${VERSION}.dmg"
if [[ ! -f "${DMG}" ]]; then
  echo "Error: DMG was not produced at ${DMG}" >&2
  exit 1
fi
SHA="$(shasum -a 256 "${DMG}" | awk '{print $1}')"

export TAP_ROOT VERSION SHA CASK_FILE

ruby <<'RUBY'
path = ENV.fetch("CASK_FILE")
contents = File.read(path)
contents = contents.sub(/version "[^"]+"/, %(version "#{ENV.fetch("VERSION")}"))
contents = contents.sub(/sha256 "[0-9a-f]{64}"/, %(sha256 "#{ENV.fetch("SHA")}"))
File.write(path, contents)
RUBY

printf '%s  %s\n' "${SHA}" "${DMG}"
printf '\nUpdated %s\n' "${CASK_FILE}"

cat <<EOF

Upload with:
gh release create v${VERSION} \\
  "${DMG}" \\
  --repo jianzhoujz/mac-browser-switch \\
  --title v${VERSION}
EOF
