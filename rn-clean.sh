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

confirm_or_exit() {
  $CONFIRM && return 0
  read -r -p "This will DELETE caches/builds (safe). Continue? [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { warn "Canceled."; exit 0; }
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
    --pm) PM="${2:-}"; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [options]
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
  -h, --help            Show this help
EOF
      exit 0
      ;;
    *) warn "Unknown option: $1";;
  esac
  shift
done

# ========== Start ==========
: > "$LOG_FILE"
echo "React Native Clean Script Log - $(date)" >> "$LOG_FILE"

ensure_project_root
detect_pm

echo -e "🧹 ${BOLD}Starting React Native project cleanup${RST}"
echo "  PM: $PM"
echo "  Log: $LOG_FILE"
confirm_or_exit
echo

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