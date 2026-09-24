#!/usr/bin/env bash

# Shared helpers for scripts invoked from any working directory.

mozais_repo_root() {
  local caller_path="${BASH_SOURCE[1]}"
  cd -- "$(dirname -- "$caller_path")/.." && pwd
}

mozais_require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    return 1
  fi
}

mozais_require_file() {
  local file_path="$1"
  local description="$2"
  if [[ ! -f "$file_path" ]]; then
    printf 'Missing %s: %s\n' "$description" "$file_path" >&2
    return 1
  fi
}

mozais_log_dir() {
  local repo_root="$1"
  local log_dir="${MOZAIS_LOG_DIR:-$repo_root/logs}"
  mkdir -p -- "$log_dir"
  printf '%s\n' "$log_dir"
}

mozais_run_dev_cli() {
  local repo_root="$1"
  shift

  local dart_bin="${MOZAIS_DART_BIN:-}"
  if [[ -z "$dart_bin" && -n "${MOZAIS_FLUTTER_BIN:-}" ]]; then
    dart_bin="$(dirname -- "$MOZAIS_FLUTTER_BIN")/dart"
  fi

  if [[ -n "$dart_bin" ]]; then
    exec "$dart_bin" "$repo_root/tool/mozais.dart" "$@"
  fi

  cd -- "$repo_root"
  exec fvm dart run tool/mozais.dart "$@"
}
