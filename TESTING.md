# FinanceApp Testing

Run all iOS tests through one script so simulator/device selection stays stable.

## Canonical simulator

- Device name: `FinanceApp Test iPhone 16e`
- Script will:
  - reuse this simulator by name;
  - create it if missing;
  - boot it and wait until ready;
  - (by default) shutdown other simulators to avoid random window/device switching;
  - stop `xcodebuild` early if the simulator unexpectedly goes to `Shutdown/Shutting Down` (prevents infinite hangs).

## Commands

- Build for tests:
  - `scripts/test-ios.sh build`
- Show/prepare canonical simulator:
  - `scripts/test-ios.sh device`
- Run one UI test (after `build`):
  - `scripts/test-ios.sh ui FinanceAppUITests/FinanceAppUITests/testDashboardShowsCoreSections`
- Run all tests (unit + UI):
  - `scripts/test-ios.sh full-ui`

## Useful env overrides

- Keep other booted simulators:
  - `KEEP_BOOTED=1 scripts/test-ios.sh ui ...`
- Change simulator name:
  - `SIM_NAME="My iPhone" scripts/test-ios.sh device`
