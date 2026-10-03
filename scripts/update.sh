#!/usr/bin/env bash
# Fuerza la actualización ahora, sin esperar al chequeo automático (cada 5 min).
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only || echo "No se pudo actualizar la carpeta con git; se sigue con las imágenes."
# Un .env de antes de la imagen de planta apunta al backend completo de la nube.
sed -i 's|^SERVILION_IMAGE=ghcr.io/howlonely/servilion-backend:|SERVILION_IMAGE=ghcr.io/howlonely/servilion-edge:|' .env
docker compose pull
docker compose up -d
docker image prune -f
