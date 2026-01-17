#!/usr/bin/env bash
# rn-clean.sh — Robust React Native cleanup + reinstall
# Usage:
#   ./rn-clean.sh [--yes] [--dry-run] [--no-ios] [--no-android] [--no-install] [--no-pods]
#                 [--pm npm|yarn|pnpm|bun] [--legacy-peer-deps] [--npm-ci]
# Env:
#   LOG_FILE=/tmp/rn-clean.log (override to change)
# Notes:
#   - Deletes node_modules, Pods, Gradle caches/builds, DerivedData (macOS), etc.
#   - Reinstalls deps (npm/yarn/pnpm/bun) and runs `pod install` unless skipped.
#   - Writes full logs to $LOG_FILE

set -Eeuo pipefail

# ========== Version ==========
VERSION="1.0.1"

# ========== Config ==========
LOG_FILE="${LOG_FILE:-/tmp/rn-clean.log}"
FAILED_COMMANDS=0
CONFIRM=false
DRY_RUN=false
DO_IOS=true
DO_ANDROID=true
DO_INSTALL=true
DO_PODS=true
RUN_RN_CLEAN_PROJECT=true
LEGACY_PEER_DEPS=false
NPM_CI=false
PM=""   # auto-detect unless --pm provided

# ========== Colors ==========
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD="\033[1m"; DIM="\033[2m"; RED="\033[31m"; YEL="\033[33m"; GRN="\033[32m"; BLU="\033[34m"; RST="\033[0m"
else
  BOLD=""; DIM=""; RED=""; YEL=""; GRN=""; BLU=""; RST=""
fi

# ========== Utils ==========
log()   { echo -e "${BLU}ℹ${RST}  $*"; }
ok()    { echo -e "${GRN}✅${RST} $*"; }
warn()  { echo -e "${YEL}⚠${RST}  $*"; }
err()   { echo -e "${RED}❌${RST} $*"; }

append_log() { printf "%s\n" "$*" >>"$LOG_FILE"; }

# ========== Update Check ==========
REPO_USER="ThanaphatNorth"
REPO_NAME="rn-clean"
RAW_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/main/rn-clean.sh"
UPDATE_CHECK_FILE="${HOME}/.rn-clean-last-update-check"
UPDATE_CHECK_INTERVAL=86400  # 24 hours in seconds

# Compare versions (returns 0 if $1 > $2)
version_gt() {
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

check_for_updates() {
  # Skip if NO_UPDATE_CHECK is set
  [[ -n "${NO_UPDATE_CHECK:-}" ]] && return 0

  # Check if we should skip (checked recently)
  if [[ -f "$UPDATE_CHECK_FILE" ]]; then
    local last_check
    last_check=$(cat "$UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
    local now
    now=$(date +%s)
    if ((now - last_check < UPDATE_CHECK_INTERVAL)); then
      return 0
    fi
  fi

  # Update the check timestamp
  date +%s > "$UPDATE_CHECK_FILE" 2>/dev/null || true

  # Try to fetch latest version (with timeout, in background-ish manner)
  local remote_content
  if command -v curl >/dev/null 2>&1; then
    remote_content=$(curl -fsSL --connect-timeout 2 --max-time 5 "$RAW_URL" 2>/dev/null) || return 0
  elif command -v wget >/dev/null 2>&1; then
    remote_content=$(wget -q --timeout=5 -O - "$RAW_URL" 2>/dev/null) || return 0
  else
    return 0
  fi

  # Extract remote version
  local remote_version
  remote_version=$(echo "$remote_content" | grep -oE 'VERSION="[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | sed 's/VERSION="//;s/"//') || return 0

  if [[ -z "$remote_version" ]]; then
    return 0
  fi

  # Compare versions
  if version_gt "$remote_version" "$VERSION"; then
    echo
    echo -e "${YEL}╭────────────────────────────────────────────────────────╮${RST}"
    echo -e "${YEL}│${RST}  ${BOLD}Update available!${RST} ${DIM}${VERSION}${RST} → ${GRN}${remote_version}${RST}                      ${YEL}│${RST}"
    echo -e "${YEL}│${RST}  Run: ${BLU}curl -fsSL https://raw.githubusercontent.com/${RST}    ${YEL}│${RST}"
    echo -e "${YEL}│${RST}       ${BLU}${REPO_USER}/${REPO_NAME}/main/install.sh | bash${RST}  ${YEL}│${RST}"
    echo -e "${YEL}╰────────────────────────────────────────────────────────╯${RST}"
    echo
  fi
}

check_permission_denied() {
  tail -n 50 "$LOG_FILE" | grep -qiE "permission denied|operation not permitted"
}

# safe runner with auto chown retry
run() {
  local desc="$1"; shift
  echo -e "${BOLD}🔧 $desc${RST}"
  if $DRY_RUN; then
    echo "DRY-RUN: $*" | tee -a "$LOG_FILE"
    ok "$desc - SKIPPED (dry-run)"
    return 0
  fi
  if "$@" >>"$LOG_FILE" 2>&1; then
    ok "$desc - SUCCESS"
    return 0
  fi
  if check_permission_denied; then
    warn "Permission denied — attempting: sudo chown -R $(whoami) ."
    if sudo chown -R "$(whoami)" . >>"$LOG_FILE" 2>&1 && "$@" >>"$LOG_FILE" 2>&1; then
      ok "$desc - SUCCESS (after ownership fix)"
      return 0
    fi
  fi
  err "$desc - FAILED (continuing...)"
  tail -n 20 "$LOG_FILE" | sed 's/^/  /'
  FAILED_COMMANDS=$((FAILED_COMMANDS+1))
  return 1
}


is_macos() { [[ "${OSTYPE:-}" == darwin* ]]; }

ensure_project_root() {
  if [[ ! -f package.json ]]; then
    err "package.json not found. Run from your React Native project root."
    exit 1
  fi
}

detect_pm() {
  [[ -n "$PM" ]] && return 0
  if command -v pnpm >/dev/null 2>&1 && [[ -f pnpm-lock.yaml ]]; then PM="pnpm"
  elif command -v yarn >/dev/null 2>&1 && [[ -f yarn.lock ]]; then PM="yarn"
  elif command -v bun  >/dev/null 2>&1 && [[ -f bun.lockb ]]; then PM="bun"
  else PM="npm"; fi
}

pm_install() {
  case "$PM" in
    npm)
      if $NPM_CI && [[ -f package-lock.json ]]; then
        $LEGACY_PEER_DEPS && run "npm ci (legacy-peer-deps ignored by ci)" npm ci || run "npm ci" npm ci
      else
        if $LEGACY_PEER_DEPS; then run "npm install --legacy-peer-deps" npm install --legacy-peer-deps
        else run "npm install" npm install; fi
      fi
      ;;
    yarn)  run "yarn install" yarn install ;;
    pnpm)  run "pnpm install" pnpm install ;;
    bun)   run "bun install" bun install ;;
    *) err "Unknown package manager: $PM"; exit 1 ;;
  esac
}

pm_cache_clean() {
  case "$PM" in
    npm)  run "Cleaning npm cache" npm cache clean --force ;;
    yarn) run "Cleaning yarn cache" yarn cache clean ;;
    pnpm) run "Pruning pnpm store" pnpm store prune ;;
    bun)  log "Bun has no cache clean cmd; skipping";;
  esac
}

gradle_cmd() {
  ( cd android && ./gradlew "$@" )
}

show_task_list() {
  echo -e "${BOLD}📋 Tasks to be performed:${RST}"
  echo

  # React Native Clean Project
  if $RUN_RN_CLEAN_PROJECT && command -v npx >/dev/null 2>&1; then
    echo -e "  ${BLU}•${RST} Run react-native-clean-project"
  fi

  # JavaScript cleanup
  echo -e "  ${BLU}•${RST} Remove node_modules directory"
  [[ -f package-lock.json ]] && echo -e "  ${BLU}•${RST} Remove package-lock.json"
  [[ -f yarn.lock ]] && echo -e "  ${BLU}•${RST} Remove yarn.lock"
  [[ -f pnpm-lock.yaml ]] && echo -e "  ${BLU}•${RST} Remove pnpm-lock.yaml"
  [[ -f bun.lockb ]] && echo -e "  ${BLU}•${RST} Remove bun.lockb"

  # iOS cleanup
  if $DO_IOS && [[ -d ios ]]; then
    echo -e "  ${BLU}•${RST} Clean iOS Pods and Podfile.lock"
    echo -e "  ${BLU}•${RST} Clean iOS build directory"
    if is_macos; then
      echo -e "  ${BLU}•${RST} Clean Xcode DerivedData"
    fi
  fi

  # Android cleanup
  if $DO_ANDROID && [[ -d android ]]; then
    echo -e "  ${BLU}•${RST} Clean Android .gradle (project)"
    echo -e "  ${BLU}•${RST} Clean Android build directories"
    echo -e "  ${BLU}•${RST} Clean local .gradle"
    echo -e "  ${BLU}•${RST} Clean Android CMake (.cxx)"
    echo -e "  ${BLU}•${RST} Clean global Gradle caches"
    echo -e "  ${BLU}•${RST} Clean Gradle daemon"
    echo -e "  ${BLU}•${RST} Clean Gradle native"
    echo -e "  ${BLU}•${RST} Clean Gradle kotlin"
    if [[ -x android/gradlew ]]; then
      echo -e "  ${BLU}•${RST} Stop Gradle daemon"
    fi
  fi

  # Watchman
  if command -v watchman >/dev/null 2>&1; then
    echo -e "  ${BLU}•${RST} Clear Watchman watches"
  fi

  # Package manager cache
  case "$PM" in
    npm)  echo -e "  ${BLU}•${RST} Clean npm cache" ;;
    yarn) echo -e "  ${BLU}•${RST} Clean yarn cache" ;;
    pnpm) echo -e "  ${BLU}•${RST} Prune pnpm store" ;;
    bun)  ;; # No cache clean for bun
  esac

  # Reinstall dependencies
  if $DO_INSTALL; then
    case "$PM" in
      npm)
        if $NPM_CI && [[ -f package-lock.json ]]; then
          echo -e "  ${BLU}•${RST} Install dependencies with npm ci"
        else
          if $LEGACY_PEER_DEPS; then
            echo -e "  ${BLU}•${RST} Install dependencies with npm (legacy-peer-deps)"
          else
            echo -e "  ${BLU}•${RST} Install dependencies with npm"
          fi
        fi
        ;;
      yarn) echo -e "  ${BLU}•${RST} Install dependencies with yarn" ;;
      pnpm) echo -e "  ${BLU}•${RST} Install dependencies with pnpm" ;;
      bun)  echo -e "  ${BLU}•${RST} Install dependencies with bun" ;;
    esac
    if command -v npx >/dev/null 2>&1; then
      echo -e "  ${BLU}•${RST} Link assets with react-native-asset"
    fi
  fi

  # CocoaPods
  if $DO_IOS && $DO_PODS && [[ -d ios ]] && is_macos && command -v pod >/dev/null 2>&1; then
    echo -e "  ${BLU}•${RST} Run pod install"
  fi

  # Gradle clean
  if $DO_ANDROID && [[ -d android ]] && [[ -x android/gradlew ]]; then
    echo -e "  ${BLU}•${RST} Run Gradle clean"
  fi

  echo
}

# ========== Args ==========
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) CONFIRM=true ;;
    --dry-run) DRY_RUN=true ;;
    --no-ios) DO_IOS=false ;;
    --no-android) DO_ANDROID=false ;;
    --no-install) DO_INSTALL=false ;;
    --no-pods) DO_PODS=false ;;
    --no-clean-project) RUN_RN_CLEAN_PROJECT=false ;;
    --legacy-peer-deps) LEGACY_PEER_DEPS=true ;;
    --npm-ci) NPM_CI=true ;;
    --pm)
      PM="${2:-}"
      if [[ ! "$PM" =~ ^(npm|yarn|pnpm|bun)$ ]]; then
        err "Invalid package manager: $PM"
        err "Valid options: npm, yarn, pnpm, bun"
        exit 1
      fi
      shift
      ;;
    -v|--version)
      echo "rn-clean version $VERSION"
      exit 0
      ;;
    -h|--help)
      cat <<EOF
Usage: $0 [options]

React Native cleanup script that shows all tasks before execution.

Options:
  --yes|-y              Skip confirmation
  --dry-run             Show actions without executing
  --no-ios              Skip iOS cleanup
  --no-android          Skip Android cleanup
  --no-install          Skip reinstalling JS deps
  --no-pods             Skip CocoaPods install
  --no-clean-project    Skip 'react-native-clean-project'
  --pm <npm|yarn|pnpm|bun>  Force package manager
  --legacy-peer-deps    Use npm --legacy-peer-deps when installing
  --npm-ci              Use npm ci when possible
  -v, --version         Show version
  -h, --help            Show this help

The script displays all tasks that will be performed before execution,
giving you a clear overview of what will be cleaned and reinstalled.
EOF
      exit 0
      ;;
    *) warn "Unknown option: $1";;
  esac
  shift
done

# ========== Pre-flight Check ==========
preflight_check() {
  local missing=()

  # Check for package manager
  if [[ -z "$PM" ]]; then
    if ! command -v npm >/dev/null 2>&1; then
      missing+=("npm (or yarn/pnpm/bun)")
    fi
  else
    if ! command -v "$PM" >/dev/null 2>&1; then
      missing+=("$PM")
    fi
  fi

  # Check for iOS tools (if iOS cleanup enabled)
  if $DO_IOS && [[ -d ios ]] && is_macos; then
    if ! command -v pod >/dev/null 2>&1; then
      warn "CocoaPods not found - iOS pod install will be skipped"
    fi
  fi

  # Check for Android tools (if Android cleanup enabled)
  if $DO_ANDROID && [[ -d android ]]; then
    if [[ ! -x android/gradlew ]]; then
      warn "gradlew not found - Gradle commands will be skipped"
    fi
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

# ========== Start ==========
: > "$LOG_FILE"
echo "React Native Clean Script Log - $(date)" >> "$LOG_FILE"

# Check for updates (non-blocking, once per day)
check_for_updates

ensure_project_root
detect_pm
preflight_check

echo -e "🧹 ${BOLD}Starting React Native project cleanup${RST}"
echo "  PM: $PM"
echo "  Log: $LOG_FILE"
echo

# Show all tasks that will be performed
show_task_list

# Confirmation prompt (if not --yes and not --dry-run)
if ! $CONFIRM && ! $DRY_RUN; then
  echo -e "${YEL}⚠${RST}  This will delete build files and caches. Continue? [y/N]"
  read -r response
  case "$response" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
  echo
fi

# Optional: react-native-clean-project
if $RUN_RN_CLEAN_PROJECT && command -v npx >/dev/null 2>&1; then
  log "Running npx react-native-clean-project (auto-answers)..."
  if $DRY_RUN; then echo "DRY-RUN: npx react-native-clean-project" | tee -a "$LOG_FILE"
  else
    # Answer prompts: yes to most, avoid deleting iOS/Android projects themselves.
    printf "y\ny\ny\ny\nn\ny\ny\ny\nn\n" | npx react-native-clean-project >>"$LOG_FILE" 2>&1 || {
      warn "react-native-clean-project failed (continuing...)"
      tail -n 20 "$LOG_FILE" | sed 's/^/  /'
      FAILED_COMMANDS=$((FAILED_COMMANDS+1))
    }
    ok "npx react-native-clean-project"
  fi
else
  warn "Skipping react-native-clean-project (npx not found or disabled)."
fi

# Remove JS deps & lock (lock optional)
run "Removing node_modules" rm -rf node_modules
if [[ -f package-lock.json ]]; then run "Removing package-lock.json" rm -f package-lock.json; fi
if [[ -f yarn.lock ]]; then run "Removing yarn.lock" rm -f yarn.lock; fi
if [[ -f pnpm-lock.yaml ]]; then run "Removing pnpm-lock.yaml" rm -f pnpm-lock.yaml; fi
if [[ -f bun.lockb ]]; then run "Removing bun.lockb" rm -f bun.lockb; fi

# iOS cleanup
if $DO_IOS; then
  if [[ -d ios ]]; then
    run "Cleaning iOS Pods" rm -rf ios/Pods ios/Podfile.lock
    run "Cleaning iOS build" rm -rf ios/build
    if is_macos; then
      run "Cleaning Xcode DerivedData" rm -rf ~/Library/Developer/Xcode/DerivedData
    else
      log "Non-macOS detected; skipping DerivedData."
    fi
  else
    warn "iOS directory not found; skipping iOS."
  fi
fi

# Android cleanup
if $DO_ANDROID; then
  if [[ -d android ]]; then
    run "Cleaning Android .gradle (project)" rm -rf android/.gradle
    run "Cleaning Android build dirs" rm -rf android/build android/app/build
    run "Cleaning local .gradle" rm -rf .gradle
    run "Cleaning Android CMake (.cxx)" rm -rf android/.cxx android/app/.cxx
    # Global Gradle caches (can be large)
    run "Cleaning Gradle caches" rm -rf "${HOME}/.gradle/caches/"
    run "Cleaning Gradle daemon" rm -rf "${HOME}/.gradle/daemon/"
    run "Cleaning Gradle native" rm -rf "${HOME}/.gradle/native/"
    run "Cleaning Gradle kotlin" rm -rf "${HOME}/.gradle/kotlin/"
    # Stop daemon gracefully
    if [[ -x android/gradlew ]]; then
      run "Stopping Gradle daemon" bash -lc 'cd android && ./gradlew --stop'
    fi
  else
    warn "Android directory not found; skipping Android."
  fi
fi

# Watchman
if command -v watchman >/dev/null 2>&1; then
  run "Clearing Watchman watches" watchman watch-del-all
else
  warn "Watchman not found; skipping."
fi

# JS Cache clean (pm-specific)
pm_cache_clean

# Reinstall JS deps
if $DO_INSTALL; then
  log "Installing JS dependencies ($PM)..."
  pm_install

  # Link assets with react-native-asset
  if command -v npx >/dev/null 2>&1; then
    log "Running npx react-native-asset (auto-answers y)..."
    if $DRY_RUN; then
      echo "DRY-RUN: npx react-native-asset" | tee -a "$LOG_FILE"
    else
      echo "y" | npx react-native-asset >>"$LOG_FILE" 2>&1 || {
        warn "react-native-asset failed (continuing...)"
        tail -n 20 "$LOG_FILE" | sed 's/^/  /'
        FAILED_COMMANDS=$((FAILED_COMMANDS+1))
      }
      ok "Linking assets with react-native-asset"
    fi
  else
    warn "npx not found; skipping react-native-asset."
  fi
else
  warn "Skipping JS install (--no-install)."
fi

# CocoaPods install
if $DO_IOS && $DO_PODS && [[ -d ios ]] && is_macos; then
  if command -v pod >/dev/null 2>&1; then
    (
      cd ios
      run "pod install" pod install || {
        warn "pod install failed; retry with --repo-update"
        run "pod install --repo-update" pod install --repo-update || true
      }
    )
  else
    warn "CocoaPods not found; skipped."
  fi
elif $DO_IOS && ! is_macos; then
  warn "CocoaPods install skipped on non-macOS."
fi

# Gradle clean
if $DO_ANDROID && [[ -d android ]] && [[ -x android/gradlew ]]; then
  run "Gradle clean (no-daemon)" bash -lc 'cd android && ./gradlew clean --no-daemon'
fi

echo
if (( FAILED_COMMANDS == 0 )); then
  echo -e "🎉 ${BOLD}Cleanup completed successfully!${RST}"
else
  echo -e "⚠  Cleanup completed with ${FAILED_COMMANDS} failed command(s). See log."
fi
echo "📋 Log: $LOG_FILE"
