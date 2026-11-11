#!/bin/zsh
# Build Training β and launch it on a simulator against Firebase's local emulators (throwaway accounts, nothing real).
#   ios-native/dev/run-emu.sh <UDID>     (start the emulators first: see HANDOFF.md → Testing sync)
DD="${TMPDIR:-/tmp}/training-native-dd"
cd "${0:A:h}/.."
./dev/run-sim.sh || exit 1
DEV="${1:-booted}"
xcrun simctl terminate "$DEV" io.github.lukaslundmark1.training.native 2>/dev/null
xcrun simctl install "$DEV" "$DD/Build/Products/Debug-iphonesimulator/Training.app" && xcrun simctl launch "$DEV" io.github.lukaslundmark1.training.native -emulator 127.0.0.1
