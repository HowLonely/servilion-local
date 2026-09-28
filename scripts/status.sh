#!/usr/bin/env bash
# Muestra el estado de los contenedores y de la sincronización con la nube.
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose ps
echo
docker compose exec -T api python manage.py shell -c "
from sync import edge
s = edge.status()
print('Nube:                 ', s['cloud_url'])
print('Conectado a la nube:  ', 'sí' if s['online'] else 'NO')
print('Cambios por enviar:   ', s['pending_changes'])
print('Último envío:         ', s['last_push_at'] or '-')
print('Última recepción:     ', s['last_pull_at'] or '-')
print('Incidencias abiertas: ', s['open_issues'])
print('Último error:         ', s['last_error'] or '-')
"
