#!/usr/bin/env bash

set -euo pipefail

ENV_FILE_ARGS=(--env-file .env --env-file .env-server)

check_for_env_files() {
  if [ ! -f .env-server ]; then
    echo "Missing .env-server file with server-specific environment variables" >&2
    exit 1
  fi
}

USAGE="Must specify command: start, stop, setup [--debug], build-iddm, or build-setup"

get_command() {
  if [ $# -eq 1 ]; then
    echo "$1"
  elif [ $# -eq 2 ] && [ "$1" = "setup" ] && [ "$2" = "--debug" ]; then
    echo "$1"
  else
    echo "$USAGE" >&2
    exit 1
  fi
}

start() {
  echo "Starting Radiant Logic IDDM-Lite application"

  docker compose \
    --profile fid \
    "${ENV_FILE_ARGS[@]}" \
    up -d
}

stop() {
  echo "Stopping Radiant Logic IDDM-Lite application"

  docker compose \
    "${ENV_FILE_ARGS[@]}" \
    --profile fid \
    stop
}

compose_up_setup() {
  docker compose \
    "${ENV_FILE_ARGS[@]}" \
    --profile setup \
    up \
    --menu=false
}

setup() {
  echo "Running Radiant Logic IDDM-Lite setup"

  compose_up_setup
}

setup_debug() {
  echo "Running Radiant Logic IDDM-Lite setup with debug logging"

  SETUP_DEBUG=true compose_up_setup
}

build() {
  local profile
  profile="$1"
  echo "(Re-)Building Radiant Logic IDDM-Lite images"

  docker compose \
    "${ENV_FILE_ARGS[@]}" \
    --profile "$profile" \
    build
}

check_for_env_files
command="$(get_command "$@")"

case "$command" in
  start) start ;;
  stop) stop ;;
  setup) if [ $# -eq 2 ]; then setup_debug; else setup; fi ;;
  build-iddm) build fid ;;
  build-setup) build setup ;;
  *)
    echo "Invalid command: $command" >&2
    exit 1
  ;;
esac