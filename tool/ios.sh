#!/usr/bin/env bash

set -euo pipefail

readonly OPTIMIZATION_FLAG="-O3"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROJECT_ROOT

readonly OUTPUT_LIBRARY_NAME=openssl_bridge
readonly VENDOR_LIBRARY_NAME=crypto
readonly LIBRARY_EXTENSION=dylib

readonly SRC_DIR="$PROJECT_ROOT/external"
readonly PREBUILT_DIR="$PROJECT_ROOT/prebuilt"

readonly TARGET_OS=ios
readonly IOS_MIN_VERSION=12.0

# shellcheck source=/dev/null
source "$PROJECT_ROOT/tool/_utils.sh"
trap clean EXIT

step "Build options"
echo "PROJECT_ROOT: $PROJECT_ROOT"
echo ""
echo "SRC_DIR: $SRC_DIR"
echo "PREBUILT_DIR: $PREBUILT_DIR"
echo ""
echo "OUTPUT_LIBRARY_NAME: $OUTPUT_LIBRARY_NAME"
echo "VENDOR_LIBRARY_NAME: $VENDOR_LIBRARY_NAME"
echo "LIBRARY_EXTENSION: $LIBRARY_EXTENSION"
echo ""
echo "TARGET_OS: $TARGET_OS"
echo ""
echo "OPTIMIZATION_FLAG: $OPTIMIZATION_FLAG"
echo "IOS_MIN_VERSION: $IOS_MIN_VERSION"

if [[ $# -ne 1 ]]; then
  echo "Error: platform are required. Use: <device|simulator>." >&2
  exit 1
fi
readonly TARGET_PLATFORM="$1"
readonly TARGET_ARCH="arm64"
echo "TARGET_PLATFORM: $TARGET_PLATFORM"
echo "TARGET_ARCH: $TARGET_ARCH"

case "$TARGET_PLATFORM" in
  device)
    OPENSSL_TARGET="ios64-xcrun"
    MIN_VERSION_FLAG="-miphoneos-version-min=${IOS_MIN_VERSION}"
    ;;
  simulator)
    OPENSSL_TARGET="iossimulator-arm64-xcrun"
    MIN_VERSION_FLAG="-mios-simulator-version-min=${IOS_MIN_VERSION}"
    ;;
  *)
    echo "Error: unsupported platform '$TARGET_PLATFORM'. Use: device or simulator." >&2
    exit 1
    ;;
esac

step "Changing directory to $SRC_DIR..."
cd "$SRC_DIR"

if [ -f "Makefile" ]; then
    step "Cleaning previous build..."
    make clean > /dev/null
fi

step "Configuring library..."
readonly CFLAGS="$OPTIMIZATION_FLAG"
readonly LDFLAGS="-Wl,-headerpad_max_install_names"
echo "CFLAGS: $CFLAGS"
echo "LDFLAGS: $LDFLAGS"
echo "OPENSSL_TARGET: $OPENSSL_TARGET"
echo "IOS_MIN_VERSION: $IOS_MIN_VERSION"
echo "MIN_VERSION_FLAG: $MIN_VERSION_FLAG"
export CC
export CFLAGS
export LDFLAGS
"./Configure" \
  "$OPENSSL_TARGET" \
  shared no-tests no-apps \
  "$MIN_VERSION_FLAG" \
  > /dev/null
print_config Makefile

step "Building library..."
make -j"$(sysctl -n hw.logicalcpu)" > /dev/null

step "Creating output directory..."
readonly OUT_DIR="$PREBUILT_DIR/$TARGET_OS/$TARGET_PLATFORM/$TARGET_ARCH"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

step "Copying files to output directory..."
readonly OUT_LIBRARY_FILE=lib$OUTPUT_LIBRARY_NAME.$LIBRARY_EXTENSION
readonly OUT_LIBRARY_PATH="$OUT_DIR/$OUT_LIBRARY_FILE"
cp -L "$SRC_DIR/lib$VENDOR_LIBRARY_NAME.$LIBRARY_EXTENSION" "$OUT_LIBRARY_PATH"
readonly OUT_INCLUDE_DIR="$OUT_DIR/include/openssl/"
mkdir -p "$OUT_DIR/include"
cp -R "$SRC_DIR/include/openssl/" "$OUT_INCLUDE_DIR"
if ! test -s "$OUT_LIBRARY_PATH"; then
  echo "Error: output library is missing or empty: $OUT_LIBRARY_PATH" >&2
  exit 1
fi
if is_dir_empty "$OUT_INCLUDE_DIR"; then
  echo "Error: OpenSSL headers are missing or empty: $OUT_INCLUDE_DIR" >&2
  exit 1
fi

echo "Setting rpath..."
install_name_tool -id "@rpath/lib${OUTPUT_LIBRARY_NAME}.${LIBRARY_EXTENSION}" "$OUT_FILE"

step "$OUTPUT_LIBRARY_NAME build completed."
echo "Output: $OUT_DIR"
