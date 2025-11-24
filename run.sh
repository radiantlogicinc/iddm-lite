#!/usr/bin/env bash

set -euo pipefail

get_command() {
  if [ $# -ne 1 ]; then
    echo "Must specify command: start, stop, or setup" >&2
    exit 1
  fi

  echo "$1"
}

start() {
  echo "TBD"
}

stop() {
  echo "TBD"
}

setup() {
  echo "TBD"
}

command="$(get_command "$@")"

case "$command" in
  start) start ;;
  stop) stop ;;
  setup) setup ;;
esac