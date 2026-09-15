#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
cat Sources/CodexAccounts/ProviderDashboard.swift Sources/CodexAccounts/ProviderCatalog.swift Sources/CodexAccounts/ProviderBrandIcon.swift Tests/ProviderModelChecks.swift > "$CHECK_DIR/Checks.swift"
swiftc -parse-as-library "$CHECK_DIR/Checks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$@"
