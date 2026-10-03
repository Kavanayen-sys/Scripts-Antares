# SiGeRU - Primera entrega Full Stack

VersiÃ³n simple realizada con HTML, CSS, JavaScript, PHP 8 y MySQL 8.

## Funciones incluidas

- landing page;
- registro e inicio de sesiÃ³n;
- formulario pÃºblico de incidencias;
- selector de contenedores cargado desde MySQL;
- panel con listados y ABM de usuarios, contenedores y camiones;
- listado y baja de incidencias;
- intercambio de datos en JSON;
- API REST de usuarios y API REST de gestiÃ³n;
- modelo fÃ­sico, DDL, dump y datos de prueba.

## Seguridad incluida

- todas las consultas con datos del usuario usan sentencias preparadas;
- contraseÃ±as almacenadas con `password_hash`;
- validaciÃ³n de tipos, largos, correos y opciones permitidas;
- sesiÃ³n PHP con cookie `HttpOnly` y `SameSite=Lax`;
- cambio del identificador de sesiÃ³n al iniciar sesiÃ³n;
- token CSRF para altas, modificaciones y bajas;
- lÃ­mite bÃ¡sico de intentos de login;
- panel y endpoints de administraciÃ³n limitados al rol `administrador`;
- acceso desde navegador limitado a `localhost:8090` y `127.0.0.1:8090`;
- salida HTML escapada para evitar inyecciÃ³n de cÃ³digo.

## 1. Preparar XAMPP

Este proyecto estÃ¡ preparado para ejecutarse desde el **Shell de XAMPP para Linux**.

La instalaciÃ³n habitual de XAMPP se encuentra en:

```bash
/opt/lampp
```

Primero iniciar XAMPP:

```bash
sudo /opt/lampp/lampp start
```

Comprobar que MySQL estÃ¡ funcionando:

```bash
/opt/lampp/lampp status
```

> Si XAMPP estÃ¡ instalado en otra ubicaciÃ³n, modificar la variable `XAMPP_DIR`
> del script `run.sh`.

## 2. Preparar la base de datos

Entrar al directorio del proyecto:

```bash
cd /ruta/a/primera-entrega
```

El proyecto necesita MySQL 8 iniciado.

Desde el Shell de XAMPP se puede cargar la estructura y los datos con:

```bash
/opt/lampp/bin/mysql -u root -e "source database/ddl.sql"
/opt/lampp/bin/mysql -u root sigeru -e "source database/datos-prueba.sql"
```

Si el usuario `root` tiene contraseÃ±a, utilizar:

```bash
/opt/lampp/bin/mysql -u root -p -e "source database/ddl.sql"
/opt/lampp/bin/mysql -u root -p sigeru -e "source database/datos-prueba.sql"
```

El archivo `dump-estructura.sql` contiene la misma estructura que el DDL, sin datos.

### ConfiguraciÃ³n de la base de datos

Las APIs usan estos valores por defecto:

| Dato | Valor |
|---|---|
| Servidor | `localhost` |
| Puerto | `3306` |
| Base | `sigeru` |
| Usuario | `root` |
| ContraseÃ±a | vacÃ­a |

Se pueden cambiar con las variables:

```bash
SIGERU_DB_HOST
SIGERU_DB_PORT
SIGERU_DB_NAME
SIGERU_DB_USER
SIGERU_DB_PASSWORD
```

Por ejemplo:

```bash
export SIGERU_DB_HOST="localhost"
export SIGERU_DB_PORT="3306"
export SIGERU_DB_NAME="sigeru"
export SIGERU_DB_USER="root"
export SIGERU_DB_PASSWORD=""
```

## 3. Iniciar la aplicaciÃ³n

La aplicaciÃ³n utiliza PHP 8 con la extensiÃ³n `mysqli`.

En Linux, el ejecutable de PHP incluido con XAMPP normalmente es:

```bash
/opt/lampp/bin/php
```

Se pueden iniciar los tres servidores manualmente:

### API de usuarios

```bash
/opt/lampp/bin/php -S localhost:8091 api-usuarios/index.php
```

### API de gestiÃ³n

```bash
/opt/lampp/bin/php -S localhost:8092 api-gestion/index.php
```

### Frontend

```bash
/opt/lampp/bin/php -S localhost:8090 -t frontend
```

Cada comando debe ejecutarse en una terminal distinta.

DespuÃ©s abrir:

```text
http://localhost:8090
```

## 4. Inicio automÃ¡tico con `run.sh`

Para evitar abrir tres terminales, se incluye el script:

```bash
./run.sh
```

Si el sistema no permite ejecutarlo todavÃ­a:

```bash
chmod +x run.sh
./run.sh
```

El script:

1. comprueba que exista PHP de XAMPP;
2. comprueba que MySQL estÃ© disponible;
3. crea la base de datos usando `database/ddl.sql`;
4. carga los datos de prueba;
5. inicia las dos APIs;
6. inicia el frontend;
7. mantiene los tres servidores ejecutÃ¡ndose;
8. detiene los procesos al pulsar `Ctrl+C`.

## Cuenta de demostraciÃ³n

- correo: `admin@sigeru.local`
- contraseÃ±a: `admin123`

## Endpoints principales

### API de usuarios - puerto 8091

- `POST /registro`
- `POST /login`
- `POST /logout`
- `GET /sesion`
- `GET|POST /usuarios`
- `PUT|DELETE /usuarios/{id}`

### API de gestiÃ³n - puerto 8092

- `GET /contenedores-publicos`
- `GET|POST /contenedores`
- `PUT|DELETE /contenedores/{id}`
- `GET|POST /camiones`
- `PUT|DELETE /camiones/{id}`
- `GET|POST /incidencias`
- `DELETE /incidencias/{id}`
