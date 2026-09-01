#!/bin/bash 

LeerArchivo_leer() {
local archivo="$1"
if [ $(find $1 2>/dev/null) ]; then
nombre=$(cut -d' ' -f1 "$archivo")
else
echo "Este archivo, mi estimado, no existe."
unset $nombre
fi
}

LeerNombre_leer() {
echo "
'0' para salir."
read -p "Nombre de usuario: " nombre
if [ $nombre != '0' ]; then
VerificarNumero
else
unset $nombre
echo "Ignora el siguiente texto"
sleep 1
fi
}

AgregarUsuario_crear() {

if [ $(cut -d: -f1 /etc/passwd | grep -w "$nombre") ]; then
echo "Este usuario ya existe"
echo "$nombre" >> cre_usuarios.log
else
sudo useradd -m -s /bin/bash "$nombre" || echo "$nombre" >> cre_usuarios.log
echo "$nombre:$(expr substr "$nombre" 1 1)#123456" | sudo chpasswd 
sudo chage -d 0 "$nombre"
echo "Usuario creado."
fi
}

BorrarUsuario_eliminar() {
sudo userdel -r "$nombre"
}

CargarUsuario() {
echo "
0. Volver 1. Escribir nombre de usuario 2. Cargar archivo"
read -n 1 -p "Introduce una opción: " opcionusuario
case $opcionusuario in
0)
echo "
Volviendo..."
unset $nombre
;;
1)
LeerNombre_leer
;;
2)
read -p "
Ruta del archivo: " archivo
LeerArchivo_leer "$archivo"	        	
;;
*)
echo "Escribiste mal."
;;
esac
if [ $opcionusuario -le 0 ] && [ $opcionusuario -gt 2 ]; then
unset $nombre
fi
}

VerificarNumero(){
    if [ "$1" -eq "$1" ] 2>/dev/null || [ "$2" -eq "$2" ]  2>/dev/null; then
        echo "No se aceptan numeros."
        exit 2

    fi
}


if [ $# -eq 0 ]; 
then
opcion=-1
grupo=''
nombre=''
while [ $opcion -ne 0 ]; do
sleep 1
unset $nombre
unset $grupo
clear 
echo 'AdmUsuarios CUSTOM'
echo “0: Salir. 1. Modificar usuarios. 2. Gestionar BACKUPS.”
read -n 1 -p "Introduce una opción: " opcion
case $opcion in
0)
echo "
Saliendo de AdmUsuarios..."
;;
1)
echo "
0. Volver 
1. Agregar usuario 
2. Eliminar usuario 
3. Agregar grupo 
4. Eliminar grupo 
5. Agregar usuario a un grupo 
6. Eliminar usuario de un grupo"
read -n 1 -p "Introduce una opción: " opcionusuario
case $opcionusuario in
0)
echo "
Volviendo..."
;;
1)
CargarUsuario
if [ $nombre ]; then
AgregarUsuario_crear
fi
;;
2)
echo "
Eliminar usuario."
CargarUsuario 
if [ $nombre ]; then
BorrarUsuario_eliminar
fi
;;
3) 
echo " 
'0' para salir."
echo "Agregar grupo."
read -p "Nombre de grupo: " grupo 
if [ $grupo != "0" ];then
sudo groupadd $grupo
fi

;;
4) 
echo "
'0' para salir."
echo "Eliminar grupo."
read -p "Nombre del grupo: " grupo
if [ $grupo != "0" ];then
sudo groupdel $grupo
fi
;;
5) 
echo "Agregar usuario a un grupo."
echo "Sobre el usuario: "
CargarUsuario
if [ $nombre ]; then
echo "
'0' para salir."
read -p "Escoge el grupo: " grupo
if [ $grupo != "0" ];then
sudo usermod -aG $grupo $nombre 
fi

fi
;;
6)  
echo "
Sacar a un usuario de un grupo"
echo "Sobre el usuario: "
CargarUsuario
if [ $nombre ]; then
echo "
'0' para salir"
read -p "Escoge al grupo: " grupo 
if [ $grupo != "0" ];then
sudo gpasswd -d $nombre $grupo 
fi

fi
;;
esac
;;      
2)
echo "
Gestionar backups"
echo "0. Volver 1. Crear/recuperar backup de usuario 2. Crear backup de grupo:"
read -n 1 -p "Introduce una opción: " backup
case $backup in
0)
echo "
Volviendo..."
;;
1)
CargarUsuario
if [ $nombre ]; then
echo "0. Volver 1. Crear backup 2. Recuperar backup."
read -n 1 -p "Introduce una opción: " usuariobackup
case $usuariobackup in
0)
echo "
Volviendo..."
;;
1)
bash backup.sh crear $nombre
;;
2)
bash backup.sh recuperar $nombre
;;
*)
echo "
Opción inválida"
;;
esac
fi
;;
2)
echo "
0 para volver."
read -p "Nombre del grupo: " grupo
if [ $grupo != "0" ];then
bash backup.sh bckgrupo $grupo
fi

;;
esac

;;
*)
echo "
Opción inválida"
opcion=-1
;;
esac
done

elif [ $# -eq 2 ];
then
if [ $2 == "archivo" ];
then
echo "$1"
LeerArchivo_leer "$1"
echo "En el primer usuario"
if [ $(cut -d: -f1 /etc/passwd | grep -w "$nombre") ]; then
BorrarUsuario_eliminar
echo "Usuario espuriado completamente."
sleep 2
else 
AgregarUsuario_crear
echo "Usuario creado exitosamente."
sleep 2
fi

else

VerificarNumero
nombre="$1"

if [ $(cut -d: -f1 /etc/passwd | grep -w "$nombre") ]; then
BorrarUsuario_eliminar
echo "Usuario espuriado completamente."
sleep 2
else
AgregarUsuario_crear
echo "Usuario creado exitosamente."
sleep 2
fi

fi

fi
echo "fin de ejecución"
