#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
unlock_check_dir=$(mktemp -d /tmp/homey-device-unlock-checks.XXXXXX)
trap 'rm -rf "$unlock_check_dir"' EXIT
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path "$unlock_check_dir/cache" -emit-library -emit-module \
    -module-name LocalAuthentication Tests/Support/MockLocalAuthentication.swift \
    -emit-module-path "$unlock_check_dir/LocalAuthentication.swiftmodule" \
    -o "$unlock_check_dir/libLocalAuthentication.dylib"
xcrun swiftc -module-cache-path "$unlock_check_dir/cache" -I "$unlock_check_dir" -L "$unlock_check_dir" \
    -lLocalAuthentication -Xlinker -rpath -Xlinker "$unlock_check_dir" \
    Homey/Features/Authentication/Models/AuthenticationState.swift \
    Tests/Support/DeviceUnlockAuthenticationStub.swift \
    Homey/Core/Security/DeviceUnlockService.swift \
    Tests/DeviceUnlockChecks.swift -o "$unlock_check_dir/checks"
"$unlock_check_dir/checks"
python3 Tests/check-device-unlock-contracts.py
