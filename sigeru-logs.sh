#!/bin/bash

# ==============================================================================
# SiGeRU - Módulo: Gestión de Logs del Sistema
# ==============================================================================

set -o pipefail

COLOR_RESET="\e[0m"
COLOR_VERDE="\e[1;32m"
COLOR_ROJO="\e[1;31m"
COLOR_AZUL="\e[1;34m"
COLOR_AMARILLO="\e[1;33m"
COLOR_CYAN="\e[1;36m"

LOG_ADMIN="/var/log/sigeru-admin.log"

if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_ROJO}ERROR: Debe ejecutarse como root.${COLOR_RESET}" >&2
    exit 1
fi

Pausar() {
    echo
    echo -e "${COLOR_AMARILLO}Presione [ENTER] para continuar...${COLOR_RESET}"
    read -r
}

opc=-1
while [ "$opc" -ne 0 ]; do
    clear
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}       SiGeRU - GESTIÓN DE LOGS DEL SISTEMA         ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo "1. Ver log de administración general"
    echo "2. Ver eventos de autenticación SSH"
    echo "3. Ver estado y bloqueos de Fail2Ban"
    echo "4. Ver errores críticos del sistema (journalctl prioridad error)"
    echo "5. Ver logs del servidor Web Apache (httpd)"
    echo "6. Ver logs de MySQL Server"
    echo "0. Volver al menú principal"
    echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
    read -p "Seleccione una opción: " opc

    case $opc in
        1)
            if [ -f "$LOG_ADMIN" ]; then
                tail -n 30 "$LOG_ADMIN"
            else
                echo "Sin registros en $LOG_ADMIN."
            fi
            Pausar
            ;;
        2)
            echo -e "\n${COLOR_AZUL}--- Últimos eventos de SSH ---${COLOR_RESET}"
            journalctl -u sshd -n 30 --no-pager
            Pausar
            ;;
        3)
            fail2ban-client status sshd 2>/dev/null || echo "Fail2Ban no activo o sin jail sshd."
            Pausar
            ;;
        4)
            echo -e "\n${COLOR_ROJO}--- Errores Críticos del Sistema ---${COLOR_RESET}"
            journalctl -p err..emerg -n 25 --no-pager
            Pausar
            ;;
        5)
            if [ -f "/var/log/httpd/error_log" ]; then
                tail -n 30 /var/log/httpd/error_log
            else
                echo "No se encontró log de Apache (/var/log/httpd/error_log)."
            fi
            Pausar
            ;;
        6)
            if [ -f "/var/log/mysqld.log" ]; then
                tail -n 30 /var/log/mysqld.log
            else
                echo "No se encontró log de MySQL (/var/log/mysqld.log)."
            fi
            Pausar
            ;;
        0) break ;;
        *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
    esac
done