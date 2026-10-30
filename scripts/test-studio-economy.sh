#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pass a destination string to use a particular installed simulator.
destination="${1:-platform=iOS Simulator,name=iPhone 17,OS=latest}"
xcodebuild test \
  -project 75.xcodeproj -scheme 75 \
  -destination "$destination" \
  -only-testing:75Tests/IdleEngineTests \
  -only-testing:75Tests/BuddyEngineTests \
  -only-testing:75Tests/BuddyEconomyTransactionTests \
  -only-testing:75Tests/StudioJourneySimulationTests \
  CODE_SIGNING_ALLOWED=NO
