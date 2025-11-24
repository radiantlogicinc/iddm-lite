#!/usr/bin/env bash

set -euo pipefail

ENV_FILE_ARGS=(--env-file .env --env-file .env-server)

check_for_env_files() {
  if [ ! -f .env-server ]; then
    echo "Missing .env-server file with server-specific environment variables" >&2
    exit 1
  fi
}

get_command() {
  if [ $# -ne 1 ]; then
    echo "Must specify command: start, stop, or setup" >&2
    exit 1
  fi

  echo "$1"
}

start() {
  echo "Starting RadiantLogic IDDM-Lite (FID & Zookeeper) application"

  docker compose \
    --profile fid \
    "${ENV_FILE_ARGS[@]}" \
    up -d
}

stop() {
  echo "Stopping RadiantLogic IDDM-Lite (FID & Zookeeper) application"

  docker compose \
    "${ENV_FILE_ARGS[@]}" \
    --profile fid \
    stop
}

setup() {
  echo "TBD"
}

check_for_env_files
command="$(get_command "$@")"

case "$command" in
  start) start ;;
  stop) stop ;;
  setup) setup ;;
esac