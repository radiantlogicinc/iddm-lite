#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "fid-setup.sh: Error occurred at line $LINENO, aborting"; exit 1' ERR

FID_ADMIN_HOST=fid
FID_ADMIN_PORT=9101
INPUT_DIR=/input
FID_GIT_DIR_PATH=/fid-git
FID_GIT_CONFIG_DIR_PATH="$FID_GIT_DIR_PATH/config"

promotion_needed=false

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
  local file
  file="$1"

  echo "Staging promotion data from git repo"

  . "$INPUT_DIR/$file"

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

  promotion_needed=true
}

stage_promotion_from_zip() {
  local file
  file="$1"

  echo "Staging promotion data from zip file"

  if [ -d "$FID_GIT_CONFIG_DIR_PATH" ]; then
    rm -rf "$FID_GIT_CONFIG_DIR_PATH"
  fi

  unzip -q "/input/$file" -d "$FID_GIT_CONFIG_DIR_PATH"
  promotion_needed=true
}

execute_promotion_import() {
  echo "Executing promotion import"
}

find_and_execute_operations() {
  find "$INPUT_DIR" -maxdepth 1 -mindepth 1 -name 'iddm-*' | while read -r file; do
    echo "Executing operation for $file"
    case "$file" in
      iddm-promotion-git.sh) stage_promotion_from_git "$file" ;;
      iddm-promotion.zip) stage_promotion_from_zip "$file" ;;
      *)
        echo "Unknown operation file: $file" >&2
        exit 1
      ;;
    esac
  done

  if [ "$promotion_needed" == "true" ]; then
    execute_promotion_import
  fi
}

echo "Running Home Depot RadiantLogic IDDM Lite setup"
wait_for_fid
find_and_execute_operations