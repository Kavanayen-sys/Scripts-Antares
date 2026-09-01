#!/bin/bash

# ==========================================
# SiGeRU - Gestión de respaldos
# Servidor de aplicaciones (192.168.1.10)
# ==========================================

# Configuración de Red y Servidor de Backup
SERVIDOR_BACKUP="192.168.1.12"
USUARIO_BACKUP="respaldo"
PUERTO_SSH="2026"

# Rutas locales
RUTA_APP="/var/www/html"
RUTA_CONF_HTTPD="/etc/httpd"
# Opcional: Agregar configuraciones de Docker o servicios si existen
# RUTA_DOCKER="/etc/docker /opt/docker-compose"
RUTA_TEMP="/var/backups/sigeru"
ARCHIVO_INCREMENTAL="/var/lib/sigeru-backup/aplicacion.snar"
ARCHIVO_LOG="/var/log/sigeru-backup.log"

# Opciones SSH para entornos desatendidos / Cron
SSH_OPTS="-p $PUERTO_SSH -o BatchMode=yes -o ConnectTimeout=15"

FECHA=$(date +"%Y-%m-%d_%H-%M-%S")


RegistrarLog() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$ARCHIVO_LOG"
}


ValidarPermisos() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Este script debe ejecutarse con privilegios de root." >&2
        exit 1
    fi
}


PrepararDirectorios() {
    mkdir -p "$RUTA_TEMP"
    mkdir -p "$(dirname "$ARCHIVO_INCREMENTAL")"
    mkdir -p "$(dirname "$ARCHIVO_LOG")"
}


EnviarBackup() {
    local archivo="$1"
    local tipo="$2"

    if [ ! -f "$archivo" ]; then
        RegistrarLog "ERROR: El archivo $archivo no existe para ser transferido."
        return 1
    fi

    local tamano
    tamano=$(du -h "$archivo" | cut -f1)
    RegistrarLog "Enviando respaldo ($tamano) al servidor $SERVIDOR_BACKUP en categoría '$tipo'..."

    # rsync con creación automática del directorio destino en el servidor remoto
    rsync -avz \
        --rsync-path="mkdir -p /backups/aplicaciones/$tipo && rsync" \
        -e "ssh $SSH_OPTS" \
        "$archivo" \
        "$USUARIO_BACKUP@$SERVIDOR_BACKUP:/backups/aplicaciones/$tipo/"

    if [ $? -eq 0 ]; then
        RegistrarLog "Respaldo transferido exitosamente a /backups/aplicaciones/$tipo/"
        rm -f "$archivo"
        EjecutarRotacion "$tipo"
    else
        RegistrarLog "ERROR crítico: Falló la transferencia rsync hacia $SERVIDOR_BACKUP."
        return 1
    fi
}


EjecutarRotacion() {
    local tipo="$1"
    local dias_retencion

    case "$tipo" in
        diarios)   dias_retencion=7 ;;
        semanales) dias_retencion=28 ;; # 4 semanas
        mensuales) dias_retencion=365 ;; # 12 meses
        *) return ;;
    esac

    RegistrarLog "Aplicando política de rotación en servidor de backup ($tipo: conservar $dias_retencion días)..."

    # Elimina en el servidor de respaldo los archivos que superen los días de retención
    ssh $SSH_OPTS "$USUARIO_BACKUP@$SERVIDOR_BACKUP" \
        "find /backups/aplicaciones/$tipo/ -name '*.tar.bz2' -type f -mtime +$dias_retencion -delete" 2>/dev/null

    if [ $? -eq 0 ]; then
        RegistrarLog "Rotación de respaldos $tipo completada."
    else
        RegistrarLog "ADVERTENCIA: No se pudo verificar la rotación en el servidor remoto."
    fi
}


BackupIncremental() {
    local archivo="$RUTA_TEMP/aplicacion-incremental-$FECHA.tar.bz2"
    RegistrarLog "Iniciando respaldo incremental de la aplicación (Web + Conf)..."

    # Se ejecuta tar incremental usando el archivo de metadatos .snar
    tar --listed-incremental="$ARCHIVO_INCREMENTAL" \
        -cjf "$archivo" \
        "$RUTA_APP" \
        "$RUTA_CONF_HTTPD" 2>> "$ARCHIVO_LOG"

    local tar_status=$?

    # 0 = Éxito, 1 = Archivo cambió durante la lectura (aceptable en servidores vivos)
    if [ $tar_status -eq 0 ] || [ $tar_status -eq 1 ]; then
        RegistrarLog "Respaldo incremental creado localmente ($archivo)."
        EnviarBackup "$archivo" "diarios"
    else
        RegistrarLog "ERROR al crear respaldo incremental (Código tar: $tar_status)."
    fi
}


BackupCompleto() {
    local archivo="$RUTA_TEMP/aplicacion-completo-$FECHA.tar.bz2"
    RegistrarLog "Iniciando respaldo completo de la aplicación..."

    # Se elimina el .snar para reiniciar el árbol incremental
    rm -f "$ARCHIVO_INCREMENTAL"

    tar --listed-incremental="$ARCHIVO_INCREMENTAL" \
        -cjf "$archivo" \
        "$RUTA_APP" \
        "$RUTA_CONF_HTTPD" 2>> "$ARCHIVO_LOG"

    local tar_status=$?

    if [ $tar_status -eq 0 ] || [ $tar_status -eq 1 ]; then
        RegistrarLog "Respaldo completo semanal creado localmente ($archivo)."
        EnviarBackup "$archivo" "semanales"
    else
        RegistrarLog "ERROR al crear respaldo completo (Código tar: $tar_status)."
    fi
}


BackupMensual() {
    local archivo="$RUTA_TEMP/aplicacion-mensual-$FECHA.tar.bz2"
    RegistrarLog "Iniciando respaldo completo mensual para archivo a largo plazo..."

    # Respaldo standalone independiente del ciclo semanal/diario
    tar -cjf "$archivo" \
        "$RUTA_APP" \
        "$RUTA_CONF_HTTPD" 2>> "$ARCHIVO_LOG"

    local tar_status=$?

    if [ $tar_status -eq 0 ] || [ $tar_status -eq 1 ]; then
        RegistrarLog "Respaldo mensual creado localmente ($archivo)."
        EnviarBackup "$archivo" "mensuales"
    else
        RegistrarLog "ERROR al crear respaldo mensual (Código tar: $tar_status)."
    fi
}


# ==========================================
# Control de Flujo Principal
# ==========================================

ValidarPermisos

case "$1" in
    incremental)
        PrepararDirectorios
        BackupIncremental
        ;;
    completo)
        PrepararDirectorios
        BackupCompleto
        ;;
    mensual)
        PrepararDirectorios
        BackupMensual
        ;;
    *)
        echo "=========================================="
        echo "   SiGeRU - Gestión de Respaldos Web"
        echo "=========================================="
        echo "Uso: $0 {incremental|completo|mensual}"
        echo
        echo "Opciones:"
        echo "  incremental : Respaldo diario de cambios (Retención: 7 días)"
        echo "  completo    : Respaldo semanal base (Retención: 4 semanas)"
        echo "  mensual     : Respaldo mensual de largo plazo (Retención: 12 meses)"
        exit 1
        ;;
esac
