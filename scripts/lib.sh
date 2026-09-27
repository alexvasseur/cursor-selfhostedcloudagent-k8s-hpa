#!/usr/bin/env bash
# Shared helpers for the Kind pool scripts. Source this file; do not execute it.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "source scripts/lib.sh from another script" >&2
  exit 1
fi

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${_LIB_DIR}/.." && pwd)"

# Caller-supplied values win over .env.
_preset_key="${CURSOR_API_KEY-}"
_preset_file="${KEY_FILE-}"
_preset_pool="${POOL-}"
_preset_skip="${SKIP_QUEUE_SCALER-}"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

[[ -n "$_preset_key" ]] && CURSOR_API_KEY="$_preset_key"
[[ -n "$_preset_file" ]] && KEY_FILE="$_preset_file"
[[ -n "$_preset_pool" ]] && POOL="$_preset_pool"
[[ -n "$_preset_skip" ]] && SKIP_QUEUE_SCALER="$_preset_skip"
unset _preset_key _preset_file _preset_pool _preset_skip

POOL="${POOL:-kind-demo}"

load_api_key() {
  local key=""
  if [[ -n "${CURSOR_API_KEY:-}" ]]; then
    key="$(printf '%s' "$CURSOR_API_KEY" | tr -d '\n\r[:space:]')"
  elif [[ -n "${KEY_FILE:-}" ]]; then
    local key_path="$KEY_FILE"
    if [[ "$key_path" != /* ]]; then
      key_path="$ROOT/$key_path"
    fi
    if [[ ! -r "$key_path" ]]; then
      echo "error: KEY_FILE is not readable: $key_path" >&2
      exit 1
    fi
    key="$(tr -d '\n\r[:space:]' < "$key_path")"
  else
    echo "error: set CURSOR_API_KEY or KEY_FILE to a Cursor service-account API key." >&2
    echo "       Other API key types cannot start pool workers." >&2
    echo "       Copy .env.example to .env or export the variable in your shell." >&2
    exit 1
  fi
  if [[ -z "$key" ]]; then
    echo "error: the API key is empty." >&2
    exit 1
  fi
  printf '%s' "$key"
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "error: $cmd is required and was not found on PATH" >&2
      exit 1
    fi
  done
}
