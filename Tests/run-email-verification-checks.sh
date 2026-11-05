#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
verification_check_dir=$(mktemp -d /tmp/homey-verification-checks.XXXXXX)
trap 'rm -rf "$verification_check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path "$verification_check_dir/cache" \
    Homey/Features/Authentication/Models/PasswordRecovery.swift \
    Homey/Features/Authentication/Models/EmailVerification.swift \
    Homey/Features/Authentication/Services/EmailVerificationService.swift \
    Tests/EmailVerificationChecks.swift -o "$verification_check_dir/checks"
"$verification_check_dir/checks"
python3 Tests/check-email-verification-contracts.py
