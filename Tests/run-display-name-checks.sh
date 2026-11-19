#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
name_check_dir=$(mktemp -d /tmp/homey-display-name-checks.XXXXXX)
trap 'rm -rf "$name_check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path "$name_check_dir/cache" \
    Homey/Features/Authentication/Models/ProfileNameFormatter.swift \
    Homey/Features/Authentication/Models/PasswordRecovery.swift \
    Homey/Features/Authentication/Models/EmailVerification.swift \
    Tests/DisplayNameChecks.swift -o "$name_check_dir/checks"
"$name_check_dir/checks"
python3 Tests/check-display-name-contracts.py
