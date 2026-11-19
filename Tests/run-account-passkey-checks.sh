#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
passkey_check_dir=$(mktemp -d /tmp/homey-passkey-checks.XXXXXX)
trap 'rm -rf "$passkey_check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path "$passkey_check_dir/cache" \
    Homey/Features/Authentication/Models/AccountPasskey.swift \
    Tests/AccountPasskeyChecks.swift -o "$passkey_check_dir/checks"
"$passkey_check_dir/checks"
python3 Tests/check-account-passkey-contracts.py
