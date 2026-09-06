#!/bin/bash

# ==============================================================================
# SiGeRU - Gestión de respaldos
# Servidor de aplicaciones (192.168.1.10)
# Esquema: Completo (Mensual) + Diferencial (Semanal) + Incremental (Diario)
# ==============================================================================

# Configuración del servidor de backup
SERVIDOR_BACKUP="192.168.1.12"
USUARIO_BACKUP="respaldo"
PUERTO_SSH="2026"

# Rutas locales a respaldar
RUTA_APP="/var/www/html"
RUTA_CONF_HTTPD="/etc/httpd"

# Rutas temporales y de control
RUTA_TEMP="/var/backups/sigeru"
DIR_SNAR="/var/lib/sigeru-backup"
SNAR_BASE="$DIR_SNAR/aplicacion_base.snar"
SNAR_INC="$DIR_SNAR/aplicacion_inc.snar"
ARCHIVO_LOG="/var/log/sigeru-backup.log"

# Opciones SSH seguras para ejecución desatendida
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
    mkdir -p "$DIR_SNAR"
    mkdir -p "$(dirname "$ARCHIVO_LOG")"
}


EnviarBackup() {
    local archivo="$1"
    local tipo="$2"

    if [ ! -f "$archivo" ]; then
        RegistrarLog "ERROR: El archivo $archivo no existe para transferir."
        return 1
    fi

    local tamano
    tamano=$(du -h "$archivo" | cut -f1)
    RegistrarLog "Enviando respaldo ($tamano) al servidor $SERVIDOR_BACKUP en '$tipo'..."

    # Transferencia con creación automática del directorio remoto si no existe
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

    RegistrarLog "Aplicando política de retención en servidor de backup ($tipo: conservar $dias_retencion días)..."

    ssh $SSH_OPTS "$USUARIO_BACKUP@$SERVIDOR_BACKUP" \
        "find /backups/aplicaciones/$tipo/ -name '*.tar.bz2' -type f -mtime +$dias_retencion -delete" 2>/dev/null

    if [ $? -eq 0 ]; then
        RegistrarLog "Rotación de respaldos $tipo completada."
    else
        RegistrarLog "ADVERTENCIA: No se pudo verificar la rotación remota."
    fi
}


# ------------------------------------------------------------------------------
# 1. Respaldo Completo Mensual (Nivel 0 - Punto de referencia para todo el mes)
# ------------------------------------------------------------------------------
BackupCompleto() {
    local archivo="$RUTA_TEMP/aplicacion-completo-$FECHA.tar.bz2"
    RegistrarLog "Iniciando RESPALDO COMPLETO MENSUAL (Nivel 0)..."

    # Se borran snapshots anteriores para crear el nuevo estado base mensual
    rm -f "$SNAR_BASE" "$SNAR_INC"

    tar --listed-incremental="$SNAR_BASE" \
        -cjf "$archivo" \
        "$RUTA_APP" \
        "$RUTA_CONF_HTTPD" 2>> "$ARCHIVO_LOG"

    local tar_status=$?
    if [ $tar_status -eq 0 ] || [ $tar_status -eq 1 ]; then
        # Sincronizamos el snapshot incremental para que el lunes continúe desde aquí
        cp "$SNAR_BASE" "$SNAR_INC"
        RegistrarLog "Respaldo completo mensual generado correctamente ($archivo)."
        EnviarBackup "$archivo" "mensuales"
    else
        RegistrarLog "ERROR al generar respaldo completo (Código tar: $tar_status)."
    fi
}


# ------------------------------------------------------------------------------
# 2. Respaldo Diferencial Semanal (Nivel 1 - Cambios desde el Completo Mensual)
# ------------------------------------------------------------------------------
BackupDiferencial() {
    local archivo="$RUTA_TEMP/aplicacion-diferencial-$FECHA.tar.bz2"
    RegistrarLog "Iniciando RESPALDO DIFERENCIAL SEMANAL (Cambios respecto al mensual)..."

    if [ ! -f "$SNAR_BASE" ]; then
        RegistrarLog "ADVERTENCIA: No existe snapshot base mensual. Ejecutando respaldo completo primero."
        BackupCompleto
        return
    fi

    # Se copia el snapshot base mensual a uno temporal para no sobreescribir la base
    local snar_dif_temp="$DIR_SNAR/temp_dif.snar"
    cp "$SNAR_BASE" "$snar_dif_temp"

    tar --listed-incremental="$snar_dif_temp" \
        -cjf "$archivo" \
        "$RUTA_APP" \
        "$RUTA_CONF_HTTPD" 2>> "$ARCHIVO_LOG"

    local tar_status=$?
    if [ $tar_status -eq 0 ] || [ $tar_status -eq 1 ]; then
        # Actualizamos el snapshot incremental con el estado de este domingo
        cp "$snar_dif_temp" "$SNAR_INC"
        rm -f "$snar_dif_temp"
        RegistrarLog "Respaldo diferencial generado correctamente ($archivo)."
        EnviarBackup "$archivo" "semanales"
    else
        rm -f "$snar_dif_temp"
        RegistrarLog "ERROR al generar respaldo diferencial (Código tar: $tar_status)."
    fi
}


# ------------------------------------------------------------------------------
# 3. Respaldo Incremental Diario (Nivel 2 - Cambios respecto al día anterior)
# ------------------------------------------------------------------------------
BackupIncremental() {
    local archivo="$RUTA_TEMP/aplicacion-incremental-$FECHA.tar.bz2"
    RegistrarLog "Iniciando RESPALDO INCREMENTAL DIARIO (Cambios respecto a última copia)..."

    if [ ! -f "$SNAR_INC" ]; then
        RegistrarLog "ADVERTENCIA: No existe snapshot incremental previo. Generando respaldo completo base."
        BackupCompleto
        return
    fi

    tar --listed-incremental="$SNAR_INC" \
        -cjf "$archivo" \
        "$RUTA_APP" \
        "$RUTA_CONF_HTTPD" 2>> "$ARCHIVO_LOG"

    local tar_status=$?
    if [ $tar_status -eq 0 ] || [ $tar_status -eq 1 ]; then
        RegistrarLog "Respaldo incremental diario generado correctamente ($archivo)."
        EnviarBackup "$archivo" "diarios"
    else
        RegistrarLog "ERROR al generar respaldo incremental (Código tar: $tar_status)."
    fi
}


# ==============================================================================
# Control de Flujo Principal
# ==============================================================================

ValidarPermisos
PrepararDirectorios

case "$1" in
    incremental|diario)
        BackupIncremental
        ;;
    diferencial|semanal)
        BackupDiferencial
        ;;
    completo|mensual)
        BackupCompleto
        ;;
    *)
        echo "======================================================="
        echo "        SiGeRU - Gestión de Respaldos de Aplicación   "
        echo "======================================================="
        echo "Uso: $0 {incremental|diferencial|completo}"
        echo
        echo "Opciones:"
        echo "  incremental  : Respaldo diario de cambios (Retención: 7 días)"
        echo "  diferencial  : Respaldo semanal vs. base mensual (Retención: 4 semanas)"
        echo "  completo     : Respaldo mensual base de referencia (Retención: 12 meses)"
        exit 1
        ;;
esac