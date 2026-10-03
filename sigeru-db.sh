#!/bin/bash

# ==============================================================================
# SiGeRU - Módulo: Gestión de Bases de Datos (MySQL)
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [BD] $1" >> "$LOG_ADMIN"
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
    echo -e "${COLOR_CYAN}       SiGeRU - GESTIÓN DE BASES DE DATOS           ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo "1. Ver estado del servicio MySQL Server"
    echo "2. Iniciar / Detener / Reiniciar MySQL"
    echo "3. Crear / Verificar Base de Datos 'sigeru'"
    echo "4. Ejecutar optimización y chequeo de tablas (mysqlcheck)"
    echo "5. Ver bases de datos existentes"
    echo "0. Volver al menú principal"
    echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
    read -p "Seleccione una opción: " opc

    case $opc in
        1)
            systemctl status mysqld --no-pager
            Pausar
            ;;
        2)
            echo "a. Iniciar | b. Detener | c. Reiniciar"
            read -p "Acción: " subopc
            case $subopc in
                a) systemctl start mysqld && echo -e "${COLOR_VERDE}MySQL iniciado.${COLOR_RESET}" ;;
                b) systemctl stop mysqld && echo -e "${COLOR_AMARILLO}MySQL detenido.${COLOR_RESET}" ;;
                c) systemctl restart mysqld && echo -e "${COLOR_VERDE}MySQL reiniciado.${COLOR_RESET}" ;;
            esac
            Pausar
            ;;
        3)
            mysql -e "
              CREATE DATABASE IF NOT EXISTS sigeru;
              USE sigeru;
              CREATE TABLE IF NOT EXISTS usuarios (
                id INT AUTO_INCREMENT PRIMARY KEY,
                nombre VARCHAR(50),
                rol VARCHAR(20),
                creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              );
            "
            if [ $? -eq 0 ]; then
                echo -e "${COLOR_VERDE}Base de datos 'sigeru' y tabla 'usuarios' listas.${COLOR_RESET}"
                RegistrarAccion "Base de datos sigeru verificada/inicializada"
            else
                echo -e "${COLOR_ROJO}Error al conectar con MySQL. Verifique /root/.my.cnf.${COLOR_RESET}"
            fi
            Pausar
            ;;
        4)
            mysqlcheck --optimize --databases sigeru
            Pausar
            ;;
        5)
            echo -e "\n${COLOR_AZUL}--- Bases de Datos en el Servidor ---${COLOR_RESET}"
            mysql -e "SHOW DATABASES;"
            Pausar
            ;;
        0) break ;;
        *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
    esac
done