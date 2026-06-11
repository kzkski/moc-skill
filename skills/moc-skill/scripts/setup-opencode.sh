#!/usr/bin/env bash
set -euo pipefail

# OpenCode TUI: hide tool execution details by default (quieter UI for end users).
# Persists to OpenCode's KV store (same state as toggling via /details).

STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/opencode"
KV_FILE="${STATE_DIR}/kv.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "setup-opencode.sh: jq is required (brew install jq)" >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"

if [[ -f "${KV_FILE}" ]]; then
  tmp="$(mktemp)"
  jq '.tool_details_visibility = false' "${KV_FILE}" >"${tmp}"
  mv "${tmp}" "${KV_FILE}"
else
  printf '%s\n' '{"tool_details_visibility": false}' >"${KV_FILE}"
fi

echo "setup-opencode.sh: set tool_details_visibility=false in ${KV_FILE}"
echo "Restart OpenCode if it is already running, or run /details once to verify."
