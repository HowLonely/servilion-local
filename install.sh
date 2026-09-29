#!/usr/bin/env bash
# Instala el servidor local de planta de Servilion en Ubuntu (22.04 o 24.04).
#
#   sudo ./install.sh
#
# Qué hace:
#   1. Instala Docker si no está.
#   2. Crea el .env con secretos nuevos y pide el token del nodo.
#   3. Baja las imágenes, levanta la base y el backend.
#   4. Baja de la nube la foto inicial (catálogo, usuarios y últimos 90 días).
#   5. Deja todo arrancando solo al encender el equipo y actualizándose solo.
#
# Se puede volver a correr sin miedo: no toca un .env existente ni borra datos.

set -euo pipefail

cd "$(dirname "$0")"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Corre este script con sudo: sudo ./install.sh"

# --- 1. Docker -----------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    bold "Instalando Docker..."
    apt-get update -y
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    # shellcheck disable=SC1091
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
systemctl enable --now docker >/dev/null

# Watchtower lee aquí las credenciales de ghcr.io; si la imagen es pública
# basta con un archivo vacío, pero tiene que existir.
mkdir -p /root/.docker
[ -f /root/.docker/config.json ] || echo '{}' > /root/.docker/config.json

# --- 2. Configuración -------------------------------------------------------
if [ ! -f .env ]; then
    bold "Creando la configuración (.env)..."
    cp .env.example .env
    secret() { head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
    sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$(secret)|" .env
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(secret)|" .env
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(secret | head -c 40)|" .env
fi

# Un .env de antes de la imagen de planta apunta al backend completo de la nube.
sed -i 's|^SERVILION_IMAGE=ghcr.io/howlonely/servilion-backend:|SERVILION_IMAGE=ghcr.io/howlonely/servilion-edge:|' .env

current_token=$(grep -E '^SYNC_NODE_TOKEN=' .env | cut -d= -f2- || true)
if [ -z "$current_token" ]; then
    echo
    echo "Falta el token con que este servidor se identifica ante la nube."
    echo "Se genera en el servidor de la nube con:"
    echo "    docker compose -f docker-compose.prod.yml exec api python manage.py sync_register_node antofagasta"
    read -r -p "Pega aquí el token (srvnode_...): " token
    [[ "$token" == srvnode_* ]] || fail "El token debe empezar con srvnode_"
    sed -i "s|^SYNC_NODE_TOKEN=.*|SYNC_NODE_TOKEN=${token}|" .env
fi
chmod 600 .env

# --- 3. Contenedores --------------------------------------------------------
bold "Bajando imágenes..."
if ! docker compose pull; then
    # La imagen de planta es privada. Las credenciales quedan en
    # /root/.docker/config.json, que es donde Watchtower las lee para actualizar.
    echo
    echo "No se pudo bajar la imagen de planta: es privada y hace falta un token de"
    echo "GitHub con permiso read:packages (ver README, «Acceso a la imagen»)."
    read -r -p "Usuario de GitHub: " gh_user
    read -r -s -p "Token: " gh_token
    echo
    echo "$gh_token" | DOCKER_CONFIG=/root/.docker docker login ghcr.io -u "$gh_user" --password-stdin \
        || fail "GitHub rechazó el usuario o el token."
    docker compose pull
fi

bold "Levantando base de datos y backend..."
docker compose up -d db api
echo -n "Esperando a que el backend migre y responda"
for _ in $(seq 1 90); do
    if [ "$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q api)" 2>/dev/null)" = "healthy" ]; then
        echo " listo."
        break
    fi
    echo -n "."
    sleep 2
done

# --- 4. Foto inicial --------------------------------------------------------
if docker compose exec -T api python manage.py shell -c \
    "from sync import edge; import sys; sys.exit(0 if edge.is_bootstrapped() else 1)" 2>/dev/null; then
    bold "El servidor ya tenía su foto inicial; no se vuelve a bajar."
else
    bold "Bajando desde la nube usuarios, catálogo y los últimos días de operación..."
    docker compose exec -T api python manage.py sync_bootstrap
fi

# --- 5. Resto de servicios ----------------------------------------------------
docker compose up -d

ip=$(hostname -I | awk '{print $1}')
port=$(grep -E '^API_PORT=' .env | cut -d= -f2-)
bold "Servidor local listo."
echo "En cada terminal, Ajustes → Servidor:  http://${ip}:${port:-8000}"
echo "Estado de la sincronización:          sudo ./scripts/status.sh"
