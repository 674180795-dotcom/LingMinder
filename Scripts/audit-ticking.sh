#!/bin/zsh
set -euo pipefail
TASK_ROOT=${0:A:h:h}
mkdir -p "$TASK_ROOT/test-output"
xcrun swift -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk -module-cache-path /private/tmp/lingminder-swift-cache "$TASK_ROOT/Scripts/audio-audit.swift" "$TASK_ROOT/Resources/Audio/ticking.m4a" "$TASK_ROOT/test-output/ticking-600s" 600
