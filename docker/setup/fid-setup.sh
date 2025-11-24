#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "fid-setup.sh: Error occurred at line $LINENO, aborting"; exit 1' ERR

FID_ADMIN_HOST=fid
FID_ADMIN_PORT=9101
INPUT_DIR=/input
FID_GIT_DIR_PATH=/fid-git
FID_GIT_CONFIG_DIR_PATH="$FID_GIT_DIR_PATH/config"
INPUT_PROMOTION_GIT_FILE="$INPUT_DIR/iddm-promotion-git.sh"
INPUT_PROMOTION_ZIP_FILE="$INPUT_DIR/iddm-promotion.zip"
DATASOURCE_FILENAME_REGEX=^\/input\/iddm-promotion-datasource-\(.+\)\.sh\$

wait_for_fid() {
  for ((i=1; i<=100; i++)); do
    echo "Waiting for FID to be ready..."
    local result
    set +e
    nc -w 1 "$FID_ADMIN_HOST" "$FID_ADMIN_PORT"
    result=$?
    set -e

    if [ "$result" -eq 0 ]; then
      return 0
    fi
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
  fid_admin_base_url="https://$FID_ADMIN_HOST:$FID_ADMIN_PORT/v8/admin"

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
  ds_name="$1"

  echo "Configuring Database datasource"

  local uri_encoded_name
  uri_encoded_name=$(echo -n "$homedepot_central_name" | jq -sRr @uri)

  local data_source
  data_source=$(execute_admin_request \
    "/data_sources/$uri_encoded_name")

  data_source=$(echo -n "$data_source" | jq --arg jdbc_url "$JDBC_URL" '.url = $jdbc_url')
  data_source=$(echo -n "$data_source" | jq --arg username "USERNAME" '.username = $username')
  data_source=$(echo -n "$data_source" | jq --arg password "$PASSWORD" '.password = $password')

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
  ds_name="$1"

  echo "Configuring LDAP datasource"

  local uri_encoded_name
  uri_encoded_name=$(echo -n "$homedepot_central_name" | jq -sRr @uri)

  local data_source
  data_source=$(execute_admin_request \
    "/data_sources/$uri_encoded_name")

  data_source=$(echo -n "$data_source" | jq --arg host "$HOST" '.host = $host')
  data_source=$(echo -n "$data_source" | jq --arg port "$PORT" '.port = $port')
  data_source=$(echo -n "$data_source" | jq --arg tls "$IS_SSL" '.ssl = $tls')
  data_source=$(echo -n "$data_source" | jq --arg user "$BIND_DN" '.bindDn = $user')
  data_source=$(echo -n "$data_source" | jq --arg password "$BIND_PASSWORD" '.password = $password')

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
    if [[ ! "$file" =~ $DATASOURCE_FILENAME_REGEX  ]]; then
      echo "$file does not match regex $DATASOURCE_FILENAME_REGEX" >&2
      exit 1
    fi

    local ds_name
    ds_name="${BASH_REMATCH[1]}"
    (
      . "$file"
      case "$CATEGORY" in
        ldap) execute_ldap_datasource_update "$ds_name" ;;
        database) execute_database_datasource_update "$ds_name" ;;
        *)
          echo "Invalid category: $CATEGORY" >&2
          exit 1
        ;;
      esac
    )
  done
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

  local cert_files
  mapfile -t cert_files < <(find "$INPUT_DIR" -maxdepth 1 -name '*.pem')
  if [ "${#cert_files[@]}" -gt 0 ]; then
    execute_cert_import "${cert_files[@]}"
  fi

  if [ "$promotion_needed" == "true" ]; then
    execute_promotion_import
  fi

  local ds_files
  mapfile -t ds_files < <(find "$INPUT_DIR" -maxdepth 1 -name 'iddm-promotion-datasource-*.sh')
  if [ "${#ds_files[@]}" -gt 0 ]; then
    execute_datasource_update "${ds_files[@]}"
  fi
}

echo "Running Home Depot RadiantLogic IDDM Lite setup"
wait_for_fid
find_and_execute_operations
echo "Home Depot RadiantLogic IDDM Lite setup complete"