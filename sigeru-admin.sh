#!/bin/bash

# ==============================================================================
# SiGeRU - Sistema de Gestión de Residuos Urbanos
# Grupo Antares - Script Orquestador Modular de Administración (Rocky Linux 10)
# ==============================================================================

set -o pipefail

COLOR_RESET="\e[0m"
COLOR_VERDE="\e[1;32m"
COLOR_ROJO="\e[1;31m"
COLOR_AZUL="\e[1;34m"
COLOR_AMARILLO="\e[1;33m"
COLOR_CYAN="\e[1;36m"

LOG_ADMIN="/var/log/sigeru-admin.log"
LOG_BACKUP_APP="/var/log/sigeru-backup.log"
LOG_BACKUP_DB="/var/log/sigeru-backup-mysql.log"

if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_ROJO}ERROR: Este script debe ejecutarse con privilegios de root (sudo).${COLOR_RESET}" >&2
    exit 1
fi

RegistrarAccion() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ORQUESTADOR] $1" >> "$LOG_ADMIN"
}

Pausar() {
    echo
    echo -e "${COLOR_AMARILLO}Presione [ENTER] para continuar...${COLOR_RESET}"
    read -r
}

# Submenú específico de Respaldos (llama a backup-sigeru.sh y backup-mysql.sh)
SubmenuRespaldos() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}         SiGeRU - GESTIÓN DE RESPALDOS (GFS)        ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_AZUL}--- Servidor de Aplicaciones (192.168.1.10) ---${COLOR_RESET}"
        echo "1. Respaldo Incremental Diario (App)"
        echo "2. Respaldo Diferencial Semanal (App)"
        echo "3. Respaldo Completo Mensual (App)"
        echo
        echo -e "${COLOR_AZUL}--- Servidor de Base de Datos (192.168.1.11) ---${COLOR_RESET}"
        echo "4. Respaldo Incremental Diario (MySQL)"
        echo "5. Respaldo Diferencial Semanal (MySQL)"
        echo "6. Respaldo Completo Mensual (MySQL)"
        echo
        echo -e "${COLOR_AZUL}--- Registros de Backup ---${COLOR_RESET}"
        echo "7. Ver logs de respaldos"
        echo "0. Volver al menú principal"
        echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
        read -p "Seleccione una opción: " opc

        case $opc in
            1) [ -x "/usr/local/bin/backup-sigeru.sh" ] && /usr/local/bin/backup-sigeru.sh incremental || echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-sigeru.sh${COLOR_RESET}"; Pausar ;;
            2) [ -x "/usr/local/bin/backup-sigeru.sh" ] && /usr/local/bin/backup-sigeru.sh diferencial || echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-sigeru.sh${COLOR_RESET}"; Pausar ;;
            3) [ -x "/usr/local/bin/backup-sigeru.sh" ] && /usr/local/bin/backup-sigeru.sh completo || echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-sigeru.sh${COLOR_RESET}"; Pausar ;;
            4) [ -x "/usr/local/bin/backup-mysql.sh" ] && /usr/local/bin/backup-mysql.sh incremental || echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-mysql.sh${COLOR_RESET}"; Pausar ;;
            5) [ -x "/usr/local/bin/backup-mysql.sh" ] && /usr/local/bin/backup-mysql.sh diferencial || echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-mysql.sh${COLOR_RESET}"; Pausar ;;
            6) [ -x "/usr/local/bin/backup-mysql.sh" ] && /usr/local/bin/backup-mysql.sh completo || echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-mysql.sh${COLOR_RESET}"; Pausar ;;
            7)
                echo -e "${COLOR_AZUL}--- Logs de Respaldo de Aplicación ---${COLOR_RESET}"
                if [ -f "$LOG_BACKUP_APP" ]; then tail -n 10 "$LOG_BACKUP_APP"; else echo "Sin registros."; fi
                echo -e "\n${COLOR_AZUL}--- Logs de Respaldo de MySQL ---${COLOR_RESET}"
                if [ -f "$LOG_BACKUP_DB" ]; then tail -n 10 "$LOG_BACKUP_DB"; else echo "Sin registros."; fi
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# Bucle del Menú Principal
opcion=-1
RegistrarAccion "Sesión administrativa iniciada"

while [ "$opcion" -ne 0 ]; do
    clear
    echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}       SiGeRU - CONSOLA DE ADMINISTRACIÓN DEL SERVIDOR                ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}       Grupo Antares | Rocky Linux 10 Minimal                         ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
    echo -e " 1. ${COLOR_VERDE}[Usuarios/Grupos]${COLOR_RESET}   Gestión de Usuarios, Grupos y Membresías"
    echo -e " 2. ${COLOR_VERDE}[Respaldos]${COLOR_RESET}         Rutinas de Backup SiGeRU (GFS: Diario/Semanal/Mensual)"
    echo -e " 3. ${COLOR_VERDE}[Redes]${COLOR_RESET}             Configuración de Red e Interfaces (nmcli)"
    echo -e " 4. ${COLOR_VERDE}[Bases de Datos]${COLOR_RESET}    Administración de MySQL Server 8.4"
    echo -e " 5. ${COLOR_VERDE}[Firewall]${COLOR_RESET}          Control de Puertos y Reglas (Firewalld)"
    echo -e " 6. ${COLOR_VERDE}[Logs]${COLOR_RESET}              Auditoría de Logs del Sistema y Seguridad"
    echo -e " 0. ${COLOR_ROJO}[Salir]${COLOR_RESET}             Cerrar la consola de administración"
    echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
    read -p "Seleccione el módulo a administrar: " opcion

    case $opcion in
        1)
            if [ -x "/usr/local/bin/sigeru-usuarios.sh" ]; then
                /usr/local/bin/sigeru-usuarios.sh
            else
                echo -e "${COLOR_ROJO}No se encontró el módulo /usr/local/bin/sigeru-usuarios.sh${COLOR_RESET}"
                Pausar
            fi
            ;;
        2)
            SubmenuRespaldos
            ;;
        3)
            if [ -x "/usr/local/bin/sigeru-redes.sh" ]; then
                /usr/local/bin/sigeru-redes.sh
            else
                echo -e "${COLOR_ROJO}No se encontró el módulo /usr/local/bin/sigeru-redes.sh${COLOR_RESET}"
                Pausar
            fi
            ;;
        4)
            if [ -x "/usr/local/bin/sigeru-db.sh" ]; then
                /usr/local/bin/sigeru-db.sh
            else
                echo -e "${COLOR_ROJO}No se encontró el módulo /usr/local/bin/sigeru-db.sh${COLOR_RESET}"
                Pausar
            fi
            ;;
        5)
            if [ -x "/usr/local/bin/sigeru-firewall.sh" ]; then
                /usr/local/bin/sigeru-firewall.sh
            else
                echo -e "${COLOR_ROJO}No se encontró el módulo /usr/local/bin/sigeru-firewall.sh${COLOR_RESET}"
                Pausar
            fi
            ;;
        6)
            if [ -x "/usr/local/bin/sigeru-logs.sh" ]; then
                /usr/local/bin/sigeru-logs.sh
            else
                echo -e "${COLOR_ROJO}No se encontró el módulo /usr/local/bin/sigeru-logs.sh${COLOR_RESET}"
                Pausar
            fi
            ;;
        0)
            echo -e "\n${COLOR_VERDE}Cerrando consola de administración SiGeRU. ¡Hasta luego!${COLOR_RESET}\n"
            RegistrarAccion "Sesión administrativa finalizada"
            exit 0
            ;;
        *)
            echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"
            Pausar
            ;;
    esac
done