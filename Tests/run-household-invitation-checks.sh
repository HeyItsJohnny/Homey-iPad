#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
invitation_check_dir=$(mktemp -d /tmp/homey-invitation-checks.XXXXXX)
trap 'rm -rf "$invitation_check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path "$invitation_check_dir/cache" \
    Homey/Features/HomeOnboarding/Models/HomeRoles.swift \
    Homey/Features/HomeOnboarding/Services/HouseholdInvitationFlow.swift \
    Tests/HouseholdInvitationChecks.swift -o "$invitation_check_dir/checks"
"$invitation_check_dir/checks"
python3 Tests/check-household-invitation-contracts.py
