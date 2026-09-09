#!/bin/bash

# ==============================================================================
# SiGeRU - Gestión de respaldos REALES de Base de Datos
# Servidor de Base de Datos (192.168.1.11)
# Esquema: Completo (mysqldump) + Diferencial (Binlogs acumulados) + Incremental (Binlog diario)
# ==============================================================================

# Configuración del servidor de backup
SERVIDOR_BACKUP="192.168.1.12"
USUARIO_BACKUP="respaldo"
PUERTO_SSH="2026"

NOMBRE_BD="sigeru"
DIR_MYSQL="/var/lib/mysql"
BINLOG_INDEX="$DIR_MYSQL/binlog.index"

# Rutas de control y temporales
RUTA_TEMP="/var/backups/sigeru-mysql"
DIR_CONTROL="/var/lib/sigeru-backup"
MARKER_BASE="$DIR_CONTROL/mysql_base_binlog.txt"
MARKER_LAST="$DIR_CONTROL/mysql_last_binlog.txt"
ARCHIVO_LOG="/var/log/sigeru-backup-mysql.log"

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
    mkdir -p "$DIR_CONTROL"
    mkdir -p "$(dirname "$ARCHIVO_LOG")"
}


# Obtener el nombre del binlog activo actual
ObtenerBinlogActual() {
    mysql -N -e "SHOW MASTER STATUS;" 2>/dev/null | awk '{print $1}'
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

    RegistrarLog "Aplicando política de retención ($tipo: conservar $dias_retencion días)..."

    ssh $SSH_OPTS "$USUARIO_BACKUP@$SERVIDOR_BACKUP" \
        "find /backups/mysql/$tipo/ -name 'mysql-*' -type f -mtime +$dias_retencion -delete" 2>/dev/null

    if [ $? -eq 0 ]; then
        RegistrarLog "Rotación de respaldos MySQL $tipo completada."
    else
        RegistrarLog "ADVERTENCIA: No se pudo verificar la rotación remota."
    fi
}


# ------------------------------------------------------------------------------
# 1. RESPALDO COMPLETO MENSUAL (Dump lógico base + rotación de log)
# ------------------------------------------------------------------------------
BackupCompleto() {
    local archivo="$RUTA_TEMP/mysql-$NOMBRE_BD-completo-$FECHA.sql.bz2"
    RegistrarLog "Iniciando RESPALDO COMPLETO MENSUAL (mysqldump base)..."

    # mysqldump con --flush-logs cierra el binlog anterior e inicia uno nuevo limpio
    mysqldump \
        --single-transaction \
        --quick \
        --flush-logs \
        --routines \
        --triggers \
        --events \
        --databases "$NOMBRE_BD" 2>> "$ARCHIVO_LOG" | bzip2 -c > "$archivo"

    local dump_status=$?
    if [ $dump_status -eq 0 ] && [ -s "$archivo" ]; then
        # Guardamos el nuevo binlog activo como punto cero del mes
        local binlog_actual
        binlog_actual=$(ObtenerBinlogActual)
        echo "$binlog_actual" > "$MARKER_BASE"
        echo "$binlog_actual" > "$MARKER_LAST"

        RegistrarLog "Completo mensual generado ($archivo). Punto de inicio binlog: $binlog_actual"
        EnviarBackup "$archivo" "mensuales"
    else
        RegistrarLog "ERROR: Falló mysqldump completo."
        rm -f "$archivo"
    fi
}


# ------------------------------------------------------------------------------
# 2. RESPALDO DIFERENCIAL SEMANAL (Todos los binlogs desde el Completo Mensual)
# ------------------------------------------------------------------------------
BackupDiferencial() {
    local archivo="$RUTA_TEMP/mysql-$NOMBRE_BD-diferencial-$FECHA.tar.bz2"
    RegistrarLog "Iniciando RESPALDO DIFERENCIAL SEMANAL (Binlogs acumulados del mes)..."

    if [ ! -f "$MARKER_BASE" ]; then
        RegistrarLog "ADVERTENCIA: No existe punto de inicio mensual. Ejecutando respaldo completo primero."
        BackupCompleto
        return
    fi

    local binlog_inicio
    binlog_inicio=$(cat "$MARKER_BASE")

    # Forzamos cierre del binlog actual para poder empaquetar datos consistentes
    mysqladmin flush-logs 2>> "$ARCHIVO_LOG"
    local binlog_nuevo
    binlog_nuevo=$(ObtenerBinlogActual)

    # Identificamos todos los binlogs desde el inicio mensual hasta el recién cerrado
    local lista_logs=()
    local capturar=0
    while IFS= read -r log_line; do
        log_name=$(basename "$log_line")
        if [ "$log_name" == "$binlog_inicio" ]; then capturar=1; fi
        if [ "$log_name" == "$binlog_nuevo" ]; then break; fi
        if [ $capturar -eq 1 ]; then
            lista_logs+=("$log_name")
        fi
    done < "$BINLOG_INDEX"

    if [ ${#lista_logs[@]} -eq 0 ]; then
        RegistrarLog "Sin cambios acumulados desde el respaldo completo."
        return
    fi

    # Empaquetamos los logs binarios acumulados
    tar -cjf "$archivo" -C "$DIR_MYSQL" "${lista_logs[@]}" 2>> "$ARCHIVO_LOG"
    if [ $? -eq 0 ]; then
        echo "$binlog_nuevo" > "$MARKER_LAST"
        RegistrarLog "Respaldo diferencial generado con ${#lista_logs[@]} logs binarios ($archivo)."
        EnviarBackup "$archivo" "semanales"
    else
        RegistrarLog "ERROR al empaquetar diferencial de logs binarios."
        rm -f "$archivo"
    fi
}


# ------------------------------------------------------------------------------
# 3. RESPALDO INCREMENTAL DIARIO (Solo los binlogs generados desde ayer)
# ------------------------------------------------------------------------------
BackupIncremental() {
    local archivo="$RUTA_TEMP/mysql-$NOMBRE_BD-incremental-$FECHA.tar.bz2"
    RegistrarLog "Iniciando RESPALDO INCREMENTAL DIARIO (Binlogs del día)..."

    if [ ! -f "$MARKER_LAST" ]; then
        RegistrarLog "ADVERTENCIA: No existe marcador previo. Ejecutando respaldo completo base."
        BackupCompleto
        return
    fi

    local binlog_inicio
    binlog_inicio=$(cat "$MARKER_LAST")

    # Cerramos el log de hoy para empaquetarlo
    mysqladmin flush-logs 2>> "$ARCHIVO_LOG"
    local binlog_nuevo
    binlog_nuevo=$(ObtenerBinlogActual)

    local lista_logs=()
    local capturar=0
    while IFS= read -r log_line; do
        log_name=$(basename "$log_line")
        if [ "$log_name" == "$binlog_inicio" ]; then capturar=1; fi
        if [ "$log_name" == "$binlog_nuevo" ]; then break; fi
        if [ $capturar -eq 1 ]; then
            lista_logs+=("$log_name")
        fi
    done < "$BINLOG_INDEX"

    if [ ${#lista_logs[@]} -eq 0 ]; then
        RegistrarLog "Sin transacciones nuevas para respaldar hoy."
        return
    fi

    tar -cjf "$archivo" -C "$DIR_MYSQL" "${lista_logs[@]}" 2>> "$ARCHIVO_LOG"
    if [ $? -eq 0 ]; then
        echo "$binlog_nuevo" > "$MARKER_LAST"
        RegistrarLog "Respaldo incremental generado con ${#lista_logs[@]} binlogs ($archivo)."
        EnviarBackup "$archivo" "diarios"
    else
        RegistrarLog "ERROR al empaquetar incremental de logs binarios."
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
        echo "        SiGeRU - Gestión de Respaldos MySQL (GFS)     "
        echo "======================================================="
        echo "Uso: $0 {incremental|diferencial|completo}"
        echo
        echo "Opciones:"
        echo "  incremental  : Respaldo de transacciones del día (Binlogs diarios)"
        echo "  diferencial  : Respaldo acumulado del mes (Binlogs acumulados)"
        echo "  completo     : Respaldo lógico total de la base (mysqldump base)"
        exit 1
        ;;
esac