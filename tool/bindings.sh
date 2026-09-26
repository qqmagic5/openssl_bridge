#!/usr/bin/env bash

set -euo pipefail

readonly HEADERS=(
  external/include/openssl/err.h
  external/include/openssl/pem.h
  external/include/openssl/evp.h
  external/include/openssl/rsa.h
  external/include/openssl/rand.h
  external/include/openssl/hmac.h
  external/include/openssl/pkcs5.h
  external/include/openssl/core_names.h
  external/include/openssl/kdf.h
  external/include/openssl/params.h
  external/include/openssl/decoder.h
  external/include/openssl/bio.h
)

readonly INCLUDES=(
  external/include/
)

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly PROJECT_ROOT

readonly SRC_DIR="$PROJECT_ROOT/external"

readonly OUTPUT_LIBRARY_NAME=openssl_bridge
readonly PACKAGE_NAME=openssl_bridge
readonly API_FILE="$PROJECT_ROOT/lib/api.g.dart"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/tool/_utils.sh"
trap clean EXIT

cd "$SRC_DIR"

if [ -f "Makefile" ]; then
    step "Cleaning previous build..."
    make clean > /dev/null
fi

step "Configuring library..."
./Configure \
  shared no-tests no-apps \
  > /dev/null

step "Generating library files..."
make -j"$(nproc)" build_generated > /dev/null

cd "$PROJECT_ROOT"

ARGS=()

for header in "${HEADERS[@]}"; do
  ARGS+=(--header "$header")
done

for include in "${INCLUDES[@]}"; do
  ARGS+=(--cflag "-I$include")
done

dart run libffigen:make \
  "${ARGS[@]}" \
  --asset-package $PACKAGE_NAME \
  --asset-id $OUTPUT_LIBRARY_NAME \
  --output "$API_FILE"

if ! test -s "$API_FILE"; then
  echo "Error: generated API file is missing or empty: $API_FILE" >&2
  exit 1
fi

echo "Output: $API_FILE"
