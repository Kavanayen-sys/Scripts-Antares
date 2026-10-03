#!/bin/bash

# ==============================================================================
# SiGeRU - Módulo: Gestión de Firewall (Firewalld)
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

RegistrarAccion() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [FIREWALL] $1" >> "$LOG_ADMIN"
}

Pausar() {
    echo
    echo -e "${COLOR_AMARILLO}Presione [ENTER] para continuar...${COLOR_RESET}"
    read -r
}

opc=-1
while [ "$opc" -ne 0 ]; do
    clear
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}          SiGeRU - GESTIÓN DE FIREWALL              ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo "1. Ver estado del Firewall y reglas activas"
    echo "2. Abrir puerto permanentemente"
    echo "3. Cerrar puerto"
    echo "4. Aplicar configuración de seguridad SiGeRU (SSH: 2026, HTTP, HTTPS)"
    echo "5. Recargar Firewall (Reload)"
    echo "0. Volver al menú principal"
    echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
    read -p "Seleccione una opción: " opc

    case $opc in
        1)
            echo
            firewall-cmd --list-all
            Pausar
            ;;
        2)
            read -p "Puerto y protocolo (ej: 2026/tcp): " pto
            if [[ "$pto" =~ ^[0-9]+/(tcp|udp)$ ]]; then
                firewall-cmd --permanent --zone=public --add-port="$pto" >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
                echo -e "${COLOR_VERDE}Puerto $pto abierto con éxito.${COLOR_RESET}"
                RegistrarAccion "Firewall: Puerto $pto abierto"
            else
                echo -e "${COLOR_ROJO}Formato inválido. Ejemplo: 2026/tcp${COLOR_RESET}"
            fi
            Pausar
            ;;
        3)
            read -p "Puerto y protocolo a cerrar (ej: 22/tcp): " pto
            if [[ "$pto" =~ ^[0-9]+/(tcp|udp)$ ]]; then
                firewall-cmd --permanent --zone=public --remove-port="$pto" >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
                echo -e "${COLOR_VERDE}Puerto $pto cerrado con éxito.${COLOR_RESET}"
                RegistrarAccion "Firewall: Puerto $pto cerrado"
            else
                echo -e "${COLOR_ROJO}Formato inválido. Ejemplo: 22/tcp${COLOR_RESET}"
            fi
            Pausar
            ;;
        4)
            firewall-cmd --permanent --zone=public --add-port=2026/tcp >/dev/null 2>&1
            firewall-cmd --permanent --zone=public --add-service=http >/dev/null 2>&1
            firewall-cmd --permanent --zone=public --add-service=https >/dev/null 2>&1
            firewall-cmd --permanent --zone=public --remove-service=ssh >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            echo -e "${COLOR_VERDE}Perfil de seguridad SiGeRU aplicado con éxito.${COLOR_RESET}"
            RegistrarAccion "Firewall: Perfil SiGeRU aplicado"
            Pausar
            ;;
        5)
            firewall-cmd --reload
            echo -e "${COLOR_VERDE}Firewall recargado.${COLOR_RESET}"
            Pausar
            ;;
        0) break ;;
        *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
    esac
done