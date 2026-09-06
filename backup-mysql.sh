#!/bin/bash

# ==============================================================================
# SiGeRU - Gestión de respaldos
# Servidor de Base de Datos (192.168.1.11)
# Esquema: Completo (Mensual) + Diferencial (Semanal) + Incremental (Diario)
# ==============================================================================

# Configuración del servidor de backup
SERVIDOR_BACKUP="192.168.1.12"
USUARIO_BACKUP="respaldo"
PUERTO_SSH="2026"

# Parámetros de Base de Datos
# NOTA: Se utiliza /root/.my.cnf con permisos 600 para autenticación desatendida.
NOMBRE_BD="sigeru"

# Rutas temporales y de logs
RUTA_TEMP="/var/backups/sigeru-mysql"
ARCHIVO_LOG="/var/log/sigeru-backup-mysql.log"

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
    RegistrarLog "Enviando respaldo MySQL ($tamano) al servidor $SERVIDOR_BACKUP en '$tipo'..."

    # Transferencia con creación automática del directorio destino en el servidor de backup
    rsync -avz \
        --rsync-path="mkdir -p /backups/mysql/$tipo && rsync" \
        -e "ssh $SSH_OPTS" \
        "$archivo" \
        "$USUARIO_BACKUP@$SERVIDOR_BACKUP:/backups/mysql/$tipo/"

    if [ $? -eq 0 ]; then
        RegistrarLog "Respaldo MySQL transferido exitosamente a /backups/mysql/$tipo/"
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

    RegistrarLog "Aplicando política de retención en servidor de backup (MySQL $tipo: conservar $dias_retencion días)..."

    ssh $SSH_OPTS "$USUARIO_BACKUP@$SERVIDOR_BACKUP" \
        "find /backups/mysql/$tipo/ -name '*.sql.bz2' -type f -mtime +$dias_retencion -delete" 2>/dev/null

    if [ $? -eq 0 ]; then
        RegistrarLog "Rotación de respaldos MySQL $tipo completada."
    else
        RegistrarLog "ADVERTENCIA: No se pudo verificar la rotación remota."
    fi
}


# ------------------------------------------------------------------------------
# 1. Respaldo Completo Mensual (Nivel 0 - Punto de referencia anual/mensual)
# ------------------------------------------------------------------------------
BackupCompleto() {
    local archivo="$RUTA_TEMP/mysql-$NOMBRE_BD-completo-$FECHA.sql.bz2"
    RegistrarLog "Iniciando RESPALDO COMPLETO MENSUAL de MySQL ($NOMBRE_BD)..."

    mysqldump \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        --events \
        --databases "$NOMBRE_BD" 2>> "$ARCHIVO_LOG" | bzip2 -c > "$archivo"

    local dump_status=$?
    if [ $dump_status -eq 0 ] && [ -s "$archivo" ]; then
        RegistrarLog "Respaldo completo de MySQL generado exitosamente ($archivo)."
        EnviarBackup "$archivo" "mensuales"
    else
        RegistrarLog "ERROR: Falló mysqldump al generar el respaldo completo."
        rm -f "$archivo"
    fi
}


# ------------------------------------------------------------------------------
# 2. Respaldo Diferencial Semanal (Nivel 1 - Puntos de control semanales)
# ------------------------------------------------------------------------------
BackupDiferencial() {
    local archivo="$RUTA_TEMP/mysql-$NOMBRE_BD-diferencial-$FECHA.sql.bz2"
    RegistrarLog "Iniciando RESPALDO DIFERENCIAL SEMANAL de MySQL ($NOMBRE_BD)..."

    mysqldump \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        --events \
        --databases "$NOMBRE_BD" 2>> "$ARCHIVO_LOG" | bzip2 -c > "$archivo"

    local dump_status=$?
    if [ $dump_status -eq 0 ] && [ -s "$archivo" ]; then
        RegistrarLog "Respaldo diferencial de MySQL generado exitosamente ($archivo)."
        EnviarBackup "$archivo" "semanales"
    else
        RegistrarLog "ERROR: Falló mysqldump al generar el respaldo diferencial."
        rm -f "$archivo"
    fi
}


# ------------------------------------------------------------------------------
# 3. Respaldo Incremental Diario (Nivel 2 - Copia diaria frecuente)
# ------------------------------------------------------------------------------
BackupIncremental() {
    local archivo="$RUTA_TEMP/mysql-$NOMBRE_BD-incremental-$FECHA.sql.bz2"
    RegistrarLog "Iniciando RESPALDO INCREMENTAL DIARIO de MySQL ($NOMBRE_BD)..."

    mysqldump \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        --events \
        --databases "$NOMBRE_BD" 2>> "$ARCHIVO_LOG" | bzip2 -c > "$archivo"

    local dump_status=$?
    if [ $dump_status -eq 0 ] && [ -s "$archivo" ]; then
        RegistrarLog "Respaldo incremental de MySQL generado exitosamente ($archivo)."
        EnviarBackup "$archivo" "diarios"
    else
        RegistrarLog "ERROR: Falló mysqldump al generar el respaldo incremental."
        rm -f "$archivo"
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
        echo "        SiGeRU - Gestión de Respaldos de MySQL        "
        echo "======================================================="
        echo "Uso: $0 {incremental|diferencial|completo}"
        echo
        echo "Opciones:"
        echo "  incremental  : Respaldo diario de MySQL (Retención: 7 días)"
        echo "  diferencial  : Respaldo semanal de MySQL (Retención: 4 semanas)"
        echo "  completo     : Respaldo mensual de referencia (Retención: 12 meses)"
        exit 1
        ;;
esac