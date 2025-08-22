#!/usr/bin/env bash
# install.sh - Install rn-clean globally
# This script downloads the latest rn-clean.sh from GitHub and installs it as `rn-clean`
# into /usr/local/bin (or ~/.local/bin if /usr/local/bin is not writable).

set -euo pipefail

REPO_USER="ThanaphatNorth"
REPO_NAME="rn-clean"
RAW_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/main/rn-clean.sh"
TARGET_NAME="rn-clean"

has_cmd() { command -v "$1" >/dev/null 2>&1; }

choose_target_dir() {
  # Prefer /usr/local/bin when writable, else ~/.local/bin (create if needed)
  if [[ -w "/usr/local/bin" ]]; then
    echo "/usr/local/bin"
  else
    echo "${HOME}/.local/bin"
  fi
}

ensure_dir_on_path() {
  local dir="$1"
  if ! echo ":$PATH:" | grep -q ":${dir}:"; then
    echo "⚠️  ${dir} is not in your PATH."
    echo "   Add this line to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo "   export PATH=\"${dir}:\$PATH\""
  fi
}

download() {
  local url="$1" dest="$2"
  if has_cmd curl; then
    curl -fsSL "$url" -o "$dest"
  elif has_cmd wget; then
    wget -q "$url" -O "$dest"
  else
    echo "Error: curl or wget is required." >&2
    exit 1
  fi
}

main() {
  local target_dir
  target_dir="$(choose_target_dir)"
  mkdir -p "$target_dir"

  local tmpfile
  tmpfile="$(mktemp)"
  echo "⬇️  Downloading rn-clean from ${RAW_URL} ..."
  download "$RAW_URL" "$tmpfile"

  chmod +x "$tmpfile"

  local target_path="${target_dir}/${TARGET_NAME}"

  if [[ -w "$target_dir" ]]; then
    mv "$tmpfile" "$target_path"
  else
    echo "🔒 '${target_dir}' requires elevated permissions. Using sudo to install..."
    sudo mv "$tmpfile" "$target_path"
  fi

  chmod +x "$target_path"

  echo "✅ Installed: ${target_path}"
  ensure_dir_on_path "$target_dir"
  echo
  echo "Run it anywhere:"
  echo "  ${TARGET_NAME} --help"
}

main "$@"
