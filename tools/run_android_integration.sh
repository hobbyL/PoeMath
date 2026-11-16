#!/usr/bin/env bash
# Linux CI entry: collect diagnostics before android-emulator-runner stops ADB.
set -euo pipefail

poemath_device="${ANDROID_SERIAL:-emulator-5554}"
poemath_logs="build/test-results/android-integration"
poemath_apk="build/app/outputs/flutter-apk/app-debug.apk"
poemath_package="com.poemath.app.integration"
poemath_forward_port=""
poemath_app_started=false
mkdir -p "$poemath_logs"

run_phase() {
  local poemath_phase=$1 poemath_timeout=$2 poemath_status=0
  shift 2
  echo "Android integration: ${poemath_phase} (limit ${poemath_timeout})"
  timeout --kill-after=15s "$poemath_timeout" "$@" \
    2>&1 | tee "$poemath_logs/${poemath_phase}.log" || poemath_status=$?
  if [ "$poemath_status" -ne 0 ]; then
    echo "::error::Android integration ${poemath_phase} failed (exit ${poemath_status}); see ${poemath_phase}.log."
  fi
  return "$poemath_status"
}

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
  if [ "$poemath_app_started" = true ]; then
    timeout --kill-after=5s 10s adb -s "$poemath_device" shell am force-stop "$poemath_package" \
      > "$poemath_logs/stop.log" 2>&1
  fi
  if [ -n "$poemath_forward_port" ]; then
    timeout --kill-after=5s 10s adb -s "$poemath_device" forward --remove "tcp:$poemath_forward_port" \
      > "$poemath_logs/forward-cleanup.log" 2>&1
  fi
  exit "$poemath_result"
}
trap collect_diagnostics EXIT

if [ ! -s "$poemath_apk" ]; then
  echo "::error::Build the integration APK before starting the emulator: ${poemath_apk}"
  exit 1
fi
run_phase adb-version 10s adb version

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

# The API 24 runner hung in adb's streamed install for over eight minutes while
# shell/Package Manager remained responsive. Push the APK before installing it.
# Flutter 3.47.8's test/startApp always installs again, so attach a driver below.
run_phase install 180s adb -s "$poemath_device" install --no-streaming -t -r "$poemath_apk"
if ! grep -q '^Success[[:space:]]*$' "$poemath_logs/install.log"; then
  echo '::error::ADB did not confirm installation; see install.log.'
  exit 1
fi
run_phase stop 15s adb -s "$poemath_device" shell am force-stop "$poemath_package"
run_phase clear-logcat 15s adb -s "$poemath_device" logcat -c
poemath_app_started=true
# Do not wait for the first frame with am start -W: start-paused deliberately
# holds Dart until the driver connects. The VM service below is our ready signal.
run_phase launch 30s adb -s "$poemath_device" shell am start \
  -n "$poemath_package/com.poemath.app.MainActivity" \
  -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
  --ez enable-checked-mode true --ez verify-entry-points true --ez start-paused true
if grep -Eiq 'Error:|Error type|Security[[:space:]]?exception' "$poemath_logs/launch.log"; then
  echo '::error::Android could not launch the integration app; see launch.log.'
  exit 1
fi

# Discover the authenticated VM service URI from this fresh launch. Keep its
# authentication token and forward only the port, without disabling VM auth.
poemath_vm_uri=""
poemath_deadline=$((SECONDS + 60))
while [ "$SECONDS" -lt "$poemath_deadline" ]; do
  timeout --kill-after=5s 10s adb -s "$poemath_device" logcat -d -s flutter:I '*:S' \
    > "$poemath_logs/startup-logcat.txt" 2>&1
  poemath_vm_uri=$(sed -nE \
    's@.*The Dart VM service is listening on (http://127\.0\.0\.1:[0-9]+/[^[:space:]]*).*@\1@p' \
    "$poemath_logs/startup-logcat.txt" | sed -n '1p')
  if [ -n "$poemath_vm_uri" ]; then
    break
  fi
  sleep 1
done
if [ -z "$poemath_vm_uri" ]; then
  echo '::error::No Dart VM service appeared within 60 seconds; see startup-logcat.txt.'
  exit 1
fi
poemath_device_port=${poemath_vm_uri#http://127.0.0.1:}
poemath_device_port=${poemath_device_port%%/*}
poemath_forward_port=$(timeout --kill-after=5s 10s adb -s "$poemath_device" forward tcp:0 "tcp:$poemath_device_port")
if [[ ! "$poemath_forward_port" =~ ^[0-9]+$ ]]; then
  echo '::error::ADB did not return a forwarded VM service port.'
  exit 1
fi
poemath_host_uri="http://127.0.0.1:${poemath_forward_port}/${poemath_vm_uri#http://127.0.0.1:*/}"
run_phase flutter 7m flutter drive \
  --driver=test_driver/app_journeys_driver.dart \
  --target=integration_test/app_journeys_test.dart \
  --use-existing-app="$poemath_host_uri" \
  -d "$poemath_device" --no-pub --keep-app-running --verbose
