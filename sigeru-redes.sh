#!/bin/bash

# ==============================================================================
# SiGeRU - Módulo: Gestión de Redes (NetworkManager / nmcli)
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [REDES] $1" >> "$LOG_ADMIN"
}

Pausar() {
    echo
    echo -e "${COLOR_AMARILLO}Presione [ENTER] para continuar...${COLOR_RESET}"
    read -r
}

ValidarIP_CIDR() {
    local ip_cidr="$1"
    if [[ ! "$ip_cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${COLOR_ROJO}ERROR: Formato inválido. Ejemplo: 192.168.1.10/24${COLOR_RESET}"
        return 1
    fi
    return 0
}

ValidarIP() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${COLOR_ROJO}ERROR: Formato inválido. Ejemplo: 192.168.1.1${COLOR_RESET}"
        return 1
    fi
    return 0
}

opc=-1
while [ "$opc" -ne 0 ]; do
    clear
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}           SiGeRU - GESTIÓN DE REDES                ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo "1. Ver estado de interfaces y direcciones IP"
    echo "2. Configurar IP estática (nmcli)"
    echo "3. Configurar interfaz en modo DHCP (Mantenimiento/Internet)"
    echo "4. Probar conectividad con servidores (Ping)"
    echo "5. Reiniciar conexión de red"
    echo "0. Volver al menú principal"
    echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
    read -p "Seleccione una opción: " opc

    case $opc in
        1)
            echo -e "\n${COLOR_AZUL}--- Direcciones IP ---${COLOR_RESET}"
            ip -br addr show
            echo -e "\n${COLOR_AZUL}--- Dispositivos NetworkManager ---${COLOR_RESET}"
            nmcli device status
            Pausar
            ;;
        2)
            read -p "Interfaz de red (ej: enp0s3): " iface
            if ! nmcli device status | grep -qw "$iface"; then
                echo -e "${COLOR_ROJO}ERROR: La interfaz '$iface' no existe.${COLOR_RESET}"
                Pausar; continue
            fi

            read -p "Dirección IP y máscara (ej: 192.168.1.10/24): " ip_cidr
            if ! ValidarIP_CIDR "$ip_cidr"; then Pausar; continue; fi

            read -p "Puerta de enlace (Gateway, ej: 192.168.1.1): " gw
            if ! ValidarIP "$gw"; then Pausar; continue; fi

            read -p "Servidores DNS (ej: 8.8.8.8,1.1.1.1): " dns

            nmcli connection modify "$iface" ipv4.method manual ipv4.addresses "$ip_cidr" ipv4.gateway "$gw" ipv4.dns "$dns"
            if [ $? -eq 0 ]; then
                nmcli connection down "$iface" >/dev/null 2>&1
                nmcli connection up "$iface" >/dev/null 2>&1
                echo -e "${COLOR_VERDE}IP estática ($ip_cidr) configurada con éxito en $iface.${COLOR_RESET}"
                RegistrarAccion "Red estática configurada en $iface: $ip_cidr"
            else
                echo -e "${COLOR_ROJO}ERROR: Falló la configuración de red.${COLOR_RESET}"
            fi
            Pausar
            ;;
        3)
            read -p "Interfaz a configurar en DHCP (ej: enp0s3): " iface
            nmcli connection modify "$iface" ipv4.method auto
            if [ $? -eq 0 ]; then
                nmcli connection down "$iface" >/dev/null 2>&1
                nmcli connection up "$iface" >/dev/null 2>&1
                echo -e "${COLOR_VERDE}Interfaz $iface configurada en DHCP exitosamente.${COLOR_RESET}"
                RegistrarAccion "Interfaz $iface cambiada a DHCP"
            else
                echo -e "${COLOR_ROJO}ERROR al cambiar a DHCP.${COLOR_RESET}"
            fi
            Pausar
            ;;
        4)
            echo "1. Servidor Web (192.168.1.10)"
            echo "2. Servidor BD (192.168.1.11)"
            echo "3. Servidor Respaldos (192.168.1.12)"
            echo "4. Gateway (192.168.1.1)"
            read -p "Destino a probar: " p_opc
            case $p_opc in
                1) ping -c 3 192.168.1.10 ;;
                2) ping -c 3 192.168.1.11 ;;
                3) ping -c 3 192.168.1.12 ;;
                4)
                    echo -e "${COLOR_AMARILLO}En Red Interna aislada no hay router en .1, puede dar 100% pérdida:${COLOR_RESET}"
                    ping -c 3 192.168.1.1
                    ;;
                *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}" ;;
            esac
            Pausar
            ;;
        5)
            read -p "Interfaz a reiniciar (ej: enp0s3): " iface
            nmcli connection down "$iface" >/dev/null 2>&1
            nmcli connection up "$iface" >/dev/null 2>&1
            echo -e "${COLOR_VERDE}Conexión reiniciada.${COLOR_RESET}"
            Pausar
            ;;
        0) break ;;
        *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
    esac
done