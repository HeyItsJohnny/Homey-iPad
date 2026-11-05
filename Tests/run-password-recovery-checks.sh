#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
recovery_check_dir=$(mktemp -d /tmp/homey-recovery-checks.XXXXXX)
trap 'rm -rf "$recovery_check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path "$recovery_check_dir/cache" \
    Homey/Features/Authentication/Models/PasswordRecovery.swift \
    Homey/Features/Authentication/Services/PasswordRecoveryService.swift \
    Tests/PasswordRecoveryChecks.swift -o "$recovery_check_dir/checks"
"$recovery_check_dir/checks"
