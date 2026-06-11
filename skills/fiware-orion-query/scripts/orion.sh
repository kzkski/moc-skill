#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENDPOINTS_FILE="${ORION_ENDPOINTS_FILE:-${SKILL_DIR}/endpoints.json}"

usage() {
  cat <<'EOF'
Usage: orion.sh <command> [args...]

Commands:
  endpoints                         List configured endpoint names
  types <ep>                        GET /v2/types?options=count
  entities <ep> [k=v ...]           GET /v2/entities
  entity <ep> <id> [k=v ...]        GET /v2/entities/{id}
  count <ep> [k=v ...]              GET /v2/entities with limit=1&options=count
  raw <ep> <path?query>             GET arbitrary path under /v2/

Environment:
  ORION_ENDPOINTS_FILE   Override endpoints.json path
  ORION_DRY_RUN=1        Print curl command without executing
EOF
}

die() {
  echo "orion.sh: $*" >&2
  exit 1
}

require_endpoints_file() {
  [[ -f "${ENDPOINTS_FILE}" ]] || die "endpoints file not found: ${ENDPOINTS_FILE}"
}

list_endpoint_names() {
  require_endpoints_file
  jq -r '.endpoints | keys[]' "${ENDPOINTS_FILE}" | sort
}

resolve_endpoint() {
  local name="$1"
  require_endpoints_file

  if ! jq -e --arg name "${name}" '.endpoints[$name]' "${ENDPOINTS_FILE}" >/dev/null; then
    local available
    available="$(list_endpoint_names | paste -sd ', ' -)"
    die "unknown endpoint '${name}'. Available: ${available:-none}"
  fi

  local base_url service service_path
  base_url="$(jq -r --arg name "${name}" '.endpoints[$name].base_url' "${ENDPOINTS_FILE}")"
  service="$(jq -r --arg name "${name}" '.endpoints[$name].service' "${ENDPOINTS_FILE}")"
  service_path="$(jq -r --arg name "${name}" '.endpoints[$name].service_path' "${ENDPOINTS_FILE}")"

  if [[ ! "${base_url}" =~ ^https?:// ]]; then
    die "invalid base_url for endpoint '${name}': must match ^https?://"
  fi

  RESOLVED_BASE_URL="${base_url}"
  RESOLVED_SERVICE="${service}"
  RESOLVED_SERVICE_PATH="${service_path}"
}

validate_entity_id() {
  local id="$1"
  [[ "${id}" =~ ^[A-Za-z0-9._:~-]+$ ]] || die "invalid entity id '${id}': must match ^[A-Za-z0-9._:~-]+$"
}

validate_raw_path() {
  local path="$1"
  [[ "${path}" =~ ^/v2/ ]] || die "invalid raw path '${path}': must start with /v2/"
}

parse_kv_args() {
  PARSED_KV_KEYS=()
  PARSED_KV_VALUES=()
  while [[ $# -gt 0 ]]; do
    local arg="$1"
    shift
    [[ "${arg}" == *=* ]] || die "expected k=v argument, got '${arg}'"
    PARSED_KV_KEYS+=("${arg%%=*}")
    PARSED_KV_VALUES+=("${arg#*=}")
  done
}

has_kv_key() {
  local key="$1"
  local k
  if ((${#PARSED_KV_KEYS[@]} == 0)); then
    return 1
  fi
  for k in "${PARSED_KV_KEYS[@]}"; do
    [[ "${k}" == "${key}" ]] && return 0
  done
  return 1
}

set_kv() {
  local key="$1"
  local value="$2"
  local i
  if ((${#PARSED_KV_KEYS[@]} > 0)); then
    for i in "${!PARSED_KV_KEYS[@]}"; do
      if [[ "${PARSED_KV_KEYS[$i]}" == "${key}" ]]; then
        PARSED_KV_VALUES[i]="${value}"
        return 0
      fi
    done
  fi
  PARSED_KV_KEYS+=("${key}")
  PARSED_KV_VALUES+=("${value}")
}

apply_default_entity_params() {
  has_kv_key "options" || {
    PARSED_KV_KEYS+=("options")
    PARSED_KV_VALUES+=("keyValues")
  }
  has_kv_key "limit" || {
    PARSED_KV_KEYS+=("limit")
    PARSED_KV_VALUES+=("20")
  }
}

build_curl_args() {
  CURL_ARGS=(-sS --fail-with-body -G -H "Accept: application/json")
  if [[ -n "${RESOLVED_SERVICE}" ]]; then
    CURL_ARGS+=(-H "Fiware-Service: ${RESOLVED_SERVICE}")
  fi
  if [[ -n "${RESOLVED_SERVICE_PATH}" ]]; then
    CURL_ARGS+=(-H "Fiware-ServicePath: ${RESOLVED_SERVICE_PATH}")
  fi
  local i
  if ((${#PARSED_KV_KEYS[@]} > 0)); then
    for i in "${!PARSED_KV_KEYS[@]}"; do
      CURL_ARGS+=(--data-urlencode "${PARSED_KV_KEYS[$i]}=${PARSED_KV_VALUES[$i]}")
    done
  fi
}

print_curl_command() {
  local url="$1"
  shift
  local args=("$@")
  local rendered="curl"
  local arg
  for arg in "${args[@]}"; do
    rendered+=" $(printf '%q' "${arg}")"
  done
  rendered+=" $(printf '%q' "${url}")"
  printf '%s\n' "${rendered}"
}

run_get() {
  local url="$1"
  shift
  build_curl_args

  if [[ "${ORION_DRY_RUN:-}" == "1" ]]; then
    if (( $# > 0 )); then
      print_curl_command "${url}" "${CURL_ARGS[@]}" "$@"
    else
      print_curl_command "${url}" "${CURL_ARGS[@]}"
    fi
    return 0
  fi

  if (( $# > 0 )); then
    curl "${CURL_ARGS[@]}" "$@" "${url}" | jq .
  else
    curl "${CURL_ARGS[@]}" "${url}" | jq .
  fi
}

run_count() {
  local url="$1"
  build_curl_args
  local curl_cmd=(curl "${CURL_ARGS[@]}" -D - -o /dev/null "${url}")

  if [[ "${ORION_DRY_RUN:-}" == "1" ]]; then
    print_curl_command "${url}" "${CURL_ARGS[@]}" -D - -o /dev/null
    return 0
  fi

  local headers
  headers="$("${curl_cmd[@]}")"
  local count
  count="$(printf '%s\n' "${headers}" | awk -F': ' 'tolower($1)=="fiware-total-count" { print $2; exit }' | tr -d '\r')"
  [[ -n "${count}" ]] || die "Fiware-Total-Count header not found in response"
  printf '%s\n' "${count}"
}

cmd_endpoints() {
  require_endpoints_file
  jq -r '.endpoints | to_entries[] | "\(.key)\t\(.value.base_url)\t\(.value.note)"' "${ENDPOINTS_FILE}"
}

cmd_types() {
  local ep="$1"
  resolve_endpoint "${ep}"
  PARSED_KV_KEYS=("options")
  PARSED_KV_VALUES=("count")
  run_get "${RESOLVED_BASE_URL}/v2/types"
}

cmd_entities() {
  local ep="$1"
  shift
  resolve_endpoint "${ep}"
  parse_kv_args "$@"
  apply_default_entity_params
  run_get "${RESOLVED_BASE_URL}/v2/entities"
}

cmd_entity() {
  local ep="$1"
  local id="$2"
  shift 2
  resolve_endpoint "${ep}"
  validate_entity_id "${id}"
  parse_kv_args "$@"
  apply_default_entity_params
  run_get "${RESOLVED_BASE_URL}/v2/entities/${id}"
}

cmd_count() {
  local ep="$1"
  shift
  resolve_endpoint "${ep}"
  parse_kv_args "$@"
  set_kv "limit" "1"
  set_kv "options" "count"
  run_count "${RESOLVED_BASE_URL}/v2/entities"
}

cmd_raw() {
  local ep="$1"
  local path_query="$2"
  resolve_endpoint "${ep}"
  validate_raw_path "${path_query}"

  local path="${path_query%%\?*}"
  local query=""
  if [[ "${path_query}" == *"?"* ]]; then
    query="${path_query#"${path}"}"
    query="${query#\?}"
  fi

  local url="${RESOLVED_BASE_URL}${path}"
  PARSED_KV_KEYS=()
  PARSED_KV_VALUES=()

  if [[ -n "${query}" ]]; then
    local pair key value
    local IFS='&'
    for pair in ${query}; do
      key="${pair%%=*}"
      value="${pair#*=}"
      PARSED_KV_KEYS+=("${key}")
      PARSED_KV_VALUES+=("${value}")
    done
  fi

  run_get "${url}"
}

main() {
  [[ $# -ge 1 ]] || {
    usage
    exit 1
  }

  local command="$1"
  shift

  case "${command}" in
    endpoints)
      [[ $# -eq 0 ]] || die "usage: orion.sh endpoints"
      cmd_endpoints
      ;;
    types)
      [[ $# -eq 1 ]] || die "usage: orion.sh types <ep>"
      cmd_types "$1"
      ;;
    entities)
      [[ $# -ge 1 ]] || die "usage: orion.sh entities <ep> [k=v ...]"
      cmd_entities "$@"
      ;;
    entity)
      [[ $# -ge 2 ]] || die "usage: orion.sh entity <ep> <id> [k=v ...]"
      cmd_entity "$@"
      ;;
    count)
      [[ $# -ge 1 ]] || die "usage: orion.sh count <ep> [k=v ...]"
      cmd_count "$@"
      ;;
    raw)
      [[ $# -eq 2 ]] || die "usage: orion.sh raw <ep> <path?query>"
      cmd_raw "$@"
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      die "unknown command '${command}'"
      ;;
  esac
}

main "$@"
