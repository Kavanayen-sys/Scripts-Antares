#!/bin/bash

# SiGeRU - Inicio de la aplicación para XAMPP Linux

set -u

# Cambiar esta ruta si XAMPP está instalado en otro lugar.
XAMPP_DIR="${XAMPP_DIR:-/opt/lampp}"

PHP="$XAMPP_DIR/bin/php"
MYSQL="$XAMPP_DIR/bin/mysql"

# Directorio donde está este script.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Puertos utilizados por SiGeRU.
USER_API_PORT=8091
MANAGEMENT_API_PORT=8092
FRONTEND_PORT=8090

# Variables de base de datos.
export SIGERU_DB_HOST="${SIGERU_DB_HOST:-localhost}"
export SIGERU_DB_PORT="${SIGERU_DB_PORT:-3306}"
export SIGERU_DB_NAME="${SIGERU_DB_NAME:-sigeru}"
export SIGERU_DB_USER="${SIGERU_DB_USER:-root}"
export SIGERU_DB_PASSWORD="${SIGERU_DB_PASSWORD:-}"

# PIDs de los servidores.
PIDS=()

cleanup() {
    echo
    echo "Deteniendo servidores..."

    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
    done

    wait 2>/dev/null
    echo "SiGeRU detenido."
}

trap cleanup INT TERM EXIT

# Comprobar XAMPP/PHP.
if [[ ! -x "$PHP" ]]; then
    echo "ERROR: No se encontró PHP de XAMPP en:"
    echo "       $PHP"
    echo
    echo "Si XAMPP está instalado en otra ubicación:"
    echo "       XAMPP_DIR=/ruta/a/lampp ./run.sh"
    exit 1
fi

# Comprobar MySQL.
if [[ ! -x "$MYSQL" ]]; then
    echo "ERROR: No se encontró MySQL de XAMPP en:"
    echo "       $MYSQL"
    exit 1
fi

cd "$PROJECT_DIR" || exit 1

echo "========================================"
echo " SiGeRU - Primera entrega"
echo " XAMPP Linux"
echo "========================================"
echo

# Comprobar si MySQL responde.
echo "[1/5] Comprobando MySQL..."

if ! "$MYSQL" \
    -h"$SIGERU_DB_HOST" \
    -P"$SIGERU_DB_PORT" \
    -u"$SIGERU_DB_USER" \
    ${SIGERU_DB_PASSWORD:+-p"$SIGERU_DB_PASSWORD"} \
    -e "SELECT 1;" >/dev/null 2>&1; then

    echo "ERROR: No se pudo conectar con MySQL."
    echo
    echo "Asegúrate de que XAMPP esté iniciado:"
    echo "    sudo $XAMPP_DIR/lampp start"
    echo
    echo "Si root tiene contraseña:"
    echo "    export SIGERU_DB_PASSWORD='tu_contraseña'"
    exit 1
fi

echo "OK: MySQL disponible."

# Crear estructura.
echo "[2/5] Cargando estructura de la base de datos..."

if ! "$MYSQL" \
    -h"$SIGERU_DB_HOST" \
    -P"$SIGERU_DB_PORT" \
    -u"$SIGERU_DB_USER" \
    ${SIGERU_DB_PASSWORD:+-p"$SIGERU_DB_PASSWORD"} \
    -e "source database/ddl.sql"; then

    echo "ERROR: No se pudo ejecutar database/ddl.sql"
    exit 1
fi

# Cargar datos de prueba.
echo "[3/5] Cargando datos de prueba..."

if [[ -f "database/datos-prueba.sql" ]]; then
    if ! "$MYSQL" \
        -h"$SIGERU_DB_HOST" \
        -P"$SIGERU_DB_PORT" \
        -u"$SIGERU_DB_USER" \
        ${SIGERU_DB_PASSWORD:+-p"$SIGERU_DB_PASSWORD"} \
        "$SIGERU_DB_NAME" \
        -e "source database/datos-prueba.sql"; then

        echo "ERROR: No se pudo ejecutar database/datos-prueba.sql"
        exit 1
    fi
else
    echo "ADVERTENCIA: No existe database/datos-prueba.sql"
fi

# Iniciar API de usuarios.
echo "[4/5] Iniciando API de usuarios en puerto $USER_API_PORT..."

"$PHP" -S "localhost:$USER_API_PORT" api-usuarios/index.php &
PIDS+=("$!")

# Iniciar API de gestión.
echo "      Iniciando API de gestión en puerto $MANAGEMENT_API_PORT..."

"$PHP" -S "localhost:$MANAGEMENT_API_PORT" api-gestion/index.php &
PIDS+=("$!")

# Iniciar frontend.
echo "[5/5] Iniciando frontend en puerto $FRONTEND_PORT..."

"$PHP" -S "localhost:$FRONTEND_PORT" -t frontend &
PIDS+=("$!")

sleep 1

echo
echo "========================================"
echo " SiGeRU iniciado correctamente"
echo "========================================"
echo
echo "Frontend:"
echo "  http://localhost:$FRONTEND_PORT"
echo
echo "API de usuarios:"
echo "  http://localhost:$USER_API_PORT"
echo
echo "API de gestión:"
echo "  http://localhost:$MANAGEMENT_API_PORT"
echo
echo "Cuenta de demostración:"
echo "  Usuario: admin@sigeru.local"
echo "  Contraseña: admin123"
echo
echo "Pulsa Ctrl+C para detener los servidores."
echo

# Mantener el script activo mientras los servidores estén ejecutándose.
while true; do
    sleep 1

    for pid in "${PIDS[@]}"; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "ADVERTENCIA: Uno de los servidores se detuvo."
        fi
    done
done
