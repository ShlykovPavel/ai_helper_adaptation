#!/usr/bin/env bash
set -euo pipefail

ORIG_PWD="$(pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="${CONFIGURATION_BUILD_DIR:-}"
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --build-dir)
            if [ $# -lt 2 ]; then
                echo "error: --build-dir requires an argument" >&2
                exit 1
            fi
            BUILD_DIR="$2"
            shift 2
            ;;
        --build-dir=*)
            BUILD_DIR="${1#*=}"
            shift 1
            ;;
        CONFIGURATION_BUILD_DIR=*)
            BUILD_DIR="${1#*=}"
            shift 1
            ;;
        *)
            if [ -z "$BUILD_DIR" ] && [ ${#EXTRA_ARGS[@]} -eq 0 ]; then
                case "$1" in
                    build|analyze|archive|test|installsrc|install|clean|-*)
                        EXTRA_ARGS+=("$1")
                        ;;
                    *)
                        BUILD_DIR="$1"
                        ;;
                esac
            else
                EXTRA_ARGS+=("$1")
            fi
            shift 1
            ;;
    esac
done

if [ ! -d "NotchBuddy/NotchBuddy.xcodeproj" ]; then
    if command -v xcodegen >/dev/null 2>&1; then
        echo "Generating NotchBuddy.xcodeproj via xcodegen..."
        (cd NotchBuddy && xcodegen)
    else
        echo "error: NotchBuddy.xcodeproj not found and xcodegen is not installed" >&2
        exit 1
    fi
fi

XCODE_ARGS=(
    -project NotchBuddy/NotchBuddy.xcodeproj
    -scheme NotchBuddy
    -configuration Release
    -destination 'platform=macOS'
    'ARCHS=arm64 x86_64'
    ONLY_ACTIVE_ARCH=NO
    CODE_SIGNING_ALLOWED=NO
)

if [ -n "$BUILD_DIR" ]; then
    if [[ "$BUILD_DIR" != /* ]]; then
        BUILD_DIR="$ORIG_PWD/$BUILD_DIR"
    fi
    mkdir -p "$BUILD_DIR"
    XCODE_ARGS+=("CONFIGURATION_BUILD_DIR=$BUILD_DIR")
fi

echo "Building Coucou (NotchBuddy) in Release configuration (Universal: arm64 + x86_64)..."
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    xcodebuild "${XCODE_ARGS[@]}" build "${EXTRA_ARGS[@]}"
else
    xcodebuild "${XCODE_ARGS[@]}" build
fi
