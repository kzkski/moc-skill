#!/usr/bin/env bats

setup() {
  ORION_SCRIPT="${BATS_TEST_DIRNAME}/../skills/moc-skill/scripts/orion.sh"
  ENDPOINTS_FILE="${BATS_TEST_DIRNAME}/../skills/moc-skill/endpoints.json"
  export ORION_DRY_RUN=1
  export ORION_ENDPOINTS_FILE="${ENDPOINTS_FILE}"
}

@test "endpoints lists configured catalog entries" {
  run "${ORION_SCRIPT}" endpoints
  [ "$status" -eq 0 ]
  [[ "$output" == *"local"* ]]
  [[ "$output" == *"http://localhost:1026"* ]]
  [[ "$output" == *"sendai"* ]]
  [[ "$output" == *"demo"* ]]
}

@test "types dry-run requests /v2/types with options=count" {
  run "${ORION_SCRIPT}" types local
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl"* ]]
  [[ "$output" == *"http://localhost:1026/v2/types"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
}

@test "entities dry-run adds default options=keyValues and limit=20" {
  run "${ORION_SCRIPT}" entities local
  [ "$status" -eq 0 ]
  [[ "$output" == *"/v2/entities"* ]]
  [[ "$output" == *"--data-urlencode options=keyValues"* ]]
  [[ "$output" == *"--data-urlencode limit=20"* ]]
}

@test "entities dry-run respects explicit limit and options overrides" {
  run "${ORION_SCRIPT}" entities local limit=5 options=count
  [ "$status" -eq 0 ]
  [[ "$output" == *"--data-urlencode limit=5"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" != *"limit=20"* ]]
  [[ "$output" != *"options=keyValues"* ]]
}

@test "entity dry-run validates id and adds default query params" {
  run "${ORION_SCRIPT}" entity local "Room1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/v2/entities/Room1"* ]]
  [[ "$output" == *"--data-urlencode options=keyValues"* ]]
  [[ "$output" == *"--data-urlencode limit=20"* ]]
}

@test "entity rejects invalid id with path traversal characters" {
  run "${ORION_SCRIPT}" entity local "../admin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid entity id"* ]]
}

@test "count dry-run forces limit=1 and options=count" {
  run "${ORION_SCRIPT}" count sendai type=Device
  [ "$status" -eq 0 ]
  [[ "$output" == *"/v2/entities"* ]]
  [[ "$output" == *"--data-urlencode type=Device"* ]]
  [[ "$output" == *"--data-urlencode limit=1"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" == *"-D -"* ]]
  [[ "$output" == *"-o /dev/null"* ]]
}

@test "count dry-run overwrites user-supplied limit and options" {
  run "${ORION_SCRIPT}" count local limit=99 options=keyValues
  [ "$status" -eq 0 ]
  [[ "$output" == *"--data-urlencode limit=1"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" != *"limit=99"* ]]
  [[ "$output" != *"options=keyValues"* ]]
}

@test "raw dry-run allows /v2 paths with query string" {
  run "${ORION_SCRIPT}" raw demo "/v2/types?options=count"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://orion.demo.example.jp/v2/types"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" == *"Fiware-Service"* ]]
  [[ "$output" == *"openiot"* ]]
}

@test "raw rejects paths outside /v2" {
  run "${ORION_SCRIPT}" raw local "/admin/config"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid raw path"* ]]
}

@test "unknown endpoint exits with available names" {
  run "${ORION_SCRIPT}" types unknown-platform
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown endpoint 'unknown-platform'"* ]]
  [[ "$output" == *"Available:"* ]]
  [[ "$output" == *"local"* ]]
  [[ "$output" == *"sendai"* ]]
}

@test "sendai endpoint includes Fiware service headers in dry-run" {
  run "${ORION_SCRIPT}" entities sendai
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fiware-Service"* ]]
  [[ "$output" == *"sendai"* ]]
  [[ "$output" == *"Fiware-ServicePath"* ]]
  [[ "$output" == *"/urban"* ]]
}

@test "entities rejects malformed k=v arguments" {
  run "${ORION_SCRIPT}" entities local type
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected k=v argument"* ]]
}
