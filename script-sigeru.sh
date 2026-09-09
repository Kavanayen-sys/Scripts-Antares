#!/bin/bash

# ==============================================================================
# SiGeRU - Sistema de Gestión de Residuos Urbanos
# Grupo Antares - Script Modular de Administración del Servidor (Rocky Linux 10)
# Versión 1.3 - Sintaxis Limpia y Control Estricto
# ==============================================================================

set -o pipefail

# Colores para la consola
COLOR_RESET="\e[0m"
COLOR_VERDE="\e[1;32m"
COLOR_ROJO="\e[1;31m"
COLOR_AZUL="\e[1;34m"
COLOR_AMARILLO="\e[1;33m"
COLOR_CYAN="\e[1;36m"

# Archivos de logs
LOG_ADMIN="/var/log/sigeru-admin.log"
LOG_USUARIOS="/var/log/cre_usuarios.log"
LOG_BACKUP_APP="/var/log/sigeru-backup.log"
LOG_BACKUP_DB="/var/log/sigeru-backup-mysql.log"

# Comprobación de root
if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_ROJO}ERROR: Este script debe ejecutarse con privilegios de root (sudo).${COLOR_RESET}" >&2
    exit 1
fi

# ==============================================================================
# FUNCIONES AUXILIARES Y VALIDACIONES
# ==============================================================================

RegistrarAccion() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ADMIN] $1" >> "$LOG_ADMIN"
}

Pausar() {
    echo
    echo -e "${COLOR_AMARILLO}Presione [ENTER] para continuar...${COLOR_RESET}"
    read -r
}

ValidarNombreUsuario() {
    local usr="$1"
    if [[ ! "$usr" =~ ^[a-z_][a-z0-9_-]{1,31}$ ]]; then
        echo -e "${COLOR_ROJO}ERROR: Nombre de usuario inválido.${COLOR_RESET}"
        echo -e "${COLOR_AMARILLO}Reglas: Solo letras minúsculas (a-z), números (0-9), guiones (-) y guiones bajos (_). No se admiten espacios ni caracteres especiales.${COLOR_RESET}"
        return 1
    fi
    return 0
}

ValidarIP_CIDR() {
    local ip_cidr="$1"
    if [[ ! "$ip_cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${COLOR_ROJO}ERROR: Formato de IP/Máscara inválido. Ejemplo: 192.168.1.10/24${COLOR_RESET}"
        return 1
    fi
    return 0
}

ValidarIP() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${COLOR_ROJO}ERROR: Formato de IP inválido. Ejemplo: 192.168.1.1${COLOR_RESET}"
        return 1
    fi
    return 0
}

CargarUsuario() {
    unset nombre
    echo
    echo "1. Escribir nombre de usuario | 2. Cargar desde archivo | 0. Volver"
    read -p "Opción: " opc_cargar
    case $opc_cargar in
        1)
            read -p "Nombre de usuario: " nombre_input
            nombre_input=$(echo "$nombre_input" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
            if [ "$nombre_input" != "0" ] && [ -n "$nombre_input" ]; then
                if ValidarNombreUsuario "$nombre_input"; then
                    nombre="$nombre_input"
                fi
            fi
            ;;
        2)
            read -p "Ruta del archivo: " ruta_arch
            if [ -f "$ruta_arch" ]; then
                local primer_usr=$(awk '{print $1; exit}' "$ruta_arch" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
                if ValidarNombreUsuario "$primer_usr"; then
                    nombre="$primer_usr"
                    echo -e "${COLOR_VERDE}Usuario '$nombre' cargado desde el archivo.${COLOR_RESET}"
                fi
            else
                echo -e "${COLOR_ROJO}El archivo no existe.${COLOR_RESET}"
            fi
            ;;
        0)
            echo "Operación cancelada."
            ;;
        *)
            echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"
            ;;
    esac
}

# ==============================================================================
# 1. MÓDULO: GESTIÓN DE USUARIOS
# ==============================================================================
ModuloUsuarios() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}         SiGeRU - 1. GESTIÓN DE USUARIOS            ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo "1. Agregar usuario"
        echo "2. Eliminar usuario"
        echo "3. Carga masiva de usuarios desde archivo"
        echo "4. Modificar cuenta (Bloquear / Desbloquear / Shell)"
        echo "5. Listar usuarios estándar del sistema (UID >= 1000)"
        echo "0. Volver al menú principal"
        echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
        read -p "Seleccione una opción: " opc

        case $opc in
            1)
                CargarUsuario
                if [ -n "$nombre" ]; then
                    if id "$nombre" &>/dev/null; then
                        echo -e "${COLOR_AMARILLO}El usuario '$nombre' ya existe.${COLOR_RESET}"
                    else
                        useradd -m -s /bin/bash "$nombre"
                        local inicial=$(echo "${nombre:0:1}" | tr '[:lower:]' '[:upper:]')
                        local pass_inicial="${inicial}#123456"
                        echo "$nombre:$pass_inicial" | chpasswd
                        chage -d 0 "$nombre"
                        echo -e "${COLOR_VERDE}Usuario '$nombre' creado.${COLOR_RESET}"
                        echo -e "Contraseña temporal: ${COLOR_AMARILLO}$pass_inicial${COLOR_RESET}"
                        echo "$(date '+%Y-%m-%d %H:%M:%S') - Creado: $nombre" >> "$LOG_USUARIOS"
                        RegistrarAccion "Usuario creado: $nombre"
                    fi
                fi
                Pausar
                ;;
            2)
                CargarUsuario
                if [ -n "$nombre" ]; then
                    if id "$nombre" &>/dev/null; then
                        read -p "¿Desea borrar también el directorio /home? (s/n): " resp
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
                read -p "Ruta del archivo de usuarios: " ruta_arch
                if [ -f "$ruta_arch" ]; then
                    while IFS= read -r linea || [ -n "$linea" ]; do
                        usr=$(echo "$linea" | awk '{print $1}' | tr '[:upper:]' '[:lower:]' | tr -d '\r')
                        [ -z "$usr" ] && continue
                        if ! ValidarNombreUsuario "$usr"; then
                            echo -e "${COLOR_ROJO}[IGNORADO]${COLOR_RESET} '$usr' no cumple las reglas de nombre."
                            continue
                        fi
                        if id "$usr" &>/dev/null; then
                            echo -e "${COLOR_AMARILLO}[EXISTE]${COLOR_RESET} $usr"
                        else
                            useradd -m -s /bin/bash "$usr"
                            local inicial=$(echo "${usr:0:1}" | tr '[:lower:]' '[:upper:]')
                            local pass_tmp="${inicial}#123456"
                            echo "$usr:$pass_tmp" | chpasswd
                            chage -d 0 "$usr"
                            echo -e "${COLOR_VERDE}[CREADO]${COLOR_RESET} $usr (Pass: $pass_tmp)"
                            echo "$(date '+%Y-%m-%d %H:%M:%S') - Masivo: $usr" >> "$LOG_USUARIOS"
                        fi
                    done < "$ruta_arch"
                    RegistrarAccion "Carga masiva desde: $ruta_arch"
                else
                    echo -e "${COLOR_ROJO}El archivo no existe.${COLOR_RESET}"
                fi
                Pausar
                ;;
            4)
                read -p "Usuario a modificar: " nombre
                if id "$nombre" &>/dev/null; then
                    echo "a. Bloquear cuenta | b. Desbloquear cuenta | c. Establecer shell /sbin/nologin"
                    read -p "Opción: " subopc
                    case $subopc in
                        a) passwd -l "$nombre" && echo -e "${COLOR_VERDE}Cuenta bloqueada.${COLOR_RESET}" ;;
                        b) passwd -u "$nombre" && echo -e "${COLOR_VERDE}Cuenta desbloqueada.${COLOR_RESET}" ;;
                        c) usermod -s /sbin/nologin "$nombre" && echo -e "${COLOR_VERDE}Shell modificado.${COLOR_RESET}" ;;
                        *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}" ;;
                    esac
                else
                    echo -e "${COLOR_ROJO}El usuario no existe.${COLOR_RESET}"
                fi
                Pausar
                ;;
            5)
                echo -e "\n${COLOR_AZUL}--- Usuarios estándar (UID >= 1000) ---${COLOR_RESET}"
                awk -F: '$3 >= 1000 && $3 < 65534 {printf "Usuario: %-15s UID: %-6s Home: %-20s Shell: %s\n", $1, $3, $6, $7}' /etc/passwd
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# ==============================================================================
# 2. MÓDULO: GESTIÓN DE GRUPOS
# ==============================================================================
ModuloGrupos() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}           SiGeRU - 2. GESTIÓN DE GRUPOS            ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo "1. Agregar grupo"
        echo "2. Eliminar grupo"
        echo "3. Agregar usuario a un grupo"
        echo "4. Eliminar usuario de un grupo"
        echo "5. Listar grupos y sus miembros"
        echo "0. Volver al menú principal"
        echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
        read -p "Seleccione una opción: " opc

        case $opc in
            1)
                read -p "Nombre del grupo: " grupo
                grupo=$(echo "$grupo" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
                if [ -n "$grupo" ] && [ "$grupo" != "0" ]; then
                    if ! ValidarNombreUsuario "$grupo"; then
                        echo -e "${COLOR_ROJO}Nombre de grupo inválido.${COLOR_RESET}"
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
                read -p "Nombre del usuario: " nombre
                read -p "Nombre del grupo: " grupo
                if id "$nombre" &>/dev/null && getent group "$grupo" &>/dev/null; then
                    usermod -aG "$grupo" "$nombre"
                    echo -e "${COLOR_VERDE}Usuario '$nombre' agregado a '$grupo'.${COLOR_RESET}"
                    RegistrarAccion "Usuario $nombre añadido al grupo $grupo"
                else
                    echo -e "${COLOR_ROJO}El usuario o el grupo no existen.${COLOR_RESET}"
                fi
                Pausar
                ;;
            4)
                read -p "Nombre del usuario: " nombre
                read -p "Nombre del grupo: " grupo
                if gpasswd -d "$nombre" "$grupo" 2>/dev/null; then
                    echo -e "${COLOR_VERDE}Usuario '$nombre' eliminado del grupo '$grupo'.${COLOR_RESET}"
                    RegistrarAccion "Usuario $nombre removido del grupo $grupo"
                else
                    echo -e "${COLOR_ROJO}Error al remover usuario del grupo.${COLOR_RESET}"
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

# ==============================================================================
# 3. MÓDULO: GESTIÓN DE RESPALDOS
# ==============================================================================
ModuloRespaldos() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}         SiGeRU - 3. GESTIÓN DE RESPALDOS           ${COLOR_RESET}"
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
        echo -e "${COLOR_AZUL}--- Auditoría y Logs ---${COLOR_RESET}"
        echo "7. Ver registros de respaldos"
        echo "0. Volver al menú principal"
        echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
        read -p "Seleccione una opción: " opc

        case $opc in
            1)
                if [ -x "/usr/local/bin/backup-sigeru.sh" ]; then
                    /usr/local/bin/backup-sigeru.sh incremental
                else
                    echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-sigeru.sh${COLOR_RESET}"
                fi
                Pausar
                ;;
            2)
                if [ -x "/usr/local/bin/backup-sigeru.sh" ]; then
                    /usr/local/bin/backup-sigeru.sh diferencial
                else
                    echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-sigeru.sh${COLOR_RESET}"
                fi
                Pausar
                ;;
            3)
                if [ -x "/usr/local/bin/backup-sigeru.sh" ]; then
                    /usr/local/bin/backup-sigeru.sh completo
                else
                    echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-sigeru.sh${COLOR_RESET}"
                fi
                Pausar
                ;;
            4)
                if [ -x "/usr/local/bin/backup-mysql.sh" ]; then
                    /usr/local/bin/backup-mysql.sh incremental
                else
                    echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-mysql.sh${COLOR_RESET}"
                fi
                Pausar
                ;;
            5)
                if [ -x "/usr/local/bin/backup-mysql.sh" ]; then
                    /usr/local/bin/backup-mysql.sh diferencial
                else
                    echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-mysql.sh${COLOR_RESET}"
                fi
                Pausar
                ;;
            6)
                if [ -x "/usr/local/bin/backup-mysql.sh" ]; then
                    /usr/local/bin/backup-mysql.sh completo
                else
                    echo -e "${COLOR_ROJO}No se encontró /usr/local/bin/backup-mysql.sh${COLOR_RESET}"
                fi
                Pausar
                ;;
            7)
                echo -e "${COLOR_AZUL}--- Logs de Respaldo de Aplicación ---${COLOR_RESET}"
                if [ -f "$LOG_BACKUP_APP" ]; then
                    tail -n 10 "$LOG_BACKUP_APP"
                else
                    echo "Sin registros."
                fi
                echo -e "\n${COLOR_AZUL}--- Logs de Respaldo de MySQL ---${COLOR_RESET}"
                if [ -f "$LOG_BACKUP_DB" ]; then
                    tail -n 10 "$LOG_BACKUP_DB"
                else
                    echo "Sin registros."
                fi
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# ==============================================================================
# 4. MÓDULO: GESTIÓN DE REDES
# ==============================================================================
ModuloRedes() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}           SiGeRU - 4. GESTIÓN DE REDES             ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo "1. Ver estado de interfaces y direcciones IP"
        echo "2. Configurar IP estática (nmcli)"
        echo "3. Configurar interfaz en modo DHCP (Modo Mantenimiento/Internet)"
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
                    echo -e "${COLOR_ROJO}ERROR: La interfaz '$iface' no existe en este servidor.${COLOR_RESET}"
                    Pausar
                    continue
                fi

                read -p "Dirección IP y máscara (ej: 192.168.1.10/24): " ip_cidr
                if ! ValidarIP_CIDR "$ip_cidr"; then
                    Pausar
                    continue
                fi

                read -p "Puerta de enlace (Gateway, ej: 192.168.1.1): " gw
                if ! ValidarIP "$gw"; then
                    Pausar
                    continue
                fi

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
                        echo -e "${COLOR_AMARILLO}En Red Interna de VirtualBox no hay un router en .1, por lo que es normal que de 100% pérdida:${COLOR_RESET}"
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
}

# ==============================================================================
# 5. MÓDULO: GESTIÓN DE BASES DE DATOS
# ==============================================================================
ModuloBaseDatos() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}       SiGeRU - 5. GESTIÓN DE BASES DE DATOS        ${COLOR_RESET}"
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
                    echo -e "${COLOR_VERDE}Base de datos 'sigeru' y tabla 'usuarios' verificadas con éxito.${COLOR_RESET}"
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
}

# ==============================================================================
# 6. MÓDULO: GESTIÓN DE FIREWALL
# ==============================================================================
ModuloFirewall() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}          SiGeRU - 6. GESTIÓN DE FIREWALL           ${COLOR_RESET}"
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
                    echo -e "${COLOR_VERDE}Puerto $pto abierto.${COLOR_RESET}"
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
                    echo -e "${COLOR_VERDE}Puerto $pto cerrado.${COLOR_RESET}"
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
}

# ==============================================================================
# 7. MÓDULO: GESTIÓN DE LOGS DEL SISTEMA
# ==============================================================================
ModuloLogs() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}       SiGeRU - 7. GESTIÓN DE LOGS DEL SISTEMA       ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo "1. Ver log de administración (este script)"
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
                    echo "Sin registros."
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
                    echo "No se encontró log de Apache."
                fi
                Pausar
                ;;
            6)
                if [ -f "/var/log/mysqld.log" ]; then
                    tail -n 30 /var/log/mysqld.log
                else
                    echo "No se encontró log de MySQL."
                fi
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# ==============================================================================
# MENÚ PRINCIPAL INTERACTIVO
# ==============================================================================
MenuPrincipal() {
    local opcion=-1
    while [ "$opcion" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}       SiGeRU - CONSOLA DE ADMINISTRACIÓN DEL SERVIDOR                ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}       Grupo Antares | Rocky Linux 10 Minimal                         ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
        echo -e " 1. ${COLOR_VERDE}[Usuarios]${COLOR_RESET}      Gestión de Usuarios (Creación, Masivo, Baja)"
        echo -e " 2. ${COLOR_VERDE}[Grupos]${COLOR_RESET}        Gestión de Grupos y Membresías"
        echo -e " 3. ${COLOR_VERDE}[Respaldos]${COLOR_RESET}     Rutinas de Backup SiGeRU (GFS: Diario, Semanal, Mensual)"
        echo -e " 4. ${COLOR_VERDE}[Redes]${COLOR_RESET}         Configuración de Red e Interfaces (nmcli)"
        echo -e " 5. ${COLOR_VERDE}[Bases Datos]${COLOR_RESET}   Administración de MySQL Server 8.4"
        echo -e " 6. ${COLOR_VERDE}[Firewall]${COLOR_RESET}      Control de Puertos y Reglas (Firewalld)"
        echo -e " 7. ${COLOR_VERDE}[Logs]${COLOR_RESET}          Auditoría de Logs del Sistema y Seguridad"
        echo -e " 0. ${COLOR_ROJO}[Salir]${COLOR_RESET}         Cerrar la consola de administración"
        echo -e "${COLOR_CYAN}======================================================================${COLOR_RESET}"
        read -p "Seleccione el módulo a administrar: " opcion

        case $opcion in
            1) ModuloUsuarios ;;
            2) ModuloGrupos ;;
            3) ModuloRespaldos ;;
            4) ModuloRedes ;;
            5) ModuloBaseDatos ;;
            6) ModuloFirewall ;;
            7) ModuloLogs ;;
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
}

# ==============================================================================
# CONTROL DE FLUJO (INTERACTIVO O LÍNEA DE COMANDOS)
# ==============================================================================

if [ $# -eq 0 ]; then
    RegistrarAccion "Sesión interactiva iniciada"
    MenuPrincipal

elif [ $# -eq 2 ] && [ "$2" == "archivo" ]; then
    if [ -f "$1" ]; then
        nombre=$(awk '{print $1; exit}' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r')
        if ValidarNombreUsuario "$nombre"; then
            if id "$nombre" &>/dev/null; then
                userdel -r "$nombre"
                echo "Usuario '$nombre' eliminado."
            else
                useradd -m -s /bin/bash "$nombre"
                inicial=$(echo "${nombre:0:1}" | tr '[:lower:]' '[:upper:]')
                echo "$nombre:${inicial}#123456" | chpasswd
                chage -d 0 "$nombre"
                echo "Usuario '$nombre' creado."
            fi
        fi
    fi

elif [ $# -eq 1 ]; then
    nombre=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    if ValidarNombreUsuario "$nombre"; then
        if id "$nombre" &>/dev/null; then
            userdel -r "$nombre"
            echo "Usuario '$nombre' eliminado."
        else
            useradd -m -s /bin/bash "$nombre"
            inicial=$(echo "${nombre:0:1}" | tr '[:lower:]' '[:upper:]')
            echo "$nombre:${inicial}#123456" | chpasswd
            chage -d 0 "$nombre"
            echo "Usuario '$nombre' creado."
        fi
    fi
fi