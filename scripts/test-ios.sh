#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FinanceApp.xcodeproj"
SCHEME="${SCHEME:-FinanceApp}"
SIM_NAME="${SIM_NAME:-FinanceApp Test iPhone 16e}"
DESTINATION_TIMEOUT="${DESTINATION_TIMEOUT:-180}"

log() {
  printf '[test-ios] %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  scripts/test-ios.sh device
  scripts/test-ios.sh build
  scripts/test-ios.sh ui [FinanceAppUITests/FinanceAppUITests/testName]
  scripts/test-ios.sh full-ui

Environment:
  SIM_NAME              Simulator device name (default: FinanceApp Test iPhone 16e)
  SCHEME                Xcode scheme (default: FinanceApp)
  DESTINATION_TIMEOUT   xcodebuild destination timeout in seconds (default: 180)
  KEEP_BOOTED=1         Do not shutdown all simulators before booting target
EOF
}

find_sim_udid() {
  xcrun simctl list devices available | awk -v name="$SIM_NAME" '
    {
      line = $0
      gsub(/^[[:space:]]+/, "", line)
      if (index(line, name " (") == 1) {
        if (match(line, /\(([0-9A-Fa-f-]{36})\)/)) {
          print substr(line, RSTART + 1, RLENGTH - 2)
          exit
        }
      }
    }
  '
}

pick_latest_runtime_id() {
  xcrun simctl list runtimes available | awk -F ' - ' '
    /com\.apple\.CoreSimulator\.SimRuntime\.iOS-/ { runtime = $2 }
    END { print runtime }
  '
}

create_simulator() {
  local runtime_id
  local device_type_id

  runtime_id="$(pick_latest_runtime_id)"
  device_type_id="$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone 16e/ { print $2; exit }')"

  if [[ -z "$runtime_id" ]]; then
    log "Cannot find available iOS runtime"
    exit 1
  fi

  if [[ -z "$device_type_id" ]]; then
    log "Cannot find iPhone 16e device type"
    exit 1
  fi

  xcrun simctl create "$SIM_NAME" "$device_type_id" "$runtime_id"
}

ensure_simulator_ready() {
  local sim_udid="${1:-}"

  if [[ -z "$sim_udid" ]]; then
    sim_udid="$(find_sim_udid)"
  fi

  if [[ -z "$sim_udid" ]]; then
    log "Simulator '$SIM_NAME' not found. Creating..."
    sim_udid="$(create_simulator)"
    log "Created simulator: $sim_udid"
  fi

  if [[ "${KEEP_BOOTED:-0}" != "1" ]]; then
    xcrun simctl shutdown all >/dev/null 2>&1 || true
  fi

  xcrun simctl boot "$sim_udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$sim_udid" -b >/dev/null
  log "Using simulator: $SIM_NAME ($sim_udid)"
  printf '%s\n' "$sim_udid"
}

sim_state() {
  local sim_udid="$1"
  local line
  line="$(xcrun simctl list devices | grep "$sim_udid" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    printf 'Unknown\n'
    return
  fi
  printf '%s\n' "$line" | sed -E 's/.*\(([^()]*)\)[[:space:]]*$/\1/'
}

monitor_test_process() {
  local pid="$1"
  local sim_udid="$2"
  local state

  while kill -0 "$pid" >/dev/null 2>&1; do
    state="$(sim_state "$sim_udid")"
    if [[ "$state" == "Shutdown" || "$state" == "Shutting Down" ]]; then
      log "Simulator state became '$state' during test run. Stopping xcodebuild to avoid hang."
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 5
  done

  return 0
}

run_build_for_testing() {
  log "Running build-for-testing"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS Simulator" \
    build-for-testing
}

run_ui_test() {
  local test_id="${1:-}"
  local sim_udid
  sim_udid="$(ensure_simulator_ready)"

  local cmd=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -destination "platform=iOS Simulator,id=$sim_udid"
    -destination-timeout "$DESTINATION_TIMEOUT"
  )

  if [[ -n "$test_id" ]]; then
    cmd+=("-only-testing:$test_id")
  fi

  cmd+=(test-without-building)

  log "Running UI test${test_id:+: $test_id}"
  "${cmd[@]}" &
  local test_pid=$!

  if ! monitor_test_process "$test_pid" "$sim_udid"; then
    wait "$test_pid" 2>/dev/null || true
    return 124
  fi

  wait "$test_pid"
}

run_full_ui() {
  local sim_udid
  sim_udid="$(ensure_simulator_ready)"

  log "Running full UI test suite"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$sim_udid" \
    -destination-timeout "$DESTINATION_TIMEOUT" \
    test &
  local test_pid=$!

  if ! monitor_test_process "$test_pid" "$sim_udid"; then
    wait "$test_pid" 2>/dev/null || true
    return 124
  fi

  wait "$test_pid"
}

main() {
  local command="${1:-}"
  case "$command" in
    device)
      ensure_simulator_ready >/dev/null
      ;;
    build)
      run_build_for_testing
      ;;
    ui)
      shift || true
      run_ui_test "${1:-}"
      ;;
    full-ui)
      run_full_ui
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
