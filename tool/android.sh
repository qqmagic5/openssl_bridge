#!/usr/bin/env bash

set -euo pipefail

readonly ANDROID_MIN_API_LEVEL=21
readonly OPTIMIZATION_FLAG="-O3"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROJECT_ROOT

readonly OUTPUT_LIBRARY_NAME=openssl_bridge
readonly VENDOR_LIBRARY_NAME=crypto
readonly LIBRARY_EXTENSION=so

readonly SRC_DIR="$PROJECT_ROOT/external"
readonly PREBUILT_DIR="$PROJECT_ROOT/prebuilt"

readonly TARGET_OS=android

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
echo "ANDROID_MIN_API_LEVEL: $ANDROID_MIN_API_LEVEL"

if [[ $# -ne 1 ]]; then
  echo "Error: architecture is required. Use: arm64, arm32, x64." >&2
  exit 1
fi
TARGET_ARCH="$1"
case "$TARGET_ARCH" in
  arm64)
    OPENSSL_TARGET="android-arm64"
    ;;
  arm32)
    OPENSSL_TARGET="android-arm"
    ;;
  x64)
    OPENSSL_TARGET="android-x86_64"
    ;;
  *)
    echo "Unsupported architecture: $TARGET_ARCH" >&2
    exit 1
    ;;
esac
echo "TARGET_ARCH: $TARGET_ARCH"

if [[ -z "${ANDROID_NDK_ROOT:-}" ]]; then
  echo "Error: ANDROID_NDK_ROOT is not set." >&2
  exit 1
fi
echo "NDK: $ANDROID_NDK_ROOT"

HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"
echo "HOST_OS: $HOST_OS"
echo "HOST_ARCH: $HOST_ARCH"
case "$HOST_OS" in
  Linux)
    case "$HOST_ARCH" in
      x86_64)  HOST_TAG="linux-x86_64" ;;
      aarch64) HOST_TAG="linux-aarch64" ;;
      *)       
        echo "Error: Unsupported Linux architecture: $HOST_ARCH. Supported: x86_64, aarch64." >&2
        exit 1 
        ;;
    esac
    ;;
  *)
    echo "Unsupported host OS: $HOST_OS" >&2
    exit 1
    ;;
esac
echo "HOST_TAG: $HOST_TAG"

TOOLCHAIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG"
if [ ! -d "$TOOLCHAIN" ]; then
  echo "Error: NDK toolchain not found for host $HOST_OS/$HOST_ARCH:" >&2
  echo "  $TOOLCHAIN" >&2
  exit 1
fi
echo "TOOLCHAIN: $TOOLCHAIN"

case "$TARGET_ARCH" in
  arm64)
    CC="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_MIN_API_LEVEL}-clang"
    ;;
  arm32)
    CC="$TOOLCHAIN/bin/armv7a-linux-androideabi${ANDROID_MIN_API_LEVEL}-clang"
    ;;
  x64)
    CC="$TOOLCHAIN/bin/x86_64-linux-android${ANDROID_MIN_API_LEVEL}-clang"
    ;;
esac

if [ ! -x "$CC" ]; then
  echo "Error: Clang not found in the NDK toolchain: $CC" >&2
  exit 1
fi

step "Changing directory to $SRC_DIR..."
cd "$SRC_DIR"

if [ -f "Makefile" ]; then
    step "Cleaning previous build..."
    make clean > /dev/null
fi

# Почему-то без указания __ANDROID_API__ игнорируется переменная CC
# и выбирается другой компилятор. При этом если явно указать __ANDROID_API__,
# то используется тот компилятор, который требуется, но при этом выводится
# предупреждение о переопределение константы препроцессора. Поэтому используется
# параметр -Wno-macro-redefined, а после выполнения команды проверяется совпадение
# выбранного компилятора с ожидаемым.
step "Configuring library..."
readonly CFLAGS="$OPTIMIZATION_FLAG -Wno-macro-redefined"
echo "CC: $CC"
echo "CFLAGS: $CFLAGS"
export CC
export CFLAGS
export PATH="$TOOLCHAIN/bin:$PATH"
./Configure \
  "$OPENSSL_TARGET" \
  -D__ANDROID_API__="$ANDROID_MIN_API_LEVEL" \
  shared no-tests no-apps \
  > /dev/null
print_config Makefile

step "Check makefile..."
EXPECTED_CC_NAME="$(basename "$CC")"
MAKE_CC_NAME="$(grep '^CC=' Makefile | sed 's/^CC=//')"
MAKE_CC_NAME="${MAKE_CC_NAME#\$(CROSS_COMPILE)}"
if [[ "$MAKE_CC_NAME" != "$EXPECTED_CC_NAME" ]]; then
    echo "Error: OpenSSL Configure selected a different compiler." >&2
    echo "  Requested CC: $EXPECTED_CC_NAME" >&2
    echo "  Makefile CC:  $MAKE_CC_NAME" >&2
    exit 1
fi
echo "CC check: OK"

step "Building library..."
make -j"$(nproc)" > /dev/null

step "Creating output directory..."
readonly OUT_DIR="$PREBUILT_DIR/$TARGET_OS/$TARGET_ARCH"
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

OUT_LIBRARY_SONAME=$OUT_LIBRARY_FILE
patchelf --set-soname "$OUT_LIBRARY_SONAME" "$OUT_LIBRARY_PATH"

step "$OUTPUT_LIBRARY_NAME build completed."
echo "Output: $OUT_DIR"
