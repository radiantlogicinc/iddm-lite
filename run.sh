#!/usr/bin/env bash

set -euo pipefail

ENV_FILE_ARGS=(--env-file .env --env-file .env-server)

check_for_env_files() {
  if [ ! -f .env-server ]; then
    echo "Missing .env-server file with server-specific environment variables" >&2
    exit 1
  fi
}

USAGE="Must specify command: start, stop, setup [--debug], clean [--yes], build-iddm, or build-setup"

get_command() {
  if [ $# -eq 1 ]; then
    echo "$1"
  elif [ $# -eq 2 ] && [ "$1" = "setup" ] && [ "$2" = "--debug" ]; then
    echo "$1"
  elif [ $# -eq 2 ] && [ "$1" = "clean" ] && [ "$2" = "--yes" ]; then
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

# Prints the canonical, guarded IDDM_DATA_ROOT from .env-server. The file is read, not sourced, so nothing in it runs.
resolve_data_root() {
  local line
  local data_root
  local canonical_root
  local canonical_home

  line="$(grep '^IDDM_DATA_ROOT=' .env-server | tail -n 1 || true)"
  data_root="${line#IDDM_DATA_ROOT=}"

  if [[ "$data_root" =~ ^\"(.*)\"$ ]] || [[ "$data_root" =~ ^\'(.*)\'$ ]]; then
    data_root="${BASH_REMATCH[1]}"
  fi

  # Compose expands a leading ~ in bind-mount paths, so clean must target the same directories.
  if [ "$data_root" = "~" ]; then
    data_root="$HOME"
  elif [[ "$data_root" == "~/"* ]]; then
    data_root="$HOME/${data_root#"~/"}"
  fi

  if [ -z "$data_root" ]; then
    echo "IDDM_DATA_ROOT is empty or not set in .env-server, refusing to clean" >&2
    exit 1
  fi

  if [[ "$data_root" != /* ]]; then
    echo "IDDM_DATA_ROOT must be an absolute path, got: $data_root" >&2
    exit 1
  fi

  if [ ! -d "$data_root" ]; then
    echo "IDDM_DATA_ROOT is not an existing directory: $data_root" >&2
    exit 1
  fi

  canonical_root="$(cd "$data_root" && pwd -P)"
  canonical_home="$(cd "$HOME" && pwd -P)"

  if [ "$canonical_root" = "/" ] || [[ "$canonical_root" =~ ^/[^/]+$ ]]; then
    echo "IDDM_DATA_ROOT resolves to $canonical_root, which is too broad to clean" >&2
    exit 1
  fi

  if [ "$canonical_root" = "$canonical_home" ]; then
    echo "IDDM_DATA_ROOT resolves to the home directory, which is too broad to clean" >&2
    exit 1
  fi

  echo "$canonical_root"
}

# Runs a compose command across every IDDM-Lite service, so fid-setup is included alongside fid and zookeeper.
compose_all_profiles() {
  docker compose \
    "${ENV_FILE_ARGS[@]}" \
    --profile fid \
    --profile setup \
    "$@"
}

# Fails when any IDDM-Lite container is running, since clean would delete data out from under it.
check_containers_stopped() {
  local running_ids
  local running_services

  running_ids="$(compose_all_profiles ps --status running --quiet)"

  if [ -n "$running_ids" ]; then
    running_services="$(compose_all_profiles ps --status running --services | paste -sd ' ' -)"
    echo "Cannot clean while IDDM-Lite containers are running: $running_services. Run ./run.sh stop first." >&2
    exit 1
  fi
}

# Lists what clean will remove and exits without changes unless the user agrees or passed --yes.
confirm_clean() {
  local data_root
  local skip_prompt
  local answer
  data_root="$1"
  skip_prompt="$2"

  if [ "$skip_prompt" = "true" ]; then
    return 0
  fi

  echo "This will delete these directories:"
  echo "  $data_root/zookeeper"
  echo "  $data_root/fid"
  echo "  $data_root/git"
  echo "This will remove the containers: fid, zookeeper, fid-setup"
  echo "This will remove these images, if they exist:"
  compose_all_profiles config --images | sed 's/^/  /'

  answer=""
  read -r -p "Continue? [y/N] " answer || true
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "Clean cancelled, nothing was changed"
    exit 0
  fi
}

# Deletes the application data directories by name, leaving setup input and anything else under the root.
delete_application_data() {
  local data_root
  local name
  local target
  data_root="$1"

  for name in zookeeper fid git; do
    target="$data_root/$name"
    if [ ! -e "$target" ]; then
      continue
    fi

    echo "Deleting $target"
    if ! rm -rf "$target"; then
      echo "Could not delete $target" >&2
      echo "Delete the remaining files there manually, then run ./run.sh clean again" >&2
      exit 1
    fi
  done
}

# Removes the IDDM-Lite containers, network and locally built images, skipping images that are already gone.
remove_containers_and_images() {
  local image

  compose_all_profiles down

  while IFS= read -r image; do
    if docker image inspect "$image" > /dev/null 2>&1; then
      echo "Removing image $image"
      docker image rm "$image"
    fi
  done < <(compose_all_profiles config --images)
}

# Returns IDDM-Lite to a fresh install by removing its application data, containers and built images.
clean() {
  local skip_prompt
  local data_root
  skip_prompt="false"
  if [ $# -eq 1 ]; then
    skip_prompt="true"
  fi

  echo "Cleaning Radiant Logic IDDM-Lite application data"

  check_containers_stopped
  data_root="$(resolve_data_root)"
  confirm_clean "$data_root" "$skip_prompt"
  delete_application_data "$data_root"
  remove_containers_and_images

  echo "Clean complete."
}

check_for_env_files
command="$(get_command "$@")"

case "$command" in
  start) start ;;
  stop) stop ;;
  setup) if [ $# -eq 2 ]; then setup_debug; else setup; fi ;;
  clean) if [ $# -eq 2 ]; then clean --yes; else clean; fi ;;
  build-iddm) build fid ;;
  build-setup) build setup ;;
  *)
    echo "Invalid command: $command" >&2
    exit 1
  ;;
esac