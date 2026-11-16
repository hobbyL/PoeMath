#!/usr/bin/env bash
# Linux CI entry: collect diagnostics before android-emulator-runner stops ADB.
set -euo pipefail

poemath_device="${ANDROID_SERIAL:-emulator-5554}"
poemath_logs="build/test-results/android-integration"
mkdir -p "$poemath_logs"

collect_diagnostics() {
  local poemath_result=$?
  # A broken emulator must not hang diagnostics or hide the test's exit status.
  set +e
  { df -h; free -h; } > "$poemath_logs/host-resources.txt" 2>&1
  timeout --kill-after=5s 10s adb devices -l \
    > "$poemath_logs/devices.txt" 2>&1
  timeout --kill-after=5s 10s adb -s "$poemath_device" shell getprop \
    > "$poemath_logs/device-properties.txt" 2>&1
  timeout --kill-after=5s 10s adb -s "$poemath_device" shell df -h \
    > "$poemath_logs/device-disk.txt" 2>&1
  timeout --kill-after=5s 10s adb -s "$poemath_device" shell dumpsys meminfo \
    > "$poemath_logs/device-memory.txt" 2>&1
  timeout --kill-after=5s 15s adb -s "$poemath_device" logcat -d -t 2000 \
    > "$poemath_logs/logcat.txt" 2>&1
  exit "$poemath_result"
}
trap collect_diagnostics EXIT

# sys.boot_completed alone does not guarantee a responsive Package Manager.
if ! timeout --kill-after=5s 30s adb -s "$poemath_device" shell pm path android \
    > "$poemath_logs/package-manager.txt" 2>&1; then
  echo '::error::Android Package Manager did not respond before the test.'
  exit 1
fi
if ! grep -q '^package:' "$poemath_logs/package-manager.txt"; then
  echo '::error::Android Package Manager is not ready; see package-manager.txt.'
  exit 1
fi

# Flutter 3.47.8 does not bound adb install. Leave time for diagnostics/upload
# instead of letting a stuck install exhaust the entire job.
poemath_result=0
timeout --kill-after=30s 10m \
  flutter test integration_test/app_journeys_test.dart \
    -d "$poemath_device" \
    --dart-define=POEMATH_INTEGRATION_TEST=true \
    --no-pub --no-uninstall --verbose --reporter expanded \
  2>&1 | tee "$poemath_logs/flutter.log" || poemath_result=$?
if [ "$poemath_result" -eq 124 ]; then
  echo '::error::Android integration timed out after 10 minutes; inspect flutter.log and logcat.txt for the last build/install/test operation.'
elif [ "$poemath_result" -eq 137 ]; then
  echo '::error::Android integration was forcibly killed; inspect flutter.log, logcat.txt and resource diagnostics.'
fi
exit "$poemath_result"
