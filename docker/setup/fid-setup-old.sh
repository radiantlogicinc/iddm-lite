#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "fid-setup.sh: Error occurred at line $LINENO, aborting"; exit 1' ERR

RDN_REGEX="^(.+)=(.+)$"

INPUT_DIR_PATH="/input"
CONFIG_ZIP_PATH="$INPUT_DIR_PATH/config.zip"
PROPS_PATH="$INPUT_DIR_PATH/setup.env"
FID_GIT_DIR_PATH=/fid-git
FID_GIT_CONFIG_DIR_PATH="$FID_GIT_DIR_PATH/config"

ensure_variable_exists() {
  local name
  name="$1"

  if ! declare -p "$name" &> /dev/null; then
    echo "Cannot find variable $name, property parsing had critical failure" >&2
    exit 1
  fi
}

validate_configuration() {
  echo "Validating configuration for FID setup"
  if [ ! -d "$INPUT_DIR_PATH" ]; then
    echo "Missing $INPUT_DIR_PATH, volumes are not setup correctly" >&2
    exit 1
  fi

  if [ ! -d "$FID_GIT_DIR_PATH" ]; then
    echo "Missing $FID_GIT_DIR_PATH, volumes are not setup correctly" >&2
    exit 1
  fi

  if [ ! -f "$PROPS_PATH" ]; then
    echo "Missing $PROPS_PATH, cannot configure setup script" >&2
    exit 1
  fi

  if [ ! -f "$CONFIG_ZIP_PATH" ]; then
    echo "Missing $CONFIG_ZIP_PATH, cannot configure FID" >&2
    exit 1
  fi

  # path for shellcheck is from root of project, not relative to file
  # shellcheck source=./input/setup.env
  source "$PROPS_PATH"

  ensure_variable_exists fid_admin_host
  ensure_variable_exists fid_admin_port
  ensure_variable_exists fid_admin_tls
  ensure_variable_exists fid_admin_api_key
  ensure_variable_exists homedepot_store_base_dn
  ensure_variable_exists homedepot_store_staging_rdn
  ensure_variable_exists homedepot_store_actual_rdn
  ensure_variable_exists homedepot_central_host
  ensure_variable_exists homedepot_central_port
  ensure_variable_exists homedepot_central_tls
  ensure_variable_exists homedepot_central_bind_dn
  ensure_variable_exists homedepot_central_bind_password
  ensure_variable_exists homedepot_central_name
}

unpack_data() {
  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  echo "Unpacking data archive to $FID_GIT_CONFIG_DIR_PATH"
  unzip -q "$CONFIG_ZIP_PATH" -d "$FID_GIT_CONFIG_DIR_PATH"
}

# This does not touch .dvx content because some of the replacement expressions may not be as safe for other file types
find_and_replace_rdn() {
  local existing replacement
  existing="$1"
  replacement="$2"

  find "$FID_GIT_CONFIG_DIR_PATH" \
    -type f \
    \( -not -name '*.jar' -o -not -name '*.dvx' \) \
    -print0 | \
    xargs -0 -I {} sed -i "s/$existing/$replacement/g" {}

  while read -r file; do
    local transformed_file
    transformed_file="${file//"$existing"/"$replacement"}"

    if [ "$file" != "$transformed_file" ]; then
      local dir
      dir="$(dirname "$transformed_file")"
      if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
      fi
      mv "$file" "$transformed_file"
    fi
  done < <(find "$FID_GIT_CONFIG_DIR_PATH" -type f -not -name '*.jar')
}

replace_rdn_in_dvx() {
  local actual_rdn_key actual_rdn_value staging_rdn_key staging_rdn_value
  file="$1"
  staging_rdn_key="$2"
  staging_rdn_value="$3"
  actual_rdn_key="$4"
  actual_rdn_value="$5"

  # Each of the find/replace operations are done sequentially, so each one needs to reflect the changes from the prior one in its xpath
  xmlstarlet ed -L \
    -u "//Node[@Name = \"$staging_rdn_key\" and @Definition = \"$staging_rdn_value\"]/@Name" -v "$actual_rdn_key" \
    -u "//Node[@Name = \"$actual_rdn_key\" and @Definition = \"$staging_rdn_value\"]/@Definition" -v "$actual_rdn_value" \
    -u "//Node[@Name = \"$actual_rdn_key\" and @Definition = \"$actual_rdn_value\"]/@TypeName" -v "${actual_rdn_key}[$actual_rdn_value]" \
    "$file"
}

# .dvx content cannot be safely modified by simple sed expressions.
find_and_replace_rdn_in_dvx() {
  local actual_rdn_key actual_rdn_value staging_rdn_key staging_rdn_value
  staging_rdn_key="$1"
  staging_rdn_value="$2"
  actual_rdn_key="$3"
  actual_rdn_value="$4"

  # shellcheck disable=SC2016
  (
    export -f replace_rdn_in_dvx
    find "$FID_GIT_CONFIG_DIR_PATH" \
      -type f \
      -name '*.dvx' \
      -print0 | \
      xargs -0 -I {} bash -c 'replace_rdn_in_dvx "$1" "$2" "$3" "$4" "$5"' _ "{}" "$staging_rdn_key" "$staging_rdn_value" "$actual_rdn_key" "$actual_rdn_value"
  )
}

generate_mapping_hash() {
  local pipeline_id
  pipeline_id="$1"

  local binary_digest
  binary_digest=$(echo -n "$pipeline_id" | openssl dgst -sha256 -binary)

  # TODO why is the xxd not existing not failing the script?
  # TODO also add xxd to the docker image
  local hex_string
  hex_string=$(echo -n "$binary_digest" | xxd -p | tr -d '\n')

  if [ "${#hex_string}" -lt 64 ]; then
    # This is in the original ROS code to correct against a length risk
    hex_string="0${hex_string}"
  fi

  echo "${hex_string:0:16}"
}

fix_mapping_hashes() {
  local normalized_actual_rdn normalized_staging_rdn
  normalized_staging_rdn="$1"
  normalized_actual_rdn="$2"

  local report_file
  report_file="$FID_GIT_CONFIG_DIR_PATH/report.json"
  if [ ! -f "$report_file" ]; then
    echo "Cannot find report.json in config data, aborting" >&2
    exit 1
  fi

  local mapping_resources
  readarray -t mapping_resources = < <(jq -r '.resources | keys[] | select(startswith("mappings"))' "$report_file")

  for resource in "${mapping_resources[@]}"; do
    local pipeline_id new_pipeline_id hash new_hash

    pipeline_id="${resource#mappings_}"
    hash="$(generate_mapping_hash "$pipeline_id")"

    new_pipeline_id="${pipeline_id//$normalized_staging_rdn/$normalized_actual_rdn}"
    new_hash="$(generate_mapping_hash "$new_pipeline_id")"

    mv "$FID_GIT_CONFIG_DIR_PATH/file/vds_server/conf/sync/mappings/$hash" \
      "$FID_GIT_CONFIG_DIR_PATH/file/vds_server/conf/sync/mappings/$new_hash"

    sed -i "s/mappings\/$hash\/mappings\.json/mappings\/$new_hash\/mappings.json/g" "$report_file"
  done
}

apply_rdn_regex() {
  local rdn
  rdn="$1"

  if [[ ! "$rdn" =~ $RDN_REGEX ]]; then
    echo "Invalid RDN: $rdn" >&2
    exit 1
  fi
}

get_rdn_key() {
  local rdn
  rdn="$1"

  apply_rdn_regex "$rdn"
  echo "${BASH_REMATCH[1]}"
}

get_rdn_value() {
  local rdn
  rdn="$1"

  apply_rdn_regex "$rdn"
  echo "${BASH_REMATCH[2]}"
}

normalize_rdn() {
  local rdn
  rdn="$1"

  echo "${rdn//[=,-]/_}"
}

fix_store_rdns() {
  local actual_rdn_key actual_rdn_value staging_rdn_key staging_rdn_value
  actual_rdn_key="$(get_rdn_key "$homedepot_store_actual_rdn")"
  actual_rdn_value="$(get_rdn_value "$homedepot_store_actual_rdn")"
  staging_rdn_key="$(get_rdn_key "$homedepot_store_staging_rdn")"
  staging_rdn_value="$(get_rdn_value "$homedepot_store_staging_rdn")"

  local normalized_actual_rdn normalized_staging_rdn
  normalized_actual_rdn="$(normalize_rdn "$homedepot_store_actual_rdn")"
  normalized_staging_rdn="$(normalize_rdn "$homedepot_store_staging_rdn")"

  echo "Transforming RDN references across all files from staging template $homedepot_store_staging_rdn to store-specific $homedepot_store_actual_rdn"

  fix_mapping_hashes "$normalized_staging_rdn" "$normalized_actual_rdn"
  find_and_replace_rdn "$normalized_staging_rdn" "$normalized_actual_rdn"
  find_and_replace_rdn "$homedepot_store_staging_rdn" "$homedepot_store_actual_rdn"
  find_and_replace_rdn_in_dvx "$staging_rdn_key" "$staging_rdn_value" "$actual_rdn_key" "$actual_rdn_value"
}

fix_report_change_status() {
  echo "Setting report.json change status for all resources to ADDED"

  sed -i 's/"changeStatus" : null,/"changeStatus" : "ADDED",/g' \
    "$FID_GIT_CONFIG_DIR_PATH/report.json"
}

get_fid_admin_base_url() {
  local protocol
  if [ "$fid_admin_tls" == "true" ]; then
    protocol="https"
  else
    protocol="http"
  fi
  echo "${protocol}://$fid_admin_host:$fid_admin_port/v8/admin"
}

# The first argument is the URI to be appended to the FID admin base url
# All other arguments are passed directly to curl
execute_admin_request() {
  local uri
  uri="$1"
  shift 1

  local fid_admin_base_url
  fid_admin_base_url="$(get_fid_admin_base_url)"

  curl -sSk --fail-with-body -w "\n%{http_code}" \
    -H "x-api-key: $fid_admin_api_key" \
    "$@" \
    "${fid_admin_base_url}${uri}" > .response_temp 2>&1 \
    || true

  status_code=$(tail -n1 < .response_temp)
  response_body=$(sed '$d' < .response_temp)
  rm .response_temp

  if [[ ! "$status_code" =~ ^[0-9]+$ ]] || [ "$status_code" -ge 400 ] || [[ "$status_code" =~ ^0+$ ]]; then
    echo "Operation failed with HTTP status code '$status_code', please inspect the following response output and try again" >&2
    echo "$response_body" >&2
    exit 1
  fi

  echo "$response_body"
}

import_certificates() {
  echo "Importing certificates if necessary"

  local existing_certs
  existing_certs=$(execute_admin_request \
    /config/security/client_certificate_truststore)

  local cert_files
  readarray -t cert_files = < <(find "$INPUT_DIR_PATH" -type f -name '*.pem')
  for cert_file in "${cert_files[@]}"; do
    local base_name exists
    base_name=$(basename -s .pem "$cert_file")
    exists=$(jq --arg name "$base_name" '. | index($name)' <<< "$existing_certs")
    if [ "$exists" != null ]; then
      echo "Certificate already exists: $cert_file"
      continue
    fi

    echo "Importing certificate $cert_file"

    execute_admin_request \
      "/config/security/client_certificate_truststore?alias=$base_name" \
      -X POST \
      -F "file=@${cert_file};name=$base_name" \
      1>/dev/null

    echo "Import certificate successful"
  done
}

configure_datasource() {
  echo "Configuring proxy datasource to central LDAP"

  local uri_encoded_name
  uri_encoded_name=$(echo -n "$homedepot_central_name" | jq -sRr @uri)

  local data_source
  data_source=$(execute_admin_request \
    "/data_sources/$uri_encoded_name")

  data_source=$(echo -n "$data_source" | jq --arg host "$homedepot_central_host" '.host = $host')
  data_source=$(echo -n "$data_source" | jq --arg port "$homedepot_central_port" '.port = $port')
  data_source=$(echo -n "$data_source" | jq --arg tls "$homedepot_central_tls" '.ssl = $tls')
  data_source=$(echo -n "$data_source" | jq --arg user "$homedepot_central_bind_dn" '.bindDn = $user')
  data_source=$(echo -n "$data_source" | jq --arg password "$homedepot_central_bind_password" '.password = $password')

  execute_admin_request \
    "/data_sources/$uri_encoded_name" \
    -X PUT \
    -H 'Content-Type: application/json' \
    -d "$data_source" \
    1>/dev/null

  echo "Datasource configured successfully"
}

import_configuration_data() {
  echo "Importing configuration data into FID"

  local resources request
  resources=$(jq '.resources' "$FID_GIT_CONFIG_DIR_PATH/report.json")
  request=$(cat <<EOF
{
  "apply": true,
  "resources": $resources,
  "placeholders": {}
}
EOF
)

  execute_admin_request \
    "/configuration_promotion/resources/import/git" \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "$request" \
    1>/dev/null

  echo "Import configuration was successful"
}

wait_for_fid() {
  for ((i=1; i<=100; i++)); do
    echo "Waiting for FID to be ready..."
    local result
    set +e
    nc -w 1 "$fid_admin_host" "$fid_admin_port"
    result=$?
    set -e

    if [ "$result" -eq 0 ]; then
      return 0
    fi
  done

  echo "Timed out before FID became ready" >&2
  exit 1
}

echo "Running Home Depot RadiantLogic Identity Data Management FID setup script"
validate_configuration
unpack_data
fix_store_rdns
fix_report_change_status
wait_for_fid
import_certificates
import_configuration_data
configure_datasource
echo "Home Depot RadiantLogic Identity Data Management FID setup complete"
