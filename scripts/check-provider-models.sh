#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
cat Sources/SwitcherCore/UsagePaceEstimate.swift Sources/CodexAccounts/ProviderDashboard.swift Sources/CodexAccounts/ProviderCatalog.swift Sources/CodexAccounts/ProviderBrandIcon.swift Sources/CodexAccounts/LocalConsumptionView.swift Tests/ProviderModelChecks.swift > "$CHECK_DIR/Checks.swift"
swiftc -sdk "${SDKROOT:-$(xcrun --show-sdk-path)}" -parse-as-library "$CHECK_DIR/Checks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks" "$@"
