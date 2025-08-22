#!/usr/bin/env bash
# uninstall.sh - Remove global rn-clean installation

set -euo pipefail

TARGETS=(
  "/usr/local/bin/rn-clean"
  "${HOME}/.local/bin/rn-clean"
)

removed_any=false
for t in "${TARGETS[@]}"; do
  if [[ -e "$t" ]]; then
    if [[ -w "$(dirname "$t")" ]]; then
      rm -f "$t"
    else
      sudo rm -f "$t"
    fi
    echo "🗑️  Removed $t"
    removed_any=true
  fi
done

if ! $removed_any; then
  echo "rn-clean not found in common install locations."
else
  echo "✅ Uninstall complete."
fi
