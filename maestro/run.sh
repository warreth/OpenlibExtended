#!/usr/bin/env bash
# Runs the Maestro end-to-end flows in order. The app must be installed
# on the connected device/emulator and the flows share state, so keep the
# order: onboarding -> search -> download -> mirrors.
set -euo pipefail

cd "$(dirname "$0")"

maestro test \
  --config config.yaml \
  01_onboarding.yaml \
  02_search.yaml \
  03_download_and_read.yaml \
  04_mirrors.yaml
