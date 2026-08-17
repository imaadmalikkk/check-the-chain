#!/usr/bin/env bash
# Runs the UI tests, including the appearance pass.
#
# XCTest has no API for setting the interface style or the Dynamic Type size,
# and adding a launch-argument override would put a test-only branch in shipping
# code. Instead the simulator is configured from out here, which has the side
# benefit of exercising the real trait-propagation path rather than a shortcut.
#
# The appearance tests assert which appearance actually resolved (via the
# `appearance-dark` / `appearance-light` identifier on the tab view), so a
# misconfigured simulator fails loudly instead of passing in the wrong mode.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17 Pro}"
# Widest iPad with an iOS 26.2 runtime on this machine — the worst case
# for line length, which is what readableWidth() exists to bound.
IPAD="${IPAD:-iPad Air 13-inch (M3)}"
OS="${OS:-26.2}"
DERIVED="${DERIVED:-DerivedData}"

run_suite() {
  local device="$1" appearance="$2" text_size="$3" only="$4"
  echo
  echo "── $device  appearance=$appearance  text=$text_size  ($only)"
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b >/dev/null
  xcrun simctl ui "$device" appearance "$appearance"
  xcrun simctl ui "$device" content_size "$text_size"
  xcodebuild test \
    -project CheckTheChain.xcodeproj \
    -scheme CheckTheChain \
    -destination "platform=iOS Simulator,OS=$OS,name=$device" \
    -derivedDataPath "$DERIVED" \
    -only-testing:"$only" \
    2>&1 | grep -E "Test Case.*(passed|failed)|XCTAssert.* failed|error:|\*\* TEST"
}

XXXL=accessibility-extra-extra-extra-large

run_suite "$DEVICE" light medium CheckTheChainUITests/WalkthroughTests
run_suite "$DEVICE" dark  medium CheckTheChainUITests/AppearanceTests/testDarkMode
run_suite "$DEVICE" light "$XXXL" CheckTheChainUITests/AppearanceTests/testLargestDynamicType
run_suite "$DEVICE" light medium CheckTheChainUITests/AppearanceTests/testLongestAttribution

# Persistence has to be checked on a clean install, or a store left behind by a
# previous run makes the test pass without proving anything.
xcrun simctl uninstall "$DEVICE" com.checkthechain.app 2>/dev/null || true
run_suite "$DEVICE" light medium CheckTheChainUITests/LibraryUITests

# iPad matters here because the app ships for it (TARGETED_DEVICE_FAMILY 1,2)
# and an unconstrained layout sets hadith at ~150 characters per line on a 13"
# screen. `readableWidth()` caps that; this is what keeps it capped.
run_suite "$IPAD" light medium CheckTheChainUITests/WalkthroughTests

xcrun simctl ui "$DEVICE" appearance light
xcrun simctl ui "$DEVICE" content_size medium
echo
echo "Done."
