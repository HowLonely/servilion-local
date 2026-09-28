#!/usr/bin/env bash
# Sigue los registros del backend y de la sincronización. Ctrl+C para salir.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -gt 0 ] || set -- api sync
docker compose logs -f --tail=100 "$@"
