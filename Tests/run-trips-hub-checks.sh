#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
trip_check_dir=$(mktemp -d /tmp/homey-trips-checks.XXXXXX)
trap 'rm -rf "$trip_check_dir"' EXIT
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path "$trip_check_dir/cache" \
 Homey/Features/Trips/TripModels.swift Homey/Features/Trips/Trips2Models.swift \
 Homey/Features/Trips/TripIdeaPlanningAttempt.swift Homey/Features/Trips/TripsHubSort.swift \
 Homey/Features/Trips/TripsServiceError.swift Homey/Features/Trips/TripCalendarPreparation.swift \
 Tests/TripsHubChecks.swift -o "$trip_check_dir/checks"
"$trip_check_dir/checks"
python3 Tests/check-trips-hub-contracts.py

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -module-cache-path "$trip_check_dir/cache" \
 Homey/Features/Trips/TripCalendarPreparation.swift Homey/Features/Trips/TripIdeaPlanningAttempt.swift \
 Homey/Features/Trips/TripCalendarSubmission.swift Tests/TripCalendarSubmissionChecks.swift -o "$trip_check_dir/calendar-checks"
"$trip_check_dir/calendar-checks"
