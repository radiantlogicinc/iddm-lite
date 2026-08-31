#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "fid-setup.sh: Error occurred at line $LINENO, aborting"; exit 1' ERR

FID_HOST=fid
FID_ADMIN_PORT=9101
FID_HEALTH_PORT=9100
INPUT_DIR=/input
FID_GIT_DIR_PATH=/fid-git
FID_GIT_CONFIG_DIR_PATH="$FID_GIT_DIR_PATH/config"
INPUT_PROMOTION_GIT_FILE="$INPUT_DIR/iddm-promotion-git.sh"
INPUT_PROMOTION_ZIP_FILE="$INPUT_DIR/iddm-promotion.zip"
RDN_REGEX="^(.+)=(.+)$"

# Probes FID's health endpoint, which answers `pong` once FID is ready to serve requests.
# The `|| return 1` keeps the probe out of reach of the ERR trap, which fires on a failed
# command regardless of errexit and would otherwise abort the script while FID is starting.
fid_is_ready() {
  local response
  response=$(curl -sf --connect-timeout 2 --max-time 5 \
    "http://$FID_HOST:$FID_HEALTH_PORT/ping" 2>/dev/null) || return 1

  [ "$response" = "pong" ]
}

wait_for_fid() {
  local i
  for ((i=1; i<=100; i++)); do
    echo "Waiting for FID to be ready..."

    if fid_is_ready; then
      return 0
    fi

    sleep 2
  done

  echo "Timed out before FID became ready" >&2
  exit 1
}

# The first argument is the URI to be appended to the FID admin base url
# All other arguments are passed directly to curl
execute_admin_request() {
  local uri
  uri="$1"
  shift 1

  local fid_admin_base_url
  fid_admin_base_url="https://$FID_HOST:$FID_ADMIN_PORT/v8/admin"

  curl -sSk --fail-with-body -w "\n%{http_code}" \
    -H "x-api-key: $FID_ADMIN_API_KEY" \
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

stage_promotion_from_git() {
  echo "Staging promotion data from git repo"

  if [ ! -f "$INPUT_PROMOTION_GIT_FILE" ]; then
    echo "Cannot find $INPUT_PROMOTION_GIT_FILE, aborting" >&2
    exit 1
  fi

  . "$INPUT_PROMOTION_GIT_FILE"

  if [ ! -d "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 ~/.ssh
  fi

  cat <<EOF > "$HOME/.ssh/config"
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  IdentityFile ~/.ssh/id_key
  IdentitiesOnly yes
EOF

  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  echo "$GIT_SSH_KEY_BASE64" | base64 -d > "$HOME/.ssh/id_key"
  chmod 600 ~/.ssh/id_key
  git clone "$GIT_REPO" "$FID_GIT_CONFIG_DIR_PATH"

  (
    cd "$FID_GIT_CONFIG_DIR_PATH"
    git checkout "$GIT_BRANCH"
  )

  echo "Promotion data staged successfully"
}

stage_promotion_from_zip() {
  echo "Staging promotion data from zip file"

  if [ ! -f "$INPUT_PROMOTION_ZIP_FILE" ]; then
    echo "Cannot find $INPUT_PROMOTION_ZIP_FILE, aborting" >&2
    exit 1
  fi

  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  unzip -q "$INPUT_PROMOTION_ZIP_FILE" -d "$FID_GIT_CONFIG_DIR_PATH"
  if [ ! -f "$FID_GIT_CONFIG_DIR_PATH/report.json" ] && [ -f "$FID_GIT_CONFIG_DIR_PATH"/*/report.json ]; then
    echo "Fixing output structure after unzip"
    mv "$FID_GIT_CONFIG_DIR_PATH"/*/* "$FID_GIT_CONFIG_DIR_PATH"
  fi

  if [ ! -f "$FID_GIT_CONFIG_DIR_PATH/report.json" ]; then
    echo "Promotion data is invalid, cannot proceed" >&2
    exit 1
  fi
  echo "Promotion data staged successfully"
}

execute_promotion_import() {
  echo "Executing promotion import"

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

  echo "Promotion import executed successfully"
}

execute_cert_import() {
  local cert_files
  cert_files=("$@")

  echo "Found certificates to import, importing them if they do not already exist"

  local existing_certs
  existing_certs=$(execute_admin_request \
    /config/security/client_certificate_truststore)

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

  echo "All certificates imported, if necessary"
}

execute_database_datasource_update() {
  local ds_name
  ds_name="$NAME"

  echo "Configuring Database datasource $ds_name"

  local uri_encoded_name
  uri_encoded_name=$(echo -n "$ds_name" | jq -sRr @uri)

  echo "Loading existing datasource data"

  local data_source
  data_source=$(execute_admin_request \
    "/data_sources/$uri_encoded_name")

  data_source=$(echo -n "$data_source" | jq --arg jdbc_url "$JDBC_URL" '.url = $jdbc_url')
  data_source=$(echo -n "$data_source" | jq --arg username "$USERNAME" '.username = $username')
  data_source=$(echo -n "$data_source" | jq --arg password "$PASSWORD" '.password = $password')

  echo "Updating datasource data"

  execute_admin_request \
    "/data_sources/$uri_encoded_name" \
    -X PUT \
    -H 'Content-Type: application/json' \
    -d "$data_source" \
    1>/dev/null

  echo "Datasource configured successfully"
}

execute_ldap_datasource_update() {
  local ds_name
  ds_name="$NAME"

  echo "Configuring LDAP datasource $ds_name"

  local uri_encoded_name
  uri_encoded_name=$(echo -n "$ds_name" | jq -sRr @uri)

  echo "Loading existing datasource data"

  local data_source
  data_source=$(execute_admin_request \
    "/data_sources/$uri_encoded_name")

  data_source=$(echo -n "$data_source" | jq --arg host "$HOST" '.host = $host')
  data_source=$(echo -n "$data_source" | jq --arg port "$PORT" '.port = $port')
  data_source=$(echo -n "$data_source" | jq --arg tls "$IS_SSL" '.ssl = $tls')
  data_source=$(echo -n "$data_source" | jq --arg user "$BIND_DN" '.bindDn = $user')
  data_source=$(echo -n "$data_source" | jq --arg password "$BIND_PASSWORD" '.password = $password')

  echo "Updating datasource data"

  execute_admin_request \
    "/data_sources/$uri_encoded_name" \
    -X PUT \
    -H 'Content-Type: application/json' \
    -d "$data_source" \
    1>/dev/null

  echo "Datasource configured successfully"
}

execute_datasource_update() {
  local ds_files
  ds_files=("$@")

  for file in "${ds_files[@]}"; do
    echo "Updating promotion datasource from $file"
    (
      . "$file"
      case "$CATEGORY" in
        ldap) execute_ldap_datasource_update ;;
        database) execute_database_datasource_update ;;
        *)
          echo "Invalid category: $CATEGORY" >&2
          exit 1
        ;;
      esac
    )
  done
}

fix_report_change_status() {
  echo "Setting report.json change status for all resources to ADDED prior to performing promotion import"

  sed -i 's/"changeStatus" : null,/"changeStatus" : "ADDED",/g' \
    "$FID_GIT_CONFIG_DIR_PATH/report.json"
}

find_and_execute_operations() {
  local promotion_needed
  promotion_needed=false

  if [ -f "$INPUT_PROMOTION_GIT_FILE" ] && [ -f "$INPUT_PROMOTION_ZIP_FILE" ]; then
    echo "Cannot configure both a git & zip promotion simultaneously" >&2
    exit 1
  fi

  if [ -f "$INPUT_PROMOTION_GIT_FILE" ]; then
    stage_promotion_from_git
    promotion_needed=true
  fi

  if [ -f "$INPUT_PROMOTION_ZIP_FILE" ]; then
    stage_promotion_from_zip
    promotion_needed=true
  fi

  local rename_files
  mapfile -t rename_files < <(find "$INPUT_DIR" -maxdepth 1 -name 'iddm-promotion-rename-*.sh')
  if [ "${#rename_files[@]}" -gt 0 ]; then
    execute_rename_rdns "${rename_files[@]}"
  fi

  local cert_files
  mapfile -t cert_files < <(find "$INPUT_DIR" -maxdepth 1 -name '*.pem')
  if [ "${#cert_files[@]}" -gt 0 ]; then
    execute_cert_import "${cert_files[@]}"
  fi

  if [ "$promotion_needed" == "true" ]; then
    fix_report_change_status
    execute_promotion_import
  fi

  local ds_files
  mapfile -t ds_files < <(find "$INPUT_DIR" -maxdepth 1 -name 'iddm-promotion-datasource-*.sh')
  if [ "${#ds_files[@]}" -gt 0 ]; then
    execute_datasource_update "${ds_files[@]}"
  fi
}

get_rdn_key() {
  local rdn
  rdn="$1"

  apply_rdn_regex "$rdn"
  echo "${BASH_REMATCH[1]}"
}

apply_rdn_regex() {
  local rdn
  rdn="$1"

  if [[ ! "$rdn" =~ $RDN_REGEX ]]; then
    echo "Invalid RDN: $rdn" >&2
    exit 1
  fi
}

get_rdn_value() {
  local rdn
  rdn="$1"

  apply_rdn_regex "$rdn"
  echo "${BASH_REMATCH[2]}"
}

generate_mapping_hash() {
  local pipeline_id
  pipeline_id="$1"

  local binary_digest
  binary_digest=$(echo -n "$pipeline_id" | openssl dgst -sha256 -binary)

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
  readarray -t mapping_resources < <(jq -r '.resources | keys[] | select(startswith("mappings"))' "$report_file")

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
  local file target_rdn_key target_rdn_value source_rdn_key source_rdn_value
  file="$1"
  source_rdn_key="$2"
  source_rdn_value="$3"
  target_rdn_key="$4"
  target_rdn_value="$5"

  # Each of the find/replace operations are done sequentially, so each one needs to reflect the changes from the prior one in its xpath
  xmlstarlet ed -L \
    -u "//Node[@Name = \"$source_rdn_key\" and @Definition = \"$source_rdn_value\"]/@Name" -v "$target_rdn_key" \
    -u "//Node[@Name = \"$target_rdn_key\" and @Definition = \"$source_rdn_value\"]/@Definition" -v "$target_rdn_value" \
    -u "//Node[@Name = \"$target_rdn_key\" and @Definition = \"$target_rdn_value\"]/@TypeName" -v "${target_rdn_key}[$target_rdn_value]" \
    "$file"
}

rename_rdn() {
  echo "Renaming RDN $SOURCE_RDN to $TARGET_RDN"

  local target_rdn_key target_rdn_value source_rdn_key source_rdn_value
  target_rdn_key="$(get_rdn_key "$TARGET_RDN")"
  target_rdn_value="$(get_rdn_value "$TARGET_RDN")"
  source_rdn_key="$(get_rdn_key "$SOURCE_RDN")"
  source_rdn_value="$(get_rdn_value "$SOURCE_RDN")"

  local normalized_target_rdn normalized_source_rdn
  normalized_target_rdn="$(normalize_rdn "$TARGET_RDN")"
  normalized_source_rdn="$(normalize_rdn "$SOURCE_RDN")"

  fix_mapping_hashes "$normalized_source_rdn" "$normalized_target_rdn"
  find_and_replace_rdn "$normalized_source_rdn" "$normalized_target_rdn"
  find_and_replace_rdn "$SOURCE_RDN" "$TARGET_RDN"
  find_and_replace_rdn_in_dvx "$source_rdn_key" "$source_rdn_value" "$target_rdn_key" "$target_rdn_value"
}

normalize_rdn() {
  local rdn
  rdn="$1"

  echo "${rdn//[=,-]/_}"
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

execute_rename_rdns() {
  local rename_files
  rename_files=("$@")

  echo "Found RDN rename files"

  for file in "${rename_files[@]}"; do
    echo "Performing RDN rename for $file"
    (
      . "$file"
      rename_rdn
    )
  done

  echo "RDN rename operations complete"
}

echo "Running Radiant Logic IDDM Lite setup"
wait_for_fid
find_and_execute_operations
echo "Radiant Logic IDDM Lite setup complete"