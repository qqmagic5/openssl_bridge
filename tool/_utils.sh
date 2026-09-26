#!/usr/bin/env bash

set -euo pipefail

step() {
  echo "==> $*"
}

clean() {
  step "Cleaning external directory via git..."
  git -C "$SRC_DIR" checkout -q HEAD -- . 2>/dev/null
  git -C "$SRC_DIR" clean -fdq . 2>/dev/null
}

print_config() {
  local makefile="$1"

  step "Makefile config"
  grep -E '^(CC|CFLAGS|LDFLAGS)' "$makefile"
  echo ""
}

# Если директория пустая, то функция завершится кодом 0,
# иначе результатом будет код 1.
is_dir_empty() {
  [[ -z "$(find "$1" -type f -print -quit)" ]]
}
