#!/usr/bin/env bash
# Fuerza la actualización ahora, sin esperar al chequeo automático (cada 5 min).
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only || echo "No se pudo actualizar la carpeta con git; se sigue con las imágenes."
docker compose pull
docker compose up -d
docker image prune -f
