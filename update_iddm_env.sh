#!/usr/bin/env bash

set -Eeuo pipefail

ENV_FILE=.env
ZOOKEEPER_IMAGE=radiantone/zookeeper
AUTH_URL="https://auth.docker.io/token?service=registry.docker.io&scope=repository:${ZOOKEEPER_IMAGE}:pull"
TAGS_URL="https://registry-1.docker.io/v2/${ZOOKEEPER_IMAGE}/tags/list"

check_required_tools() {
  local missing
  missing=()

  if ! command -v curl > /dev/null; then
    missing+=("curl (used to query the Docker registry for published Zookeeper images)")
  fi

  if ! command -v jq > /dev/null; then
    missing+=("jq (used to read the registry's JSON response)")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "This script cannot run because the following tools are not installed:" >&2
    local tool
    for tool in "${missing[@]}"; do
      echo "  - $tool" >&2
    done
    echo "Install them and run this script again." >&2
    exit 1
  fi
}

check_for_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    echo "Missing $ENV_FILE file, this script must be run from the root of this project" >&2
    exit 1
  fi
}

# Writes the value of the requested variable in .env to stdout
read_env_value() {
  local variable_name value
  variable_name="$1"

  value="$(grep -E "^${variable_name}=" "$ENV_FILE" || true)"
  if [ -z "$value" ]; then
    echo "Cannot find $variable_name in $ENV_FILE" >&2
    exit 1
  fi

  value="${value#*=}"
  value="${value%\"}"
  value="${value#\"}"
  echo "$value"
}

# Asks the operator which IDDM version to upgrade to, writing their answer to stdout.
# The current version is offered as the default.
prompt_for_iddm_version() {
  local current_version answer
  current_version="$1"

  read -r -p "Enter the IDDM version to upgrade to [$current_version]: " answer

  echo "${answer:-$current_version}"
}

# Writes every published Zookeeper image tag to stdout, one per line
fetch_zookeeper_tags() {
  local token
  token="$(curl -sS --fail-with-body "$AUTH_URL" | jq -r '.token')"
  curl -sS --fail-with-body -H "Authorization: Bearer $token" "$TAGS_URL" | jq -r '.tags[]'
}

# Writes the Zookeeper base version of every tag published for the given IDDM version to
# stdout, one per line. A tag qualifies only when the IDDM version is the whole of its
# suffix, so that variant images such as -fips are excluded, and only when a base version
# precedes it, so that tags carrying no base version at all are excluded.
find_base_versions() {
  local iddm_version escaped_version
  iddm_version="$1"

  escaped_version="${iddm_version//./\\.}"
  sed -nE "s/^(.+)-iddm-${escaped_version}\$/\1/p"
}

# Replaces the value of the given variable in .env, leaving the rest of the file alone
write_env_value() {
  local variable_name value temp_file
  variable_name="$1"
  value="$2"

  temp_file="$(mktemp)"
  sed -E "s|^${variable_name}=.*\$|${variable_name}=\"${value}\"|" "$ENV_FILE" > "$temp_file"
  mv "$temp_file" "$ENV_FILE"
}

execute() {
  check_required_tools
  check_for_env_file

  local current_iddm_version iddm_version current_base_version
  current_iddm_version="$(read_env_value IDDM_VERSION)"
  current_base_version="$(read_env_value ZOOKEEPER_BASE_VERSION)"
  iddm_version="$(prompt_for_iddm_version "$current_iddm_version")"

  echo "Looking up the Zookeeper base version for IDDM $iddm_version..."

  local tags base_versions
  tags="$(fetch_zookeeper_tags)"
  readarray -t base_versions < <(echo "$tags" | find_base_versions "$iddm_version")

  if [ "${#base_versions[@]}" -eq 0 ]; then
    echo "No $ZOOKEEPER_IMAGE image is published for IDDM $iddm_version." >&2
    echo "Check that the IDDM version is correct. No changes were written to $ENV_FILE." >&2
    exit 1
  fi

  if [ "${#base_versions[@]}" -gt 1 ]; then
    echo "Multiple $ZOOKEEPER_IMAGE images are published for IDDM $iddm_version, so the" >&2
    echo "Zookeeper base version is ambiguous. These base versions were found:" >&2
    local candidate
    for candidate in "${base_versions[@]}"; do
      echo "  - $candidate" >&2
    done
    echo "Choose one and set ZOOKEEPER_BASE_VERSION by hand. No changes were written to $ENV_FILE." >&2
    exit 1
  fi

  local base_version
  base_version="${base_versions[0]}"

  if [ "$iddm_version" = "$current_iddm_version" ] && [ "$base_version" = "$current_base_version" ]; then
    echo "$ENV_FILE is already correct for IDDM $iddm_version, nothing to change."
    exit 0
  fi

  write_env_value IDDM_VERSION "$iddm_version"
  write_env_value ZOOKEEPER_BASE_VERSION "$base_version"

  echo "Updated $ENV_FILE:"
  echo "  IDDM_VERSION=$iddm_version"
  echo "  ZOOKEEPER_BASE_VERSION=$base_version"
  echo "Now apply the upgrade with ./run.sh stop, ./run.sh build-iddm, then ./run.sh start."
}

execute
