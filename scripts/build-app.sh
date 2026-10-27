#!/bin/bash
set -euo pipefail

TASK_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_OUTPUT_DIR="${1:-${TASK_REPO_ROOT}/dist}"
TASK_APP_PATH="${TASK_OUTPUT_DIR}/HaLow Swift.app"

swift build --package-path "${TASK_REPO_ROOT}" -c release --product HaLowSwift
TASK_BIN_DIR="$(swift build --package-path "${TASK_REPO_ROOT}" -c release --show-bin-path)"
mkdir -p "${TASK_APP_PATH}/Contents/MacOS" "${TASK_APP_PATH}/Contents/Resources"
cp "${TASK_BIN_DIR}/HaLowSwift" "${TASK_APP_PATH}/Contents/MacOS/HaLowSwift"
cp "${TASK_REPO_ROOT}/Resources/Info.plist" "${TASK_APP_PATH}/Contents/Info.plist"
printf 'APPL????' > "${TASK_APP_PATH}/Contents/PkgInfo"

TASK_ICON_WORK="${TASK_REPO_ROOT}/.build/app-icon"
TASK_ICON_SET="${TASK_ICON_WORK}/AppIcon.iconset"
mkdir -p "${TASK_ICON_SET}"
swift "${TASK_REPO_ROOT}/scripts/make-icon.swift" "${TASK_ICON_WORK}/icon.png"
for TASK_SIZE in 16 32 128 256 512; do
    sips -z "${TASK_SIZE}" "${TASK_SIZE}" "${TASK_ICON_WORK}/icon.png" --out "${TASK_ICON_SET}/icon_${TASK_SIZE}x${TASK_SIZE}.png" >/dev/null
    TASK_DOUBLE_SIZE=$((TASK_SIZE * 2))
    sips -z "${TASK_DOUBLE_SIZE}" "${TASK_DOUBLE_SIZE}" "${TASK_ICON_WORK}/icon.png" --out "${TASK_ICON_SET}/icon_${TASK_SIZE}x${TASK_SIZE}@2x.png" >/dev/null
done
iconutil --convert icns "${TASK_ICON_SET}" --output "${TASK_APP_PATH}/Contents/Resources/AppIcon.icns"

# Ad hoc signing is for this local development build.
# Distribution needs a Developer ID identity and separate signing validation.
codesign --force --sign - "${TASK_APP_PATH}"
printf 'Built %s\n' "${TASK_APP_PATH}"
