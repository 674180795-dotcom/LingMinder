#!/bin/zsh
set -euo pipefail
TASK_ROOT=${0:A:h:h}
TASK_BINARY=$(mktemp /private/tmp/lingminder-tests.XXXXXX)
trap 'rm -f "$TASK_BINARY"' EXIT
xcrun swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk -swift-version 5 -module-cache-path /private/tmp/lingminder-swift-cache "$TASK_ROOT/Sources/Core.swift" "$TASK_ROOT/Sources/WidgetLayout.swift" "$TASK_ROOT/Tests/CoreTests.swift" -lsqlite3 -o "$TASK_BINARY"
"$TASK_BINARY"
