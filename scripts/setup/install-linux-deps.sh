#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script supports Debian/Ubuntu (apt-get) only." >&2
  exit 1
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required when not running as root." >&2
  exit 1
fi

SUDO=""
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  SUDO="sudo"
fi

PKGS=(
  libwebkit2gtk-4.1-dev
  libayatana-appindicator3-dev
  librsvg2-dev
  libxdo-dev
  libssl-dev
  build-essential
  patchelf
)

echo "Updating apt package index..."
${SUDO} apt-get update

echo "Installing system dependencies for Koharu build..."
${SUDO} apt-get install --no-install-recommends -y "${PKGS[@]}"

echo "Installed packages: ${PKGS[*]}"
