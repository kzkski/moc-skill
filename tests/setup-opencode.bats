#!/usr/bin/env bats

setup() {
  SETUP_SCRIPT="${BATS_TEST_DIRNAME}/../skills/moc-skill/scripts/setup-opencode.sh"
  TEST_STATE_DIR="${BATS_TMPDIR}/opencode-setup-test"
  rm -rf "${TEST_STATE_DIR}"
  export XDG_STATE_HOME="${TEST_STATE_DIR}"
}

@test "setup-opencode creates kv.json with tool_details_visibility false" {
  run "${SETUP_SCRIPT}"
  [ "$status" -eq 0 ]

  kv="${TEST_STATE_DIR}/opencode/kv.json"
  [ -f "${kv}" ]
  [ "$(jq -r '.tool_details_visibility' "${kv}")" = "false" ]
}

@test "setup-opencode preserves existing kv.json keys" {
  mkdir -p "${TEST_STATE_DIR}/opencode"
  printf '%s\n' '{"theme":"opencode","tool_details_visibility":true}' \
    >"${TEST_STATE_DIR}/opencode/kv.json"

  run "${SETUP_SCRIPT}"
  [ "$status" -eq 0 ]

  kv="${TEST_STATE_DIR}/opencode/kv.json"
  [ "$(jq -r '.theme' "${kv}")" = "opencode" ]
  [ "$(jq -r '.tool_details_visibility' "${kv}")" = "false" ]
}
