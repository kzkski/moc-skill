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
  types <ep> [service=NAME]         GET /v2/types?options=count
  entities <ep> [k=v ...]           GET /v2/entities
  entity <ep> <id> [k=v ...]        GET /v2/entities/{id}
  count <ep> [k=v ...]              GET /v2/entities with limit=1&options=count
  raw <ep> <path?query> [service=NAME]
                                    GET arbitrary path under /v2/

Notes:
  If an endpoint defines multiple Fiware-Service values, pass service=NAME
  (reserved; not sent to Orion as a query parameter).

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
  local service_selector="${2:-}"

  require_endpoints_file

  if ! jq -e --arg name "${name}" '.endpoints[$name]' "${ENDPOINTS_FILE}" >/dev/null; then
    local available
    available="$(list_endpoint_names | paste -sd ', ' -)"
    die "unknown endpoint '${name}'. Available: ${available:-none}"
  fi

  local base_url
  base_url="$(jq -r --arg name "${name}" '.endpoints[$name].base_url' "${ENDPOINTS_FILE}")"

  if [[ ! "${base_url}" =~ ^https?:// ]]; then
    die "invalid base_url for endpoint '${name}': must match ^https?://"
  fi

  local resolved_json
  resolved_json="$(jq -c --arg name "${name}" --arg sel "${service_selector}" '
    def service_item($default_path):
      if type == "string" then {value: ., path: $default_path, note: ""}
      else {value: .value, path: (.["Fiware-ServicePath"] // $default_path), note: (.note // "")}
      end;
    def service_label:
      if .note == "" then .value else "\(.value) (\(.note))" end;
    .endpoints[$name] as $ep |
    ($ep["Fiware-ServicePath"] // "") as $default_path |
    ($ep["Fiware-Service"]) as $fs |
    (if $fs == null then []
     elif ($fs | type) == "string" then [($fs | service_item($default_path))]
     elif ($fs | type) == "array" then
       [$fs[] | service_item($default_path)]
     else [{error: "invalid Fiware-Service type for endpoint \($name)"}]
     end) as $items |
    if ($items | length) > 0 and ($items[0] | has("error")) then
      $items[0]
    elif ($items | length) == 0 then
      {service: "", path: $default_path}
    elif ($items | length) == 1 then
      {service: $items[0].value, path: $items[0].path}
    elif $sel == "" then
      {error: "endpoint \($name) has multiple Fiware-Service values; specify service=NAME",
       available: [$items[] | service_label]}
    else
      ($items | map(select(.value == $sel)) | first) as $match |
      if $match == null then
        {error: "unknown service \($sel) for endpoint \($name)",
         available: [$items[] | service_label]}
      else
        {service: $match.value, path: $match.path}
      end
    end
  ' "${ENDPOINTS_FILE}")"

  if jq -e '.error' <<< "${resolved_json}" >/dev/null; then
    local message available
    message="$(jq -r '.error' <<< "${resolved_json}")"
    if jq -e '.available' <<< "${resolved_json}" >/dev/null; then
      available="$(jq -r '.available | join(", ")' <<< "${resolved_json}")"
      die "${message}. Available: ${available}"
    fi
    die "${message}"
  fi

  RESOLVED_BASE_URL="${base_url}"
  RESOLVED_SERVICE="$(jq -r '.service // ""' <<< "${resolved_json}")"
  RESOLVED_SERVICE_PATH="$(jq -r '.path // ""' <<< "${resolved_json}")"
}

validate_entity_id() {
  local id="$1"
  [[ "${id}" =~ ^[A-Za-z0-9._:~-]+$ ]] || die "invalid entity id '${id}': must match ^[A-Za-z0-9._:~-]+$"
}

validate_raw_path() {
  local path_query="$1"
  local path="${path_query%%\?*}"

  [[ "${path}" =~ ^/v2/ ]] || die "invalid raw path '${path_query}': must start with /v2/"
  # Only plain path characters; rejects percent-encoding (e.g. %2e%2e) and backslashes.
  [[ "${path}" =~ ^/v2/[A-Za-z0-9._:~/-]*$ ]] ||
    die "invalid raw path '${path_query}': path may only contain [A-Za-z0-9._:~/-]"
  # Reject dot segments and empty segments so the path cannot escape /v2/.
  case "${path%/}/" in
    */../* | */./* | *//*)
      die "invalid raw path '${path_query}': '.', '..' and empty path segments are not allowed"
      ;;
  esac
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

get_kv_value() {
  local key="$1"
  local i
  for i in "${!PARSED_KV_KEYS[@]}"; do
    if [[ "${PARSED_KV_KEYS[$i]}" == "${key}" ]]; then
      echo "${PARSED_KV_VALUES[$i]}"
      return 0
    fi
  done
  return 1
}

remove_kv_key() {
  local key="$1"
  local new_keys=() new_values=()
  local i
  if ((${#PARSED_KV_KEYS[@]} > 0)); then
    for i in "${!PARSED_KV_KEYS[@]}"; do
      if [[ "${PARSED_KV_KEYS[$i]}" != "${key}" ]]; then
        new_keys+=("${PARSED_KV_KEYS[$i]}")
        new_values+=("${PARSED_KV_VALUES[$i]}")
      fi
    done
  fi
  PARSED_KV_KEYS=("${new_keys[@]+"${new_keys[@]}"}")
  PARSED_KV_VALUES=("${new_values[@]+"${new_values[@]}"}")
}

extract_service_selector() {
  SELECTED_SERVICE=""
  if has_kv_key "service"; then
    SELECTED_SERVICE="$(get_kv_value "service")"
    remove_kv_key "service"
  fi
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
  CURL_ARGS=(-sS --fail-with-body --path-as-is -G -H "Accept: application/json")
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
  jq -r '
    def format_service_entry:
      if type == "string" then .
      else .value + (if (.note // "") != "" then " (\(.note))" else "" end)
      end;
    .endpoints | to_entries[] |
    (.value["Fiware-Service"] |
      if . == null then ""
      elif type == "string" then .
      elif type == "array" then
        map(format_service_entry) | join(", ")
      else "" end) as $services |
    "\(.key)\t\(.value.base_url)\t\($services)\t\(.value.note // "")"
  ' "${ENDPOINTS_FILE}"
}

cmd_types() {
  local ep="$1"
  shift
  local service_selector=""
  if [[ $# -ge 1 ]]; then
    [[ "${1}" == service=* ]] || die "usage: orion.sh types <ep> [service=NAME]"
    service_selector="${1#service=}"
  fi
  resolve_endpoint "${ep}" "${service_selector}"
  PARSED_KV_KEYS=("options")
  PARSED_KV_VALUES=("count")
  run_get "${RESOLVED_BASE_URL}/v2/types"
}

cmd_entities() {
  local ep="$1"
  shift
  parse_kv_args "$@"
  extract_service_selector
  resolve_endpoint "${ep}" "${SELECTED_SERVICE}"
  apply_default_entity_params
  run_get "${RESOLVED_BASE_URL}/v2/entities"
}

cmd_entity() {
  local ep="$1"
  local id="$2"
  shift 2
  validate_entity_id "${id}"
  parse_kv_args "$@"
  extract_service_selector
  resolve_endpoint "${ep}" "${SELECTED_SERVICE}"
  apply_default_entity_params
  run_get "${RESOLVED_BASE_URL}/v2/entities/${id}"
}

cmd_count() {
  local ep="$1"
  shift
  parse_kv_args "$@"
  extract_service_selector
  resolve_endpoint "${ep}" "${SELECTED_SERVICE}"
  set_kv "limit" "1"
  set_kv "options" "count"
  run_count "${RESOLVED_BASE_URL}/v2/entities"
}

cmd_raw() {
  local ep="$1"
  local path_query="$2"
  shift 2
  local service_selector=""
  if [[ $# -ge 1 ]]; then
    [[ "${1}" == service=* ]] || die "usage: orion.sh raw <ep> <path?query> [service=NAME]"
    service_selector="${1#service=}"
  fi
  resolve_endpoint "${ep}" "${service_selector}"
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
      [[ $# -ge 1 ]] || die "usage: orion.sh types <ep> [service=NAME]"
      cmd_types "$@"
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
      [[ $# -ge 2 ]] || die "usage: orion.sh raw <ep> <path?query> [service=NAME]"
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
