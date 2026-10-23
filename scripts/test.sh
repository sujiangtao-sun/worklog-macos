#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVELOPER_DIR_PATH="$(xcode-select -p)"
FRAMEWORK_ARGS=()

for candidate in \
    "$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
    "$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"; do
    if [[ -d "$candidate/Testing.framework" ]]; then
        FRAMEWORK_ARGS=(
            -Xswiftc -F -Xswiftc "$candidate"
            -Xlinker -F -Xlinker "$candidate"
            -Xlinker -framework -Xlinker Testing
        )
        break
    fi
done

swift test --build-system native "${FRAMEWORK_ARGS[@]}" "$@"
