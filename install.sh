#!/usr/bin/env bash
# install.sh - Install rn-clean globally
# This script downloads the latest rn-clean.sh from GitHub and installs it as `rn-clean`
# into /usr/local/bin (or ~/.local/bin if /usr/local/bin is not writable).

set -euo pipefail

REPO_USER="ThanaphatNorth"
REPO_NAME="rn-clean"
RAW_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/main/rn-clean.sh"
TARGET_NAME="rn-clean"

# Colors
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD="\033[1m"; RED="\033[31m"; YEL="\033[33m"; GRN="\033[32m"; BLU="\033[34m"; RST="\033[0m"
else
  BOLD=""; RED=""; YEL=""; GRN=""; BLU=""; RST=""
fi

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Get version from script content
get_version_from_content() {
  grep -oE 'VERSION="[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | sed 's/VERSION="//;s/"//'
}

# Compare versions (returns 0 if $1 > $2)
version_compare() {
  [[ "$1" == "$2" ]] && return 1
  local i
  local IFS=.
  read -ra ver1 <<< "$1"
  read -ra ver2 <<< "$2"
  for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
    local v1="${ver1[i]:-0}"
    local v2="${ver2[i]:-0}"
    if ((10#$v1 > 10#$v2)); then
      return 0
    fi
    if ((10#$v1 < 10#$v2)); then
      return 1
    fi
  done
  return 1
}

choose_target_dir() {
  # Prefer /usr/local/bin when writable, else ~/.local/bin (create if needed)
  if [[ -w "/usr/local/bin" ]]; then
    echo "/usr/local/bin"
  elif [[ -d "/usr/local/bin" ]]; then
    # /usr/local/bin exists but is not writable, make it writable with sudo
    echo "🔒 /usr/local/bin exists but is not writable by your user." >&2
    echo "🔧 Making /usr/local/bin writable with sudo..." >&2
    if sudo chown "$(whoami)" "/usr/local/bin"; then
      echo "✅ /usr/local/bin is now writable by your user." >&2
      echo "/usr/local/bin"
    else
      echo "❌ Failed to make /usr/local/bin writable. Using ~/.local/bin instead." >&2
      echo "${HOME}/.local/bin"
    fi
  else
    # /usr/local/bin doesn't exist, create it with proper permissions
    echo "📁 /usr/local/bin doesn't exist. Creating it..." >&2
    if sudo mkdir -p "/usr/local/bin" && sudo chown "$(whoami)" "/usr/local/bin"; then
      echo "✅ Created /usr/local/bin with your user ownership." >&2
      echo "/usr/local/bin"
    else
      echo "❌ Failed to create /usr/local/bin. Using ~/.local/bin instead." >&2
      echo "${HOME}/.local/bin"
    fi
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

check_existing_installation() {
  # Check if rn-clean is already installed
  if has_cmd "$TARGET_NAME"; then
    local installed_path
    installed_path="$(command -v "$TARGET_NAME")"
    local installed_version
    installed_version="$(cat "$installed_path" | get_version_from_content)"

    if [[ -z "$installed_version" ]]; then
      installed_version="unknown"
    fi

    echo -e "${BLU}ℹ${RST}  rn-clean is already installed at: ${BOLD}${installed_path}${RST}"
    echo -e "${BLU}ℹ${RST}  Installed version: ${BOLD}${installed_version}${RST}"
    echo

    # Download to temp to check remote version
    local tmpfile
    tmpfile="$(mktemp)"
    echo -e "${BLU}ℹ${RST}  Checking for updates..."
    if download "$RAW_URL" "$tmpfile" 2>/dev/null; then
      local remote_version
      remote_version="$(cat "$tmpfile" | get_version_from_content)"

      if [[ -z "$remote_version" ]]; then
        remote_version="unknown"
      fi

      echo -e "${BLU}ℹ${RST}  Latest version: ${BOLD}${remote_version}${RST}"
      echo

      if [[ "$installed_version" == "$remote_version" ]]; then
        echo -e "${GRN}✅${RST} You already have the latest version!"
        rm -f "$tmpfile"
        exit 0
      fi

      # Check if update is available
      if [[ "$installed_version" != "unknown" && "$remote_version" != "unknown" ]]; then
        if version_compare "$remote_version" "$installed_version"; then
          echo -e "${YEL}⚠${RST}  A new version is available: ${BOLD}${remote_version}${RST}"
        fi
      fi

      echo -e "${YEL}?${RST}  Do you want to update rn-clean? [y/N]"
      read -r response
      case "$response" in
        [yY]|[yY][eE][sS])
          echo
          echo "$tmpfile"  # Return tmpfile path for installation
          return 0
          ;;
        *)
          echo "Update cancelled."
          rm -f "$tmpfile"
          exit 0
          ;;
      esac
    else
      echo -e "${RED}❌${RST} Failed to check for updates."
      rm -f "$tmpfile"
      exit 1
    fi
  fi

  # Not installed, return empty
  echo ""
  return 0
}

main() {
  local target_dir
  target_dir="$(choose_target_dir)"
  mkdir -p "$target_dir"

  local tmpfile
  local existing_tmpfile
  existing_tmpfile="$(check_existing_installation)"

  if [[ -n "$existing_tmpfile" && -f "$existing_tmpfile" ]]; then
    # Use the already downloaded file for update
    tmpfile="$existing_tmpfile"
    echo "⬆️  Updating rn-clean..."
  else
    # Fresh install
    tmpfile="$(mktemp)"
    echo "⬇️  Downloading rn-clean from ${RAW_URL} ..."
    download "$RAW_URL" "$tmpfile"
  fi

  chmod +x "$tmpfile"

  local target_path="${target_dir}/${TARGET_NAME}"

  if [[ -w "$target_dir" ]]; then
    mv "$tmpfile" "$target_path"
  else
    echo "🔧 Installing with sudo to ${target_dir}..." >&2
    sudo mv "$tmpfile" "$target_path"
  fi

  if [[ -w "$target_dir" ]]; then
    chmod +x "$target_path"
  else
    sudo chmod 755 "$target_path"
  fi

  if [[ -n "$existing_tmpfile" ]]; then
    echo -e "${GRN}✅${RST} Updated: ${target_path}"
  else
    echo -e "${GRN}✅${RST} Installed: ${target_path}"
  fi
  ensure_dir_on_path "$target_dir"
  echo
  echo "Run it anywhere:"
  echo "  ${TARGET_NAME} --help"
}

main "$@"
