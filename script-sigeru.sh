#!/bin/bash

# ==============================================================================
# SiGeRU - Sistema de Gestión de Residuos Urbanos
# Grupo Antares - Script Modular de Administración del Servidor (Rocky Linux 10)
# ==============================================================================

set -o pipefail

# Paleta de colores para la interfaz de consola
COLOR_RESET="\e[0m"
COLOR_VERDE="\e[1;32m"
COLOR_ROJO="\e[1;31m"
COLOR_AZUL="\e[1;34m"
COLOR_AMARILLO="\e[1;33m"
COLOR_CYAN="\e[1;36m"

# Archivos de registro y control
LOG_ADMIN="/var/log/sigeru-admin.log"
LOG_USUARIOS="/var/log/cre_usuarios.log"
LOG_BACKUP_APP="/var/log/sigeru-backup.log"
LOG_BACKUP_DB="/var/log/sigeru-backup-mysql.log"

# Comprobación de privilegios de ejecución
if [ "$EUID" -ne 0 ]; then
    echo -e "${COLOR_ROJO}ERROR: Este script debe ejecutarse con privilegios de root (sudo).${COLOR_RESET}" >&2
    exit 1
fi

# ==============================================================================
# FUNCIONES AUXILIARES Y DE ENTRADA (Mantiene y mejora tu lógica de clase)
# ==============================================================================

RegistrarAccion() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ADMIN] $1" >> "$LOG_ADMIN"
}

Pausar() {
    echo
    echo -e "${COLOR_AMARILLO}Presione [ENTER] para continuar...${COLOR_RESET}"
    read -r
}

VerificarNumero() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        echo -e "${COLOR_ROJO}Error: No se aceptan nombres puramente numéricos.${COLOR_RESET}"
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
            if [ "$nombre_input" != "0" ] && [ -n "$nombre_input" ]; then
                if VerificarNumero "$nombre_input"; then
                    nombre="$nombre_input"
                fi
            fi
            ;;
        2)
            read -p "Ruta del archivo: " ruta_arch
            if [ -f "$ruta_arch" ]; then
                nombre=$(awk '{print $1; exit}' "$ruta_arch")
                echo -e "${COLOR_VERDE}Usuario '$nombre' cargado desde el archivo.${COLOR_RESET}"
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
        echo "5. Listar usuarios del sistema (UID >= 1000)"
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
                        # Política de clave: Inicial mayúscula + #123456
                        local pass_inicial="$(tr '[:lower:]' '[:upper:]' <<< ${nombre:0:1})#123456"
                        echo "$nombre:$pass_inicial" | chpasswd
                        chage -d 0 "$nombre" # Fuerza cambio de clave en 1er login
                        echo -e "${COLOR_VERDE}Usuario '$nombre' creado.${COLOR_RESET}"
                        echo -e "Contraseña temporal asignada: ${COLOR_AMARILLO}$pass_inicial${COLOR_RESET}"
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
                        usr=$(echo "$linea" | awk '{print $1}' | tr -d '\r')
                        [ -z "$usr" ] && continue
                        if id "$usr" &>/dev/null; then
                            echo -e "${COLOR_AMARILLO}[EXISTE]${COLOR_RESET} $usr"
                        else
                            useradd -m -s /bin/bash "$usr"
                            local pass_tmp="$(tr '[:lower:]' '[:upper:]' <<< ${usr:0:1})#123456"
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
                    echo "a. Bloquear cuenta | b. Desbloquear cuenta | c. Establecer shell nologin"
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
                if [ -n "$grupo" ] && [ "$grupo" != "0" ]; then
                    if getent group "$grupo" &>/dev/null; then
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
# 3. MÓDULO: GESTIÓN DE RESPALDOS (SiGeRU GFS)
# ==============================================================================
ModuloRespaldos() {
    local opc=-1
    while [ "$opc" -ne 0 ]; do
        clear
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo -e "${COLOR_CYAN}         SiGeRU - 3. GESTIÓN DE RESPALDOS           ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
        echo "1. Ejecutar Respaldo Incremental Diario (App)"
        echo "2. Ejecutar Respaldo Diferencial Semanal (App)"
        echo "3. Ejecutar Respaldo Completo Mensual (App)"
        echo "4. Ejecutar Respaldo de Base de Datos MySQL"
        echo "5. Ver registros y estado de respaldos"
        echo "0. Volver al menú principal"
        echo -e "${COLOR_CYAN}-----------------------------------------------------${COLOR_RESET}"
        read -p "Seleccione una opción: " opc

        case $opc in
            1)
                if [ -x "/usr/local/bin/backup-sigeru.sh" ]; then
                    /usr/local/bin/backup-sigeru.sh incremental
                else
                    echo -e "${COLOR_ROJO}Script /usr/local/bin/backup-sigeru.sh no encontrado o sin permisos.${COLOR_RESET}"
                fi
                Pausar
                ;;
            2)
                if [ -x "/usr/local/bin/backup-sigeru.sh" ]; then
                    /usr/local/bin/backup-sigeru.sh diferencial
                else
                    echo -e "${COLOR_ROJO}Script /usr/local/bin/backup-sigeru.sh no encontrado.${COLOR_RESET}"
                fi
                Pausar
                ;;
            3)
                if [ -x "/usr/local/bin/backup-sigeru.sh" ]; then
                    /usr/local/bin/backup-sigeru.sh completo
                else
                    echo -e "${COLOR_ROJO}Script /usr/local/bin/backup-sigeru.sh no encontrado.${COLOR_RESET}"
                fi
                Pausar
                ;;
            4)
                if [ -x "/usr/local/bin/backup-mysql.sh" ]; then
                    echo "a. Incremental Diario | b. Diferencial Semanal | c. Completo Mensual"
                    read -p "Tipo de respaldo MySQL: " subopc
                    case $subopc in
                        a) /usr/local/bin/backup-mysql.sh incremental ;;
                        b) /usr/local/bin/backup-mysql.sh diferencial ;;
                        c) /usr/local/bin/backup-mysql.sh completo ;;
                        *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}" ;;
                    esac
                else
                    echo -e "${COLOR_ROJO}Script /usr/local/bin/backup-mysql.sh no encontrado.${COLOR_RESET}"
                fi
                Pausar
                ;;
            5)
                echo -e "${COLOR_AZUL}--- Logs de Respaldo de Aplicación ---${COLOR_RESET}"
                [ -f "$LOG_BACKUP_APP" ] && tail -n 10 "$LOG_BACKUP_APP" || echo "Sin registros."
                echo -e "\n${COLOR_AZUL}--- Logs de Respaldo de MySQL ---${COLOR_RESET}"
                [ -f "$LOG_BACKUP_DB" ] && tail -n 10 "$LOG_BACKUP_DB" || echo "Sin registros."
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# ==============================================================================
# 4. MÓDULO: GESTIÓN DE REDES (NetworkManager / nmcli)
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
        echo "3. Configurar interfaz en modo DHCP"
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
                read -p "Dirección IP y máscara (ej: 192.168.1.10/24): " ip_cidr
                read -p "Puerta de enlace (Gateway, ej: 192.168.1.1): " gw
                read -p "Servidores DNS (ej: 8.8.8.8,1.1.1.1): " dns

                nmcli connection modify "$iface" ipv4.method manual
                nmcli connection modify "$iface" ipv4.addresses "$ip_cidr"
                nmcli connection modify "$iface" ipv4.gateway "$gw"
                nmcli connection modify "$iface" ipv4.dns "$dns"
                nmcli connection down "$iface" && nmcli connection up "$iface"
                echo -e "${COLOR_VERDE}IP estática configurada en $iface.${COLOR_RESET}"
                RegistrarAccion "Red estática configurada en $iface ($ip_cidr)"
                Pausar
                ;;
            3)
                read -p "Interfaz a configurar en DHCP (ej: enp0s3): " iface
                nmcli connection modify "$iface" ipv4.method auto
                nmcli connection down "$iface" && nmcli connection up "$iface"
                echo -e "${COLOR_VERDE}Interfaz $iface configurada en DHCP.${COLOR_RESET}"
                RegistrarAccion "Interfaz $iface cambiada a DHCP"
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
                    4) ping -c 3 192.168.1.1 ;;
                    *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}" ;;
                esac
                Pausar
                ;;
            5)
                read -p "Interfaz a reiniciar (ej: enp0s3): " iface
                nmcli connection down "$iface" && nmcli connection up "$iface"
                echo -e "${COLOR_VERDE}Conexión reiniciada.${COLOR_RESET}"
                Pausar
                ;;
            0) break ;;
            *) echo -e "${COLOR_ROJO}Opción inválida.${COLOR_RESET}"; Pausar ;;
        esac
    done
}

# ==============================================================================
# 5. MÓDULO: GESTIÓN DE BASES DE DATOS (MySQL)
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
}

# ==============================================================================
# 6. MÓDULO: GESTIÓN DE FIREWALL (Firewalld)
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
                firewall-cmd --permanent --zone=public --add-port="$pto"
                firewall-cmd --reload
                echo -e "${COLOR_VERDE}Puerto $pto abierto.${COLOR_RESET}"
                RegistrarAccion "Firewall: Puerto $pto abierto"
                Pausar
                ;;
            3)
                read -p "Puerto y protocolo a cerrar (ej: 22/tcp): " pto
                firewall-cmd --permanent --zone=public --remove-port="$pto"
                firewall-cmd --reload
                echo -e "${COLOR_VERDE}Puerto $pto cerrado.${COLOR_RESET}"
                RegistrarAccion "Firewall: Puerto $pto cerrado"
                Pausar
                ;;
            4)
                firewall-cmd --permanent --zone=public --add-port=2026/tcp
                firewall-cmd --permanent --zone=public --add-service=http
                firewall-cmd --permanent --zone=public --add-service=https
                firewall-cmd --permanent --zone=public --remove-service=ssh
                firewall-cmd --reload
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
                [ -f "$LOG_ADMIN" ] && tail -n 30 "$LOG_ADMIN" || echo "Sin registros."
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
                [ -f "/var/log/httpd/error_log" ] && tail -n 30 /var/log/httpd/error_log || echo "No se encontró log de Apache."
                Pausar
                ;;
            6)
                [ -f "/var/log/mysqld.log" ] && tail -n 30 /var/log/mysqld.log || echo "No se encontró log de MySQL."
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
# CONTROL DE FLUJO (INTERACTIVO O ARGUMENTOS DE LÍNEA DE COMANDOS)
# ==============================================================================

# Si se ejecuta sin parámetros, entra al menú interactivo
if [ $# -eq 0 ]; then
    RegistrarAccion "Sesión interactiva iniciada"
    MenuPrincipal

# Modo compatible con parámetros rápidos: $0 <usuario> [archivo]
elif [ $# -eq 2 ] && [ "$2" == "archivo" ]; then
    if [ -f "$1" ]; then
        nombre=$(awk '{print $1; exit}' "$1")
        if id "$nombre" &>/dev/null; then
            userdel -r "$nombre"
            echo "Usuario '$nombre' eliminado."
        else
            useradd -m -s /bin/bash "$nombre"
            echo "$nombre:$(tr '[:lower:]' '[:upper:]' <<< ${nombre:0:1})#123456" | chpasswd
            chage -d 0 "$nombre"
            echo "Usuario '$nombre' creado."
        fi
    fi

elif [ $# -eq 1 ]; then
    VerificarNumero "$1"
    nombre="$1"
    if id "$nombre" &>/dev/null; then
        userdel -r "$nombre"
        echo "Usuario '$nombre' eliminado."
    else
        useradd -m -s /bin/bash "$nombre"
        echo "$nombre:$(tr '[:lower:]' '[:upper:]' <<< ${nombre:0:1})#123456" | chpasswd
        chage -d 0 "$nombre"
        echo "Usuario '$nombre' creado."
    fi
fi