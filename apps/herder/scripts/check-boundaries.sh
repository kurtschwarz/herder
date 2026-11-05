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

check "Feature imports Services or the Rust module" \
  -e "^import (Services|$RUST_MODULE)" --type swift "$SRC/Features"

# Passes today, and the survey found nothing to fix. Keep it that way.
check "Singleton in HerderKit" \
  -e 'static (let|var) shared' --type swift "$SRC"

# The FFI's types never leave the module that links it: `Services/Highlighting`
# turns an `HdrToken` into a `SyntaxToken` and nothing above it knows there is a
# C ABI under the colour. The import is what a grep can see; the types crossing
# is review's job.
check "Rust module imported outside Services" \
  -e "^import $RUST_MODULE\$" --type swift --glob '!**/Services/**' "$SRC" "$APP_DIR"

# Phase 7 removed SwiftData altogether, so this is no longer "only under
# Services/Persistence" — it is "not at all". State is JSON files behind
# `StateStore`; anything reaching for a @Model is reintroducing a dependency
# the app deliberately dropped.
check "SwiftData imported anywhere" \
  -e '^import SwiftData' --type swift "$SRC" "$APP_DIR"

if [[ $fail -eq 0 ]]; then echo "✓ boundaries OK"; fi
exit $fail
