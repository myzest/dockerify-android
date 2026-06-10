#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 127
  fi
}

preflight_docker() {
  require_command docker

  if ! docker compose version >/dev/null 2>&1; then
    echo "Error: Docker Compose v2 is required. Install/update Docker Desktop or the docker compose plugin." >&2
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    cat >&2 <<MSG
Error: Docker daemon is not running or is not reachable.

Start Docker Desktop/daemon, then run this script again:
  ./scripts/start-rootavd.sh
MSG
    exit 1
  fi
}

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dockerify-android-rootavd}"
export ANDROID_CONTAINER_NAME="${ANDROID_CONTAINER_NAME:-dockerify-android-rootavd}"
export SCRCPY_CONTAINER_NAME="${SCRCPY_CONTAINER_NAME:-scrcpy-web-rootavd}"
export DATA_DIR="${DATA_DIR:-./data/rootavd}"
export ADB_PORT="${ADB_PORT:-5556}"
export WEB_PORT="${WEB_PORT:-8001}"
export ROOT_SETUP=1
export GAPPS_SETUP="${GAPPS_SETUP:-0}"
export ARM_TRANSLATION="${ARM_TRANSLATION:-1}"
export DEVICE_PROFILE="${DEVICE_PROFILE:-pixel_5_android_11}"

preflight_docker

mkdir -p "$DATA_DIR" ./extras

docker compose up -d --build

cat <<MSG

[rootAVD] started
  Web: http://localhost:${WEB_PORT}
  ADB: adb connect localhost:${ADB_PORT}
  Logs: docker logs -f ${ANDROID_CONTAINER_NAME}
  Stop: COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME} ANDROID_CONTAINER_NAME=${ANDROID_CONTAINER_NAME} SCRCPY_CONTAINER_NAME=${SCRCPY_CONTAINER_NAME} DATA_DIR=${DATA_DIR} ADB_PORT=${ADB_PORT} WEB_PORT=${WEB_PORT} docker compose down
MSG
