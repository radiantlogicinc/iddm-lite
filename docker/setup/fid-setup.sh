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

stage_promotion_from_git() {
  echo "Staging promotion data from git repo"

  . "$INPUT_PROMOTION_GIT_FILE"

  if [ ! -d "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh"
  fi

  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  echo "$GIT_SSH_KEY" | base64 -D > "$HOME/.ssh/id_key"
  git clone "$GIT_REPO" "$FID_GIT_CONFIG_DIR_PATH"

  (
    cd "$FID_GIT_CONFIG_DIR_PATH"
    git checkout "$GIT_BRANCH"
  )

  echo "Promotion data staged successfully"
}

stage_promotion_from_zip() {
  echo "Staging promotion data from zip file"

  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  unzip -q "$INPUT_PROMOTION_ZIP_FILE" -d "$FID_GIT_CONFIG_DIR_PATH"
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

  if [ "$promotion_needed" == "true" ]; then
    execute_promotion_import
  fi
}

echo "Running Home Depot RadiantLogic IDDM Lite setup"
wait_for_fid
find_and_execute_operations