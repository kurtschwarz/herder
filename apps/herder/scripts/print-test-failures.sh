#!/usr/bin/env bash
# Prints every failed test in an .xcresult bundle with its failure messages.
# Swift Testing's issue messages (failed #expect, Issue.record, time limits)
# go only into the bundle; xcodebuild's log says just "Test case … failed".
# Usage: print-test-failures.sh PATH.xcresult
set -euo pipefail

bundle="${1:?usage: print-test-failures.sh PATH.xcresult}"

if [[ ! -d "$bundle" ]]; then
  echo "No result bundle at $bundle (the build may have failed before testing)."
  exit 0
fi

# Walks the test tree and prints each failed test case under its suite path,
# then the messages (they carry file:line) from its Failure Message children.
xcrun xcresulttool get test-results tests --path "$bundle" | jq -r '
  def failures($path):
    if .nodeType == "Test Case" and .result == "Failed" then
      "✗ \($path | join(" › "))",
      ([.. | objects | select(.nodeType == "Failure Message") | .name]
        | unique[] | "    \(.)")
    else
      (.children // [])[] | failures($path + [.name])
    end;
  [.testNodes[]? | failures([])] | if length == 0 then "No failed test cases found." else .[] end
'
