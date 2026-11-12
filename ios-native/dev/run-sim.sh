#!/bin/zsh
# Build Training β for the Simulator and (optionally) install + launch it.
#   ios-native/dev/run-sim.sh            build only (prints errors/warnings)
#   ios-native/dev/run-sim.sh launch     build, install and launch on the booted simulator
#   ios-native/dev/run-sim.sh launch <UDID>   … on a specific simulator (e.g. a second one while Lukas uses the first)
#   CONF=Release ios-native/dev/run-sim.sh launch <UDID> [launch args…]   the optimised build (what ▶ in Xcode builds),
#        e.g. with -perfData 104 -perfLog 1 for performance tests (see Model/Perf.swift)
CONF="${CONF:-Debug}"
DD="${TMPDIR:-/tmp}/training-native-dd$([[ $CONF == Release ]] && echo r)"
cd "${0:A:h}/.."
xcodebuild -project Training.xcodeproj -scheme Training -configuration "$CONF" -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" build 2>&1 \
  | grep -E "error: |warning: |BUILD" | grep -v appintents | head -40
[[ ${pipestatus[1]} -ne 0 ]] && exit 1
if [[ "$1" == "launch" ]]; then
  DEV="${2:-booted}"
  xcrun simctl terminate "$DEV" io.github.lukaslundmark1.training.native 2>/dev/null
  xcrun simctl install "$DEV" "$DD/Build/Products/$CONF-iphonesimulator/Training.app" && xcrun simctl launch "$DEV" io.github.lukaslundmark1.training.native "${@:3}"
fi
