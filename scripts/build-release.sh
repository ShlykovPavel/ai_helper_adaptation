#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -d "NotchBuddy/NotchBuddy.xcodeproj" ]; then
    if command -v xcodegen >/dev/null 2>&1; then
        echo "Generating NotchBuddy.xcodeproj via xcodegen..."
        (cd NotchBuddy && xcodegen)
    else
        echo "error: NotchBuddy.xcodeproj not found and xcodegen is not installed" >&2
        exit 1
    fi
fi

echo "Building Coucou (NotchBuddy) in Release configuration..."
xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy \
    -configuration Release -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build "$@"
