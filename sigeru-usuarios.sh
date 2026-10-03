#!/bin/bash

# ==============================================================================
# SiGeRU - Módulo: Gestión de Usuarios y Grupos
# ==============================================================================

set -o pipefail

COLOR_RESET="\e[0m"
COLOR_VERDE="\e[1;32m"
COLOR_ROJO="\e[1;31m"
COLOR_AZUL="\e[1;34m"
COLOR_AMARILLO="\e[1;33m"
COLOR_CYAN="\e[1;36m"

LOG_ADMIN="/var/log/sigeru-admin.log"
LOG_USUARIOS="/var/log/cre_usuarios.log"

if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_ROJO}ERROR: Debe ejecutarse como root.${COLOR_RESET}" >&2
    exit 1
fi

RegistrarAccion() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [USUARIOS/GRUPOS] $1" >> "$LOG_ADMIN"
}

Pausar() {
    echo
    echo -e "${COLOR_AMARILLO}Presione [ENTER] para continuar...${COLOR_RESET}"
    read -r
}

ValidarNombre() {
    local str="$1"
    if [[ ! "$str" =~ ^[a-z_][a-z0-9_-]{1,31}$ ]]; then
        echo -e "${COLOR_ROJO}ERROR: Nombre inválido.${COLOR_RESET}"
        echo -e "${COLOR_AMARILLO}Reglas: Solo minúsculas (a-z), números (0-9), guiones (-) y guiones bajos (_). Sin espacios.${COLOR_RESET}"
        return 1
    fi
    return 0
}

PedirUsuario() {
    unset nombre
    echo
    read -p "Ingrese el nombre de usuario (o '0' para cancelar): " nombre_input
    nombre_input=$(echo "$nombre_input" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    if [ "$nombre_input" != "0" ] && [ -n "$nombre_input" ]; then
        if ValidarNombre "$nombre_input"; then
            nombre="$nombre_input"
        fi
    else
        echo "Operación cancelada."
    fi
}

# --- Submenú Usuarios ---
MenuUsuarios() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}              GESTIÓN DE USUARIOS                   ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo "1. Agregar usuario"
        echo "2. Eliminar usuario"
        echo "3. Modificar cuenta (Bloquear / Desbloquear / Shell)"
        echo "4. Listar usuarios estándar (UID >= 1000)"
        echo "0. Volver"
        echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
        read -p "Opción: " opc

        case $opc in
            1)
                PedirUsuario
                if [ -n "$nombre" ]; then
                    if id "$nombre" &>/dev/null; then
                        echo -e "${COLOR_AMARILLO}El usuario '$nombre' ya existe.${COLOR_RESET}"
                    else
                        useradd -m -s /bin/bash "$nombre"
                        local inicial=$(echo "${nombre:0:1}" | tr '[:lower:]' '[:upper:]')
                        local pass_inicial="${inicial}#123456"
                        echo "$nombre:$pass_inicial" | chpasswd
                        chage -d 0 "$nombre"
                        echo -e "${COLOR_VERDE}Usuario '$nombre' creado exitosamente.${COLOR_RESET}"
                        echo -e "Contraseña temporal: ${COLOR_AMARILLO}$pass_inicial${COLOR_RESET}"
                        echo "$(date '+%Y-%m-%d %H:%M:%S') - Creado: $nombre" >> "$LOG_USUARIOS"
                        RegistrarAccion "Usuario creado: $nombre"
                    fi
                fi
                Pausar
                ;;
            2)
                PedirUsuario
                if [ -n "$nombre" ]; then
                    if id "$nombre" &>/dev/null; then
                        read -p "¿Desea borrar el directorio /home? (s/n): " resp
                        if [[ "$resp" =~ ^[sS]$ ]]; then
                            userdel -r "$nombre"
                        else
                            userdel "$nombre"
                        fi
                        echo -e "${COLOR_VERDE}Usuario '$nombre' eliminado.${COLOR_RESET}"
                        RegistrarAccion "Usuario eliminado: $nombre"
                    else
                        echo -e "${COLOR_ROJO}El usuario '$nombre' no existe.${COLOR_RESET}"
                    fi
                fi
                Pausar
                ;;
            3)
                PedirUsuario
                if [ -n "$nombre" ]; then
                    if id "$nombre" &>/dev/null; then
                        echo "a. Bloquear cuenta | b. Desbloquear cuenta | c. Shell nologin"
                        read -p "Opción: " subopc
                        case $subopc in
                            a) passwd -l "$nombre" && echo -e "${COLOR_VERDE}Cuenta bloqueada.${COLOR_RESET}" ;;
                            b) passwd -u "$nombre" && echo -e "${COLOR_VERDE}Cuenta desbloqueada.${COLOR_RESET}" ;;
                            c) usermod -s /sbin/nologin "$nombre" && echo -e "${COLOR_VERDE}Shell modificado a /sbin/nologin.${COLOR_RESET}" ;;
                            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}" ;;
                        esac
                    else
                        echo -e "${COLOR_ROJO}El usuario no existe.${COLOR_RESET}"
                    fi
                fi
                Pausar
                ;;
            4)
                echo -e "\n${COLOR_AZUL}--- Usuarios estándar (UID >= 1000) ---${COLOR_RESET}"
                awk -F: '$3 >= 1000 && $3 < 65534 {printf "Usuario: %-15s UID: %-6s Home: %-20s Shell: %s\n", $1, $3, $6, $7}' /etc/passwd
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# --- Submenú Grupos ---
MenuGrupos() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}               GESTIÓN DE GRUPOS                    ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo "1. Agregar grupo"
        echo "2. Eliminar grupo"
        echo "3. Agregar usuario a un grupo"
        echo "4. Eliminar usuario de un grupo"
        echo "5. Listar grupos y sus miembros"
        echo "0. Volver"
        echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
        read -p "Opción: " opc

        case $opc in
            1)
                echo
                read -p "Nombre del grupo: " grupo
                grupo=$(echo "$grupo" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
                if [ -n "$grupo" ] && [ "$grupo" != "0" ]; then
                    if ! ValidarNombre "$grupo"; then
                        echo -e "${COLOR_ROJO}Nombre inválido.${COLOR_RESET}"
                    elif getent group "$grupo" &>/dev/null; then
                        echo -e "${COLOR_AMARILLO}El grupo '$grupo' ya existe.${COLOR_RESET}"
                    else
                        groupadd "$grupo" && echo -e "${COLOR_VERDE}Grupo '$grupo' creado.${COLOR_RESET}"
                        RegistrarAccion "Grupo creado: $grupo"
                    fi
                fi
                Pausar
                ;;
            2)
                echo
                read -p "Nombre del grupo a eliminar: " grupo
                if [ -n "$grupo" ] && [ "$grupo" != "0" ]; then
                    if getent group "$grupo" &>/dev/null; then
                        groupdel "$grupo" && echo -e "${COLOR_VERDE}Grupo '$grupo' eliminado.${COLOR_RESET}"
                        RegistrarAccion "Grupo eliminado: $grupo"
                    else
                        echo -e "${COLOR_ROJO}El grupo no existe.${COLOR_RESET}"
                    fi
                fi
                Pausar
                ;;
            3)
                PedirUsuario
                if [ -n "$nombre" ]; then
                    read -p "Grupo al que desea añadirlo: " grupo
                    if id "$nombre" &>/dev/null && getent group "$grupo" &>/dev/null; then
                        usermod -aG "$grupo" "$nombre"
                        echo -e "${COLOR_VERDE}Usuario '$nombre' agregado a '$grupo'.${COLOR_RESET}"
                        RegistrarAccion "Usuario $nombre añadido a grupo $grupo"
                    else
                        echo -e "${COLOR_ROJO}El usuario o grupo no existen.${COLOR_RESET}"
                    fi
                fi
                Pausar
                ;;
            4)
                PedirUsuario
                if [ -n "$nombre" ]; then
                    read -p "Grupo del que desea quitarlo: " grupo
                    if gpasswd -d "$nombre" "$grupo" 2>/dev/null; then
                        echo -e "${COLOR_VERDE}Usuario '$nombre' eliminado de '$grupo'.${COLOR_RESET}"
                        RegistrarAccion "Usuario $nombre removido de grupo $grupo"
                    else
                        echo -e "${COLOR_ROJO}Error al remover usuario del grupo.${COLOR_RESET}"
                    fi
                fi
                Pausar
                ;;
            5)
                echo -e "\n${COLOR_AZUL}--- Grupos del Sistema (GID >= 1000) ---${COLOR_RESET}"
                awk -F: '$3 >= 1000 && $3 < 65534 {printf "Grupo: %-15s GID: %-6s Miembros: %s\n", $1, $3, $4}' /etc/group
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# Menú principal del módulo
opc_main=-1
while [ "$opc_main" -ne 0 ]; do
    clear
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}       SiGeRU - GESTIÓN DE USUARIOS Y GRUPOS        ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo "1. Administrar Usuarios"
    echo "2. Administrar Grupos"
    echo "0. Volver al menú principal"
    echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
    read -p "Seleccione una opción: " opc_main

    case $opc_main in
        1) MenuUsuarios ;;
        2) MenuGrupos ;;
        0) break ;;
        *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
    esac
done