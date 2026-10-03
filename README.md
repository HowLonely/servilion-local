# 🏭 Servilion Local — servidor de planta

Servidor que corre en un PC dedicado de la planta de Antofagasta. Las terminales **Servilion Desktop** se conectan a él y no a internet, así la planta sigue trabajando aunque se corte la conexión.

```
 Terminales Servilion Desktop ──LAN──▶  Servidor local  ◀──internet──▶  api.servilion.cl
 (pesaje, digitalización,               (este repo)                     (nube: web + app móvil)
  empaque, despacho, hotelería)
```

- **Todo se guarda primero aquí.** Cada pesaje, guía o despacho queda en la base local en el momento. Un corte de luz justo después de digitalizar no pierde nada: la base confirma en disco antes de responderle a la terminal.
- **Se envía a la nube en segundos.** Si hay internet, cada cambio llega a `api.servilion.cl` en uno o dos segundos. Si no hay, espera en cola (una semana sin internet no es problema) y sale solo cuando vuelve la conexión.
- **Trae lo que se hace afuera.** Usuarios y catálogo editados en la web, y las recepciones y entregas de la app móvil, llegan cada pocos segundos.
- **Se actualiza solo.** Cuando se publica una versión nueva del backend en GitHub, este servidor la baja e instala sin que nadie haga nada.

Este repo contiene solo lo que se instala. El backend llega como imagen Docker de planta (`ghcr.io/howlonely/servilion-edge`), que **no es el backend de la nube**:

| Lleva | No lleva |
|---|---|
| Modelos y base de datos completos (el esquema es el mismo que en la nube, si no, no se puede sincronizar) | Reportería del panel web |
| La API de las terminales: pesaje, digitalización, empaque, despacho, hotelería, usuarios y catálogo | API de la app móvil de faena (entrega en habitación) |
| Pantalla TV | Lado nube de la sincronización (registro de servidores, feed, fotos iniciales) |
| Cliente de sincronización con la nube | Admin de Django, carga de datos legados, tests y documentación |

Además va **compilada**: trae bytecode de Python, no el código fuente. Se arma desde `servilion-backend` con `Dockerfile.edge` (ver `servilion-backend/sync/README.md`, «Imagen del servidor local»).

---

## 🚀 Instalación

Requisitos: un PC con **Ubuntu 22.04 o 24.04**, **IP fija** en la red de la planta e internet para la instalación.

### 1. Registrar el servidor en la nube (una vez)

En el servidor de la nube (EC2):

```bash
cd /home/ubuntu/servilion/backend
docker compose -f docker-compose.prod.yml --env-file .env.prod exec api python manage.py sync_register_node antofagasta
```

Imprime un token `srvnode_...`. **Guárdalo**: no se vuelve a mostrar. Si se pierde, correr el mismo comando otra vez genera uno nuevo e invalida el anterior.

### 2. Instalar en el PC de la planta

```bash
git clone https://github.com/HowLonely/servilion-local.git
cd servilion-local
sudo ./install.sh
```

El instalador instala Docker, genera las claves, pide el token del paso 1 (y el de GitHub para bajar la imagen, ver [Acceso a la imagen](#-acceso-a-la-imagen)), levanta todo y baja desde la nube:

- **completo:** usuarios, roles, clientes, empresas, prendas, precios, faenas, campamentos, habitaciones, trabajadores, correlativos y hotelería;
- **últimos 90 días:** guías y pesajes, más cualquier guía anterior que siga abierta.

Al terminar muestra la dirección que hay que poner en las terminales.

### 3. Apuntar las terminales

En cada terminal: **Ajustes (engranaje) → Servidor** → `http://<IP-del-servidor>:8000`.

Los usuarios y contraseñas son los mismos de siempre: vienen de la nube y funcionan aunque no haya internet.

---

## 🔄 Actualizaciones automáticas

| Qué | Cómo se actualiza |
|---|---|
| **Backend de este servidor** | Watchtower revisa cada 5 minutos si hay una imagen de planta nueva en `ghcr.io` (CI la publica junto con la de la nube al hacer merge a `main` en `servilion-backend`). Si la hay, la baja, migra la base y reinicia. |
| **Servilion Desktop** | Cada terminal revisa los releases de GitHub al arrancar, descarga la versión nueva y la instala al cerrar la app. Ver `servilion-desktop/README.md`. |

Para forzar la actualización ahora: `sudo ./scripts/update.sh`.

---

## 🔑 Acceso a la imagen

Las dos imágenes son **privadas** en GitHub Packages, y así tienen que quedar:

- `servilion-backend` es el backend completo de la nube, con su código fuente. **Nunca se hace pública ni se instala en la planta.**
- `servilion-edge` es la de este servidor. Privada también: solo la baja quien tenga un token.

El servidor de planta usa un token de GitHub de **solo lectura de paquetes**:

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → Generate new token, solo con el permiso `read:packages`. Idealmente desde una cuenta de GitHub creada para esto, sin acceso a los repos.
2. `install.sh` lo pide si no puede bajar la imagen. Para cambiarlo después:
   `echo <TOKEN> | sudo docker login ghcr.io -u <usuario-github> --password-stdin`

El token queda en `/root/.docker/config.json`, que es de donde Watchtower lo lee para las actualizaciones. Si se revoca, la planta sigue trabajando pero deja de actualizarse.

---

## 🛠 Operación diaria

| Comando | Para qué |
|---|---|
| `sudo ./scripts/status.sh` | ¿Está conectado a la nube? ¿Cuántos cambios faltan por enviar? |
| `sudo ./scripts/logs.sh` | Ver qué está pasando (Ctrl+C para salir) |
| `sudo ./scripts/update.sh` | Actualizar ya, sin esperar el chequeo automático |
| `sudo docker compose restart` | Reiniciar todo |

El servidor arranca solo al encender el PC. Las terminales muestran en su cabecera si el servidor local está conectado a la nube y cuántos cambios tiene pendientes.

### Sin internet

La planta trabaja igual: pesar, digitalizar, empacar, despachar, crear trabajadores, usuarios o clientes. Lo único que cambia:

- El **histórico de más de 90 días** no está disponible (con internet se consulta en la nube, sin que el operador lo note).
- Lo hecho en la web o en la app móvil durante el corte llega a la planta cuando vuelve la conexión.
- **Antes de que el morral llegue a faena, el servidor tiene que haber sincronizado**: la app móvil de faena busca las guías en la nube.

### Qué pasa si alguien edita lo mismo en la web y en la planta sin conexión

La sincronización lo resuelve sola, con la misma regla en los dos lados:

- **Misma ficha editada en los dos lados** (un trabajador, una empresa): gana la edición más reciente.
- **Mismo nombre creado en los dos lados** (el usuario "juan"): el de la planta queda como `juan~0042`. Un administrador puede renombrarlo después.
- **Una guía:** la planta manda en todo lo de planta, y la nube agrega las recepciones y entregas de faena. El estado nunca retrocede.

Cada uno de estos casos queda registrado como incidencia de sincronización para revisarlo.

---

## 🧯 Problemas comunes

**Las terminales dicen "Sin conexión"**
El problema es la red local o el servidor, no internet. Comprobar que el PC esté encendido, que tenga la IP de siempre y `sudo docker compose ps`.

**`status.sh` dice que no está conectado a la nube**
Revisar el internet del PC. Si hay internet y el error dice que la nube rechazó el token, se regeneró en la nube: pegar el nuevo en `SYNC_NODE_TOKEN` de `.env` y `sudo docker compose up -d`.

**Cambiar el PC del servidor**
Esperar a que `status.sh` muestre **0 cambios por enviar** (así todo quedó en la nube), apagar el PC viejo e instalar en el nuevo con el paso 2. Se puede reutilizar el token o generar uno nuevo. Los IDs nuevos siguen después de los del servidor anterior: no se repiten.

**Reinstalar desde cero**
`sudo docker compose down -v` borra la base local (lo que ya se envió está en la nube). Luego `sudo ./install.sh`.

---

## ⚙️ Configuración (`.env`)

| Variable | Qué es |
|---|---|
| `SYNC_CLOUD_URL` | Nube a la que se sincroniza (`https://api.servilion.cl`) |
| `SYNC_NODE_TOKEN` | Token del paso 1 |
| `API_PORT` | Puerto al que apuntan las terminales (8000) |
| `SYNC_LOCAL_RETENTION_DAYS` | Días de guías y pesajes que se guardan aquí (90) |
| `UPDATE_INTERVAL_SECONDS` | Cada cuánto se buscan actualizaciones (300) |
| `SECRET_KEY`, `JWT_SECRET`, `POSTGRES_PASSWORD` | Generados por el instalador; no se comparten |

Cómo funciona la sincronización por dentro: `servilion-backend/sync/README.md`.
