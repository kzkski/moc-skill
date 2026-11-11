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
  [[ "$output" == *"Sandbox"* ]]
  [[ "$output" == *"https://orion.sandbox.makeour.city"* ]]
  [[ "$output" == *"sagacity"* ]]
  [[ "$output" == *"moc_sagacity (水位等)"* ]]
  [[ "$output" == *"yokosuka"* ]]
}

@test "types dry-run requests /v2/types with options=count" {
  run "${ORION_SCRIPT}" types Sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"curl"* ]]
  [[ "$output" == *"https://orion.sandbox.makeour.city/v2/types"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
}

@test "entities dry-run adds default options=keyValues and limit=20" {
  run "${ORION_SCRIPT}" entities Sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"/v2/entities"* ]]
  [[ "$output" == *"--data-urlencode options=keyValues"* ]]
  [[ "$output" == *"--data-urlencode limit=20"* ]]
}

@test "entities dry-run respects explicit limit and options overrides" {
  run "${ORION_SCRIPT}" entities Sandbox limit=5 options=count
  [ "$status" -eq 0 ]
  [[ "$output" == *"--data-urlencode limit=5"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" != *"limit=20"* ]]
  [[ "$output" != *"options=keyValues"* ]]
}

@test "entity dry-run validates id and adds default query params" {
  run "${ORION_SCRIPT}" entity Sandbox "Room1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/v2/entities/Room1"* ]]
  [[ "$output" == *"--data-urlencode options=keyValues"* ]]
  [[ "$output" == *"--data-urlencode limit=20"* ]]
}

@test "entity rejects invalid id with path traversal characters" {
  run "${ORION_SCRIPT}" entity Sandbox "../admin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid entity id"* ]]
}

@test "count dry-run forces limit=1 and options=count" {
  run "${ORION_SCRIPT}" count yokosuka type=WeatherForecast
  [ "$status" -eq 0 ]
  [[ "$output" == *"/v2/entities"* ]]
  [[ "$output" == *"--data-urlencode type=WeatherForecast"* ]]
  [[ "$output" == *"--data-urlencode limit=1"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" == *"-D -"* ]]
  [[ "$output" == *"-o /dev/null"* ]]
}

@test "count dry-run overwrites user-supplied limit and options" {
  run "${ORION_SCRIPT}" count Sandbox limit=99 options=keyValues
  [ "$status" -eq 0 ]
  [[ "$output" == *"--data-urlencode limit=1"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" != *"limit=99"* ]]
  [[ "$output" != *"options=keyValues"* ]]
}

@test "raw dry-run allows /v2 paths with query string" {
  run "${ORION_SCRIPT}" raw yokosuka "/v2/types?options=count"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://orion.yokosuka.makeour.city/v2/types"* ]]
  [[ "$output" == *"--data-urlencode options=count"* ]]
  [[ "$output" == *"Fiware-Service"* ]]
  [[ "$output" == *"yokosuka_tenki"* ]]
}

@test "raw rejects paths outside /v2" {
  run "${ORION_SCRIPT}" raw Sandbox "/admin/config"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid raw path"* ]]
}

@test "raw rejects dot-segment path traversal" {
  for p in "/v2/../version" "/v2/entities/../../version" "/v2/./entities" "/v2/.." "/v2//entities" "/v2/entities/.."; do
    run "${ORION_SCRIPT}" raw Sandbox "${p}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid raw path"* ]]
  done
}

@test "raw rejects percent-encoded and special characters in path" {
  for p in "/v2/%2e%2e/version" "/v2/entities%2f..%2fversion" '/v2/entities\..\version' "/v2/entities;x"; do
    run "${ORION_SCRIPT}" raw Sandbox "${p}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid raw path"* ]]
  done
}

@test "raw allows entity id paths and ignores dots in the query string" {
  run "${ORION_SCRIPT}" raw Sandbox "/v2/entities/urn:ngsi-ld:Room~1.a?q=a..b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://orion.sandbox.makeour.city/v2/entities/urn:ngsi-ld:Room~1.a"* ]]
}

@test "curl is invoked with --path-as-is" {
  run "${ORION_SCRIPT}" entities Sandbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"--path-as-is"* ]]
}

@test "unknown endpoint exits with available names" {
  run "${ORION_SCRIPT}" types unknown-platform
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown endpoint 'unknown-platform'"* ]]
  [[ "$output" == *"Available:"* ]]
  [[ "$output" == *"Sandbox"* ]]
  [[ "$output" == *"sagacity"* ]]
}

@test "yokosuka endpoint includes Fiware service headers in dry-run" {
  run "${ORION_SCRIPT}" entities yokosuka
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fiware-Service"* ]]
  [[ "$output" == *"yokosuka_tenki"* ]]
  [[ "$output" == *"Fiware-ServicePath"* ]]
  [[ "$output" == *"/"* ]]
}

@test "entities rejects malformed k=v arguments" {
  run "${ORION_SCRIPT}" entities Sandbox type
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected k=v argument"* ]]
}

@test "multi-service endpoint requires service selector" {
  run "${ORION_SCRIPT}" entities sagacity
  [ "$status" -eq 1 ]
  [[ "$output" == *"multiple Fiware-Service values"* ]]
  [[ "$output" == *"Available:"* ]]
  [[ "$output" == *"moc_sagacity (水位等)"* ]]
  [[ "$output" == *"sagacity_topita"* ]]
}

@test "multi-service endpoint accepts service selector" {
  run "${ORION_SCRIPT}" entities sagacity service=moc_sagacity
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://orion.sagacity.makeour.city/v2/entities"* ]]
  [[ "$output" == *"moc_sagacity"* ]]
  [[ "$output" != *"--data-urlencode service="* ]]
}

@test "multi-service endpoint rejects unknown service selector" {
  run "${ORION_SCRIPT}" entities sagacity service=unknown_service
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown service unknown_service"* ]]
}

@test "service selector is not sent as NGSI query parameter" {
  run "${ORION_SCRIPT}" entities sagacity service=sagacity_topita type=TopitaPointUser limit=5
  [ "$status" -eq 0 ]
  [[ "$output" == *"sagacity_topita"* ]]
  [[ "$output" == *"--data-urlencode type=TopitaPointUser"* ]]
  [[ "$output" != *"--data-urlencode service="* ]]
}

@test "types supports service selector for multi-service endpoint" {
  run "${ORION_SCRIPT}" types sagacity service=moc_sagacity
  [ "$status" -eq 0 ]
  [[ "$output" == *"/v2/types"* ]]
  [[ "$output" == *"moc_sagacity"* ]]
}

@test "raw supports service selector for multi-service endpoint" {
  run "${ORION_SCRIPT}" raw sagacity "/v2/entities?limit=1" service=sagacity_ikunowa
  [ "$status" -eq 0 ]
  [[ "$output" == *"sagacity_ikunowa"* ]]
}
