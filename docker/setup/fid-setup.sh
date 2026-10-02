#!/usr/bin/env bash

set -Eeuo pipefail

SETUP_DEBUG="${SETUP_DEBUG:-false}"
# Exported so the bash -c child shells spawned through xargs resolve log_debug the same way.
export SETUP_DEBUG

# Every log line goes to stderr so functions that return values through stdout, which callers
# capture with $(...), are never polluted by log output.
log_info() { echo "[INFO] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
# The `|| true` keeps a disabled log_debug from returning non-zero under errexit and the ERR trap.
log_debug() { [ "$SETUP_DEBUG" = "true" ] && echo "[DEBUG] $*" >&2 || true; }

trap 'log_error "fid-setup.sh: Error occurred at line $LINENO, aborting"; exit 1' ERR

# Runs on every way out of the script, so the VDS Server log level is put back after a failure too.
# The ERR trap and errexit are disabled first so a failure inside the handler cannot recurse.
on_exit() {
  local exit_status
  exit_status="$1"
  trap - ERR
  set +e

  restore_vds_server_log_level || exit_status=1
  exit "$exit_status"
}
# The status is passed as an argument because declaring a local first would reset $?.
trap 'on_exit $?' EXIT
# As PID 1 bash ignores SIGTERM unless it is trapped; exiting from the handler runs the EXIT trap.
trap 'exit 143' TERM
trap 'exit 130' INT

FID_HOST=fid
FID_ADMIN_PORT=9101
FID_HEALTH_PORT=9100
FID_ADAP_PORT=8090
ADAP_STATUS_CODE=""
ADAP_RESPONSE_BODY=""
ADAP_TOKEN=""
INPUT_DIR=/input
FID_GIT_DIR_PATH=/fid-git
FID_GIT_CONFIG_DIR_PATH="$FID_GIT_DIR_PATH/config"
INPUT_PROMOTION_GIT_FILE="$INPUT_DIR/iddm-promotion-git.sh"
INPUT_PROMOTION_ZIP_FILE="$INPUT_DIR/iddm-promotion.zip"
RDN_REGEX="^(.+)=(.+)$"
VDS_LOG_CONFIG_PATH=zk:log4j2-vds.json
VDS_SERVER_LOG_LEVEL_KEY=server.log.level
VDS_SERVER_DEFAULT_LOG_LEVEL=WARN
VDS_SERVER_PRIOR_LOG_LEVEL=""
VDS_SERVER_DEBUG_ENABLED=false

# Probes FID's health endpoint, which answers `pong` once FID is ready to serve requests.
# The `|| return 1` keeps the probe out of reach of the ERR trap, which fires on a failed
# command regardless of errexit and would otherwise abort the script while FID is starting.
fid_is_ready() {
  local response
  log_debug "Polling FID health endpoint http://$FID_HOST:$FID_HEALTH_PORT/ping"
  response=$(curl -sf --connect-timeout 2 --max-time 5 \
    "http://$FID_HOST:$FID_HEALTH_PORT/ping" 2>/dev/null) || { log_debug "Health poll failed, FID is not answering yet"; return 1; }

  log_debug "Health poll response: $response"
  [ "$response" = "pong" ]
}

wait_for_fid() {
  local i
  for ((i=1; i<=100; i++)); do
    log_info "Waiting for FID to be ready..."
    log_debug "Health check attempt $i of 100"

    if fid_is_ready; then
      log_debug "FID is ready after $i attempt(s)"
      return 0
    fi

    sleep 2
  done

  log_error "Timed out before FID became ready"
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

  # Only the method is derived from the curl arguments; the arguments themselves can carry
  # credentials and request bodies, so they are never logged.
  local method arg prev
  method=""
  prev=""
  for arg in "$@"; do
    if [ "$prev" = "-X" ]; then
      method="$arg"
    elif [ -z "$method" ] && { [ "$arg" = "-d" ] || [ "$arg" = "-F" ]; }; then
      method="POST"
    fi
    prev="$arg"
  done
  method="${method:-GET}"

  log_debug "Admin call: $method ${fid_admin_base_url}${uri}"
  log_debug "Writing response to .response_temp"

  curl -sSk --fail-with-body -w "\n%{http_code}" \
    -H "x-api-key: $FID_ADMIN_API_KEY" \
    "$@" \
    "${fid_admin_base_url}${uri}" > .response_temp 2>&1 \
    || true

  status_code=$(tail -n1 < .response_temp)
  response_body=$(sed '$d' < .response_temp)
  rm .response_temp
  log_debug "Removed .response_temp"
  log_debug "Admin call HTTP status: $status_code"

  if [[ ! "$status_code" =~ ^[0-9]+$ ]] || [ "$status_code" -ge 400 ] || [[ "$status_code" =~ ^0+$ ]]; then
    log_error "Operation failed with HTTP status code '$status_code', please inspect the following response output and try again"
    log_error "$response_body"
    exit 1
  fi

  echo "$response_body"
}

# Binds to ADAP with the root credentials and keeps the token in ADAP_TOKEN, retrying while ADAP comes up.
# It returns 1 instead of exiting so the EXIT trap can call it; the token and response body are never logged.
# The first argument is the maximum number of attempts.
bind_adap() {
  local max_attempts i token
  max_attempts="$1"

  for ((i=1; i<=max_attempts; i++)); do
    log_debug "Binding to ADAP at https://$FID_HOST:$FID_ADAP_PORT/adap?bind=token, attempt $i of $max_attempts"

    curl -sSk -G -w "\n%{http_code}" \
      -u "$FID_ROOT_USERNAME:$FID_ROOT_PASSWORD" \
      --data-urlencode bind=token \
      "https://$FID_HOST:$FID_ADAP_PORT/adap" > .adap_response_temp 2>&1 \
      || true

    ADAP_STATUS_CODE=$(tail -n1 < .adap_response_temp)
    ADAP_RESPONSE_BODY=$(sed '$d' < .adap_response_temp)
    rm -f .adap_response_temp
    log_debug "ADAP bind response status: $ADAP_STATUS_CODE"

    if [[ "$ADAP_STATUS_CODE" =~ ^2[0-9][0-9]$ ]]; then
      # ADAP sends the token as JSON under a non-JSON content type, so the body is parsed regardless.
      token=$(echo "$ADAP_RESPONSE_BODY" | jq -r '.token // empty' 2>/dev/null) || token=""
      if [ -n "$token" ] && [ "$token" != "null" ]; then
        ADAP_TOKEN="$token"
        log_debug "ADAP bind succeeded"
        return 0
      fi
    fi

    if [ "$i" -lt "$max_attempts" ]; then
      sleep 2
    fi
  done

  log_error "Could not bind to ADAP (HTTP $ADAP_STATUS_CODE)"
  return 1
}

# Runs a vdsconfig command through ADAP, authenticating with the token from bind_adap. Prints the response
# body on stdout and returns 0 on HTTP 2xx, 1 otherwise. It never exits, so the EXIT trap can call it;
# callers decide what a failure means. The status and body of the last call are also left in ADAP_STATUS_CODE and
# ADAP_RESPONSE_BODY, because a caller that captures stdout runs this in a subshell and loses plain variables.
# The first argument is the command name, the rest are name=value parameters.
execute_vdsconfig_request() {
  local command_name
  command_name="$1"
  shift 1

  local -a param_args
  param_args=()
  local param
  for param in "$@"; do
    param_args+=(--data-urlencode "$param")
  done

  # Only the command and its parameters are logged; they are a path, a key and a value, never secrets.
  log_debug "GET https://$FID_HOST:$FID_ADAP_PORT/adap/util vdsconfig $command_name $*"

  curl -sSk -G -w "\n%{http_code}" \
    -H "Authorization: Token $ADAP_TOKEN" \
    --data-urlencode action=vdsconfig \
    --data-urlencode "commandname=$command_name" \
    --data-urlencode outputmode=json \
    "${param_args[@]}" \
    "https://$FID_HOST:$FID_ADAP_PORT/adap/util" > .adap_response_temp 2>&1 \
    || true

  ADAP_STATUS_CODE=$(tail -n1 < .adap_response_temp)
  ADAP_RESPONSE_BODY=$(sed '$d' < .adap_response_temp)
  rm -f .adap_response_temp
  log_debug "ADAP response status: $ADAP_STATUS_CODE"

  echo "$ADAP_RESPONSE_BODY"

  [[ "$ADAP_STATUS_CODE" =~ ^2[0-9][0-9]$ ]]
}

# Reads the current VDS Server log level into VDS_SERVER_PRIOR_LOG_LEVEL. A level that was never configured
# falls back to the default. A single attempt is enough because the ADAP bind has already waited for readiness.
read_vds_server_log_level() {
  local level error_message

  log_debug "Reading VDS Server log level"

  if execute_vdsconfig_request get-logging-property \
      "path=$VDS_LOG_CONFIG_PATH" "key=$VDS_SERVER_LOG_LEVEL_KEY" > /dev/null; then
    level=$(echo "$ADAP_RESPONSE_BODY" | jq -r '.data.value // empty' 2>/dev/null) || level=""
    if [ -n "$level" ] && [ "$level" != "null" ]; then
      VDS_SERVER_PRIOR_LOG_LEVEL="$level"
      return 0
    fi
  else
    error_message=$(echo "$ADAP_RESPONSE_BODY" | jq -r '.errorMessage // empty' 2>/dev/null) || error_message=""
    if [[ "$error_message" == *"could not find property"* ]]; then
      VDS_SERVER_PRIOR_LOG_LEVEL="$VDS_SERVER_DEFAULT_LOG_LEVEL"
      log_info "No VDS Server log level is configured, assuming $VDS_SERVER_DEFAULT_LOG_LEVEL"
      return 0
    fi
  fi

  log_error "Could not read the VDS Server log level through ADAP (HTTP $ADAP_STATUS_CODE)"
  exit 1
}

# Sets the VDS Server log level through ADAP, returning 1 on failure so callers decide whether it aborts.
set_vds_server_log_level() {
  local level
  level="$1"
  execute_vdsconfig_request set-logging-property \
    "path=$VDS_LOG_CONFIG_PATH" "key=$VDS_SERVER_LOG_LEVEL_KEY" "value=$level" > /dev/null
}

# Raises the VDS Server log level to DEBUG, remembering the prior level so it can be restored.
enable_vds_server_debug_logging() {
  read_vds_server_log_level

  if ! set_vds_server_log_level DEBUG; then
    log_error "Could not set the VDS Server log level to DEBUG through ADAP (HTTP $ADAP_STATUS_CODE)"
    exit 1
  fi

  VDS_SERVER_DEBUG_ENABLED=true
  log_info "VDS Server log level set to DEBUG (was $VDS_SERVER_PRIOR_LOG_LEVEL); it will be restored when setup ends"
}

# Puts the VDS Server log level back to the prior level. A no-op unless DEBUG was enabled, and the flag is
# cleared first so the main path and the EXIT trap never both restore.
restore_vds_server_log_level() {
  if [ "$VDS_SERVER_DEBUG_ENABLED" != "true" ]; then
    return 0
  fi
  VDS_SERVER_DEBUG_ENABLED=false

  if set_vds_server_log_level "$VDS_SERVER_PRIOR_LOG_LEVEL"; then
    log_info "VDS Server log level restored to $VDS_SERVER_PRIOR_LOG_LEVEL"
    return 0
  fi

  # A long setup can outlive the token, so a rejected token gets one fresh bind and one retry.
  # ADAP answers an expired or unknown token with HTTP 400 and errorCode 256 rather than 401.
  local error_code
  error_code=$(echo "$ADAP_RESPONSE_BODY" | jq -r '.errorCode // empty' 2>/dev/null) || error_code=""
  if [ "$ADAP_STATUS_CODE" = "401" ] || [ "$ADAP_STATUS_CODE" = "403" ] || [ "$error_code" = "256" ]; then
    log_debug "ADAP token rejected, binding again"
    if bind_adap 1 && set_vds_server_log_level "$VDS_SERVER_PRIOR_LOG_LEVEL"; then
      log_info "VDS Server log level restored to $VDS_SERVER_PRIOR_LOG_LEVEL"
      return 0
    fi
  fi

  log_error "Could not restore the VDS Server log level to $VDS_SERVER_PRIOR_LOG_LEVEL (HTTP $ADAP_STATUS_CODE)"
  log_error "Restore it manually with: docker exec fid /opt/radiantone/vds/bin/vdsconfig.sh set-logging-property -path $VDS_LOG_CONFIG_PATH -key $VDS_SERVER_LOG_LEVEL_KEY -value $VDS_SERVER_PRIOR_LOG_LEVEL"
  return 1
}

stage_promotion_from_git() {
  log_info "Staging promotion data from git repo"

  if [ ! -f "$INPUT_PROMOTION_GIT_FILE" ]; then
    log_error "Cannot find $INPUT_PROMOTION_GIT_FILE, aborting"
    exit 1
  fi

  log_debug "Sourcing control file $INPUT_PROMOTION_GIT_FILE"
  . "$INPUT_PROMOTION_GIT_FILE"

  if [ ! -d "$HOME/.ssh" ]; then
    log_debug "Creating $HOME/.ssh with permissions 700"
    mkdir -p "$HOME/.ssh"
    chmod 700 ~/.ssh
  fi

  log_debug "Writing $HOME/.ssh/config"
  cat <<EOF > "$HOME/.ssh/config"
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  IdentityFile ~/.ssh/id_key
  IdentitiesOnly yes
EOF

  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    log_debug "Removing $FID_GIT_CONFIG_DIR_PATH"
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  log_debug "Writing SSH key file $HOME/.ssh/id_key"
  echo "$GIT_SSH_KEY_BASE64" | base64 -d > "$HOME/.ssh/id_key"
  chmod 600 ~/.ssh/id_key
  log_debug "Cloning git repo into $FID_GIT_CONFIG_DIR_PATH"
  git clone "$GIT_REPO" "$FID_GIT_CONFIG_DIR_PATH"

  (
    cd "$FID_GIT_CONFIG_DIR_PATH"
    log_debug "Checking out branch $GIT_BRANCH"
    git checkout "$GIT_BRANCH"
  )

  log_info "Promotion data staged successfully"
}

stage_promotion_from_zip() {
  log_info "Staging promotion data from zip file"

  if [ ! -f "$INPUT_PROMOTION_ZIP_FILE" ]; then
    log_error "Cannot find $INPUT_PROMOTION_ZIP_FILE, aborting"
    exit 1
  fi

  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    log_debug "Removing $FID_GIT_CONFIG_DIR_PATH"
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  log_debug "Unzipping $INPUT_PROMOTION_ZIP_FILE into $FID_GIT_CONFIG_DIR_PATH"
  unzip -q "$INPUT_PROMOTION_ZIP_FILE" -d "$FID_GIT_CONFIG_DIR_PATH"
  if [ ! -f "$FID_GIT_CONFIG_DIR_PATH/report.json" ] && [ -f "$FID_GIT_CONFIG_DIR_PATH"/*/report.json ]; then
    log_info "Fixing output structure after unzip"
    log_debug "Flattening nested directory under $FID_GIT_CONFIG_DIR_PATH"
    mv "$FID_GIT_CONFIG_DIR_PATH"/*/* "$FID_GIT_CONFIG_DIR_PATH"
  fi

  log_debug "Checking for $FID_GIT_CONFIG_DIR_PATH/report.json"
  if [ ! -f "$FID_GIT_CONFIG_DIR_PATH/report.json" ]; then
    log_error "Promotion data is invalid, cannot proceed"
    exit 1
  fi
  log_info "Promotion data staged successfully"
}

execute_promotion_import() {
  log_info "Executing promotion import"

  local resources request
  log_debug "Extracting .resources from $FID_GIT_CONFIG_DIR_PATH/report.json"
  resources=$(jq '.resources' "$FID_GIT_CONFIG_DIR_PATH/report.json")
  log_debug "Building promotion import payload (body not logged)"
  request=$(cat <<EOF
{
  "apply": true,
  "resources": $resources,
  "placeholders": {}
}
EOF
)

  log_debug "Import URI: /configuration_promotion/resources/import/git"
  execute_admin_request \
    "/configuration_promotion/resources/import/git" \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "$request" \
    1>/dev/null

  log_info "Promotion import executed successfully"
}

execute_cert_import() {
  local cert_files
  cert_files=("$@")

  log_info "Found certificates to import, importing them if they do not already exist"

  local existing_certs
  log_debug "Fetching client certificate truststore"
  existing_certs=$(execute_admin_request \
    /config/security/client_certificate_truststore)

  for cert_file in "${cert_files[@]}"; do
    local base_name exists
    base_name=$(basename -s .pem "$cert_file")
    exists=$(jq --arg name "$base_name" '. | index($name)' <<< "$existing_certs")
    log_debug "Certificate file $cert_file, alias $base_name, existing index: $exists"
    if [ "$exists" != null ]; then
      log_info "Certificate already exists: $cert_file"
      log_debug "Skipping alias $base_name"
      continue
    fi

    log_info "Importing certificate $cert_file"
    log_debug "Importing alias $base_name from $cert_file"

    execute_admin_request \
      "/config/security/client_certificate_truststore?alias=$base_name" \
      -X POST \
      -F "file=@${cert_file};name=$base_name" \
      1>/dev/null

    log_info "Import certificate successful"
  done

  log_info "All certificates imported, if necessary"
}

execute_database_datasource_update() {
  local ds_name
  ds_name="$NAME"

  log_info "Configuring Database datasource $ds_name"

  local uri_encoded_name
  uri_encoded_name=$(echo -n "$ds_name" | jq -sRr @uri)
  log_debug "URI-encoded datasource name: $uri_encoded_name"

  log_info "Loading existing datasource data"

  local data_source
  log_debug "Fetching existing datasource"
  data_source=$(execute_admin_request \
    "/data_sources/$uri_encoded_name")

  log_debug "Updating fields: url, username, password"
  log_debug "Datasource username: $USERNAME"
  data_source=$(echo -n "$data_source" | jq --arg jdbc_url "$JDBC_URL" '.url = $jdbc_url')
  data_source=$(echo -n "$data_source" | jq --arg username "$USERNAME" '.username = $username')
  data_source=$(echo -n "$data_source" | jq --arg password "$PASSWORD" '.password = $password')

  log_info "Updating datasource data"

  execute_admin_request \
    "/data_sources/$uri_encoded_name" \
    -X PUT \
    -H 'Content-Type: application/json' \
    -d "$data_source" \
    1>/dev/null

  log_info "Datasource configured successfully"
}

execute_ldap_datasource_update() {
  local ds_name
  ds_name="$NAME"

  log_info "Configuring LDAP datasource $ds_name"

  local uri_encoded_name
  uri_encoded_name=$(echo -n "$ds_name" | jq -sRr @uri)
  log_debug "URI-encoded datasource name: $uri_encoded_name"

  log_info "Loading existing datasource data"

  local data_source
  log_debug "Fetching existing datasource"
  data_source=$(execute_admin_request \
    "/data_sources/$uri_encoded_name")

  log_debug "Updating fields: host, port, ssl, bindDn, password"
  log_debug "Datasource host=$HOST port=$PORT ssl=$IS_SSL bindDn=$BIND_DN"
  data_source=$(echo -n "$data_source" | jq --arg host "$HOST" '.host = $host')
  data_source=$(echo -n "$data_source" | jq --arg port "$PORT" '.port = $port')
  data_source=$(echo -n "$data_source" | jq --arg tls "$IS_SSL" '.ssl = $tls')
  data_source=$(echo -n "$data_source" | jq --arg user "$BIND_DN" '.bindDn = $user')
  data_source=$(echo -n "$data_source" | jq --arg password "$BIND_PASSWORD" '.password = $password')

  log_info "Updating datasource data"

  execute_admin_request \
    "/data_sources/$uri_encoded_name" \
    -X PUT \
    -H 'Content-Type: application/json' \
    -d "$data_source" \
    1>/dev/null

  log_info "Datasource configured successfully"
}

execute_datasource_update() {
  local ds_files
  ds_files=("$@")

  for file in "${ds_files[@]}"; do
    log_info "Updating promotion datasource from $file"
    (
      log_debug "Sourcing control file $file"
      . "$file"
      log_debug "Datasource category: $CATEGORY"
      case "$CATEGORY" in
        ldap) execute_ldap_datasource_update ;;
        database) execute_database_datasource_update ;;
        *)
          log_error "Invalid category: $CATEGORY"
          exit 1
        ;;
      esac
    )
  done
}

fix_report_change_status() {
  log_info "Setting report.json change status for all resources to ADDED prior to performing promotion import"

  log_debug "Running sed on $FID_GIT_CONFIG_DIR_PATH/report.json"
  sed -i 's/"changeStatus" : null,/"changeStatus" : "ADDED",/g' \
    "$FID_GIT_CONFIG_DIR_PATH/report.json"
}

find_and_execute_operations() {
  local promotion_needed
  promotion_needed=false

  if [ -f "$INPUT_PROMOTION_GIT_FILE" ] && [ -f "$INPUT_PROMOTION_ZIP_FILE" ]; then
    log_error "Cannot configure both a git & zip promotion simultaneously"
    exit 1
  fi

  if [ -f "$INPUT_PROMOTION_GIT_FILE" ]; then
    log_debug "Found git promotion control file $INPUT_PROMOTION_GIT_FILE"
    stage_promotion_from_git
    promotion_needed=true
  else
    log_debug "No git promotion control file, skipping git staging"
  fi

  if [ -f "$INPUT_PROMOTION_ZIP_FILE" ]; then
    log_debug "Found zip promotion file $INPUT_PROMOTION_ZIP_FILE"
    stage_promotion_from_zip
    promotion_needed=true
  else
    log_debug "No zip promotion file, skipping zip staging"
  fi

  local rename_files
  mapfile -t rename_files < <(find "$INPUT_DIR" -maxdepth 1 -name 'iddm-promotion-rename-*.sh')
  log_debug "Found ${#rename_files[@]} RDN rename file(s)"
  if [ "${#rename_files[@]}" -gt 0 ]; then
    execute_rename_rdns "${rename_files[@]}"
  else
    log_debug "Skipping RDN rename stage"
  fi

  local cert_files
  mapfile -t cert_files < <(find "$INPUT_DIR" -maxdepth 1 -name '*.pem')
  log_debug "Found ${#cert_files[@]} certificate file(s)"
  if [ "${#cert_files[@]}" -gt 0 ]; then
    execute_cert_import "${cert_files[@]}"
  else
    log_debug "Skipping certificate import stage"
  fi

  if [ "$promotion_needed" == "true" ]; then
    fix_report_change_status
    execute_promotion_import
  else
    log_debug "Skipping promotion import stage"
  fi

  local ds_files
  mapfile -t ds_files < <(find "$INPUT_DIR" -maxdepth 1 -name 'iddm-promotion-datasource-*.sh')
  log_debug "Found ${#ds_files[@]} datasource control file(s)"
  if [ "${#ds_files[@]}" -gt 0 ]; then
    execute_datasource_update "${ds_files[@]}"
  else
    log_debug "Skipping datasource update stage"
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
    log_error "Invalid RDN: $rdn"
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
    log_error "Cannot find report.json in config data, aborting"
    exit 1
  fi

  local mapping_resources
  readarray -t mapping_resources < <(jq -r '.resources | keys[] | select(startswith("mappings"))' "$report_file")
  log_debug "Found ${#mapping_resources[@]} mapping key(s): ${mapping_resources[*]}"

  for resource in "${mapping_resources[@]}"; do
    local pipeline_id new_pipeline_id hash new_hash

    pipeline_id="${resource#mappings_}"
    hash="$(generate_mapping_hash "$pipeline_id")"

    new_pipeline_id="${pipeline_id//$normalized_staging_rdn/$normalized_actual_rdn}"
    new_hash="$(generate_mapping_hash "$new_pipeline_id")"

    log_debug "Moving mapping $hash to $new_hash: $FID_GIT_CONFIG_DIR_PATH/file/vds_server/conf/sync/mappings/$hash -> $FID_GIT_CONFIG_DIR_PATH/file/vds_server/conf/sync/mappings/$new_hash"
    mv "$FID_GIT_CONFIG_DIR_PATH/file/vds_server/conf/sync/mappings/$hash" \
      "$FID_GIT_CONFIG_DIR_PATH/file/vds_server/conf/sync/mappings/$new_hash"

    log_debug "Rewriting hash $hash to $new_hash in $report_file"
    sed -i "s/mappings\/$hash\/mappings\.json/mappings\/$new_hash\/mappings.json/g" "$report_file"
  done
}

# This does not touch .dvx content because some of the replacement expressions may not be as safe for other file types
find_and_replace_rdn() {
  local existing replacement
  existing="$1"
  replacement="$2"

  log_debug "Replacing '$existing' with '$replacement'"
  log_debug "Replacing content in all files under $FID_GIT_CONFIG_DIR_PATH except .jar and .dvx"
  find "$FID_GIT_CONFIG_DIR_PATH" \
    -type f \
    -not -name '*.jar' -not -name '*.dvx' \
    -print0 | \
    xargs -0 -I {} sed -i "s/$existing/$replacement/g" {}

  while read -r file; do
    local transformed_file
    transformed_file="${file//"$existing"/"$replacement"}"

    if [ "$file" != "$transformed_file" ]; then
      log_debug "Renaming path $file -> $transformed_file"
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

  log_debug "Editing $file: Name '$source_rdn_key' -> '$target_rdn_key', Definition '$source_rdn_value' -> '$target_rdn_value'"

  # Each of the find/replace operations are done sequentially, so each one needs to reflect the changes from the prior one in its xpath
  xmlstarlet ed -L \
    -u "//Node[@Name = \"$source_rdn_key\" and @Definition = \"$source_rdn_value\"]/@Name" -v "$target_rdn_key" \
    -u "//Node[@Name = \"$target_rdn_key\" and @Definition = \"$source_rdn_value\"]/@Definition" -v "$target_rdn_value" \
    -u "//Node[@Name = \"$target_rdn_key\" and @Definition = \"$target_rdn_value\"]/@TypeName" -v "${target_rdn_key}[$target_rdn_value]" \
    "$file"
}

rename_rdn() {
  log_info "Renaming RDN $SOURCE_RDN to $TARGET_RDN"

  local target_rdn_key target_rdn_value source_rdn_key source_rdn_value
  target_rdn_key="$(get_rdn_key "$TARGET_RDN")"
  target_rdn_value="$(get_rdn_value "$TARGET_RDN")"
  source_rdn_key="$(get_rdn_key "$SOURCE_RDN")"
  source_rdn_value="$(get_rdn_value "$SOURCE_RDN")"

  local normalized_target_rdn normalized_source_rdn
  normalized_target_rdn="$(normalize_rdn "$TARGET_RDN")"
  normalized_source_rdn="$(normalize_rdn "$SOURCE_RDN")"

  log_debug "Source key='$source_rdn_key' value='$source_rdn_value', target key='$target_rdn_key' value='$target_rdn_value'"
  log_debug "Normalized source RDN '$normalized_source_rdn', normalized target RDN '$normalized_target_rdn'"

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
    export -f log_debug
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

  log_info "Found RDN rename files"

  for file in "${rename_files[@]}"; do
    log_info "Performing RDN rename for $file"
    (
      log_debug "Sourcing control file $file"
      . "$file"
      rename_rdn
    )
  done

  log_info "RDN rename operations complete"
}

parse_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --debug) SETUP_DEBUG=true ;;
      *)
        log_error "Unknown argument: $arg"
        exit 1
      ;;
    esac
  done
}

main() {
  parse_args "$@"

  log_info "Running Radiant Logic IDDM Lite setup"
  log_debug "Debug logging enabled"
  wait_for_fid
  if [ "$SETUP_DEBUG" = "true" ]; then
    bind_adap 10 || exit 1
    enable_vds_server_debug_logging
  fi
  find_and_execute_operations
  restore_vds_server_log_level || exit 1
  log_info "Radiant Logic IDDM Lite setup complete"
}

# Sourcing the script defines the functions without running setup.
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
