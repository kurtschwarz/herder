#!/usr/bin/env bash
# Enforces the import rules from docs/ARCHITECTURE.md that target dependencies
# can't. Rules 1, 2, 3 and 5 are already enforced by Package.swift; these are
# the ones only a grep can see.
set -euo pipefail
cd "$(dirname "$0")/.."   # always run from apps/herder

SRC="Packages/HerderKit/Sources"
APP_DIR="${APP_DIR:-Herder}"
RUST_MODULE="${RUST_MODULE:-HerderSyntaxFFI}"
fail=0

check() {  # usage: check "description" <rg args...>
  local desc="$1"; shift
  local hits
  hits=$(rg -l "$@" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    echo "✗ $desc"
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
}

check "Core imports UI, persistence, or Rust" \
  -e "^import (SwiftUI|AppKit|SwiftData|$RUST_MODULE)" --type swift "$SRC/Core"

# AppFeature lives under Sources/Features until the second half of Phase 2, and
# it is the composition root rather than a feature, so it is excluded here.
check "Feature imports Services or the Rust module" \
  -e "^import (Services|$RUST_MODULE)" --type swift \
  --glob '!**/AppFeature/**' "$SRC/Features"

# Passes today, and the survey found nothing to fix. Keep it that way.
check "Singleton in HerderKit" \
  -e 'static (let|var) shared' --type swift "$SRC"

# Enable in Phase 6, once the Syntax target is gone and the app no longer links
# Services directly:
# check "Rust module imported outside Services" \
#   -e "^import $RUST_MODULE\$" --type swift --glob '!**/Services/**' "$SRC" "$APP_DIR"

check "SwiftData imported outside Services/Persistence" \
  -e '^import SwiftData' --type swift --glob '!**/Services/Persistence/**' "$SRC" "$APP_DIR"

if [[ $fail -eq 0 ]]; then echo "✓ boundaries OK"; fi
exit $fail
