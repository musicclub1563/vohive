#!/bin/sh
# Container entrypoint.
#
# VoHive exits immediately when its YAML config is missing, and a freshly created
# container has an empty /app/config. Seed the file from the shipped example on
# first start so `docker run` / `docker compose up` works without manual setup.
set -eu

CONFIG_PATH="${CONFIG_PATH:-/app/config/config.yaml}"
CONFIG_DIR="$(dirname "$CONFIG_PATH")"

mkdir -p "$CONFIG_DIR" /app/data /app/logs

if [ ! -f "$CONFIG_PATH" ]; then
  if [ -f /app/config/config.example.yaml ]; then
    echo "vohive: $CONFIG_PATH not found, seeding from config.example.yaml" >&2
    cat /app/config/config.example.yaml > "$CONFIG_PATH"
  else
    echo "vohive: $CONFIG_PATH not found and no example config available" >&2
    exit 1
  fi
fi

exec /app/vohive "$@"
