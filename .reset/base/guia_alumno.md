# Práctica de laboratorio: despliegue y diagnóstico de una red 5G SA emulada

## Obtener el material

La versión oficial de la práctica se distribuye mediante el tag `practica-5g-v1.1.0` de un
repositorio público. En una máquina que todavía no tenga Git:

```bash
sudo apt-get update
sudo apt-get install -y git

git clone --depth 1 \
  --branch practica-5g-v1.1.0 \
  https://github.com/DavidRicoCodes/rimoai-practica-5g.git \
  ~/RIMoai

cd ~/RIMoai
./setup_inicial.sh
export PRACTICA_DIR="$PWD"
```

`setup_inicial.sh` restaura automáticamente el estado degradado inicial y verifica la integridad
del material. No instala dependencias ni compila los componentes. No vuelvas a ejecutarlo cuando
hayas empezado a resolver la práctica: una segunda ejecución se bloquea para evitar pérdidas y
`--force` descarta deliberadamente el progreso.

No utilices `git pull` durante la práctica. Las actualizaciones se publicarán con un tag nuevo y
se instalarán mediante una clonación limpia.

Si el profesor proporciona el archivo alternativo `rimoai-practica-5g-v1.1.0.tar.gz`,
descarga también su fichero `.sha256` y ejecuta:

```bash
sha256sum -c rimoai-practica-5g-v1.1.0.tar.gz.sha256
tar -xzf rimoai-practica-5g-v1.1.0.tar.gz -C ~
cd ~/RIMoai
./setup_inicial.sh
export PRACTICA_DIR="$PWD"
```

No continúes si la verificación SHA-256 falla.

## 1. Introducción

En esta práctica construirás una red 5G **Standalone (SA)** completa sobre una única máquina
Ubuntu. *Standalone* significa que el acceso radio 5G se conecta a un core 5G nativo: no se
utiliza una red 4G como apoyo. El resultado final será un UE registrado, autenticado y con una
sesión de datos capaz de transportar tráfico IP hasta el core.

La red estará formada por cuatro piezas:

- **Open5GS** proporcionará las funciones del core 5G.
- **OCUDU** actuará como gNB, la estación base de la red 5G.
- **OpenAirInterface (OAI)** actuará como un UE emulado.
- **ZeroMQ (ZMQ)** transportará las muestras de radio entre gNB y UE sin utilizar antenas ni
  hardware RF.

El material inicial contiene configuraciones coherentes desde el punto de vista sintáctico, pero
no describe todavía la red requerida y algunos componentes no podrán arrancar correctamente.
Tu tarea es diagnosticar cada etapa, relacionar los parámetros distribuidos entre core, gNB y UE
y conseguir conectividad extremo a extremo.

No se busca únicamente alcanzar el resultado final. Durante la demostración deberás explicar
qué subsistema intervenía en cada fallo y qué evidencia permitió localizarlo.

### 1.1. Planos de control y de usuario

El **plano de control** reúne los procedimientos necesarios para que la red conozca al UE y le
autorice el servicio: selección de red, señalización RRC, registro NAS, autenticación y creación
de contexto. El **plano de usuario** transporta los paquetes IP una vez establecida la sesión
PDU. Que el registro termine correctamente no implica que el plano de usuario esté disponible.

En el core intervienen principalmente:

- **AMF:** termina la señalización N2/NGAP del gNB y gestiona movilidad y registro.
- **AUSF y UDM:** participan en la autenticación y en la obtención de datos del abonado.
- **SMF:** crea y controla la sesión PDU solicitada por el UE.
- **UPF:** reenvía el tráfico del plano de usuario mediante GTP-U.

Open5GS incluye además otras funciones auxiliares. Sus direcciones internas de loopback no son
el objeto de la práctica.

### 1.2. Del encendido al ping

El recorrido que observarás es el siguiente:

```text
core disponible
      ↓
N2 y NG Setup entre gNB y AMF
      ↓
radio virtual ZMQ y sincronización del UE
      ↓
RRC + NAS: identificación, autenticación y registro
      ↓
solicitud de DNN y establecimiento de sesión PDU
      ↓
interfaz oaitun_ue1 y tráfico IP
```

NAS transporta la señalización del UE con el core; RRC controla la conexión radio; NGAP lleva
por N2 la señalización entre gNB y AMF; y GTP-U lleva por N3 el tráfico del usuario entre gNB y
UPF. En este laboratorio la radio física se sustituye por dos flujos TCP/ZMQ, pero los
procedimientos 5G superiores siguen siendo reales.

Compilar correctamente solo demuestra que se pueden construir los ejecutables. No demuestra
que sus identidades, direcciones, credenciales o redes de datos sean coherentes. Esa separación
entre problema de software y problema de configuración es parte central de la práctica.

## 2. Objetivos

Al finalizar la práctica deberás ser capaz de:

1. Distinguir las direcciones del contenedor, del bridge del host y del UE.
2. Reconocer el establecimiento de N2 entre el gNB y el AMF.
3. Mantener coherentes PLMN e identidad del abonado.
4. Configurar un enlace radio virtual mediante dos canales TCP/ZMQ.
5. Diferenciar sincronización radio, registro 5G y establecimiento de sesión PDU.
6. Provisionar un abonado mediante un procedimiento interactivo o reproducible.
7. Validar el plano de usuario mediante una interfaz TUN y tráfico IP.

## 3. Arquitectura de trabajo

```text
┌──────────────┐       radio virtual ZMQ       ┌──────────────┐
│    OAI UE    │◄─────────────────────────────►│  OCUDU gNB   │
└──────┬───────┘                               └──────┬───────┘
       │                                              │
       │ NAS / RRC                                    │ N2 / NGAP
       │                                              │ N3 / GTP-U
       │                                              ▼
       │                                       ┌──────────────┐
       └──────────── sesión PDU ──────────────►│   Open5GS   │
                                               └──────────────┘
```

Open5GS se ejecuta en Docker. El gNB y el UE se ejecutan directamente en el host. No modifiques
las direcciones internas `127.0.0.x` de las funciones de Open5GS ni el código fuente de OCUDU u
OAI.

Docker aísla el core en una red virtual. El host participa en ella mediante un bridge, mientras
que el gNB utiliza ese bridge para alcanzar N2 y N3. Cuando Open5GS acepta la sesión PDU, OAI
crea `oaitun_ue1`: esa interfaz representa en Linux la conectividad IP recibida por el UE.

## 4. Requisitos finales de la red

Los valores finales no son secretos. El reto consiste en decidir qué componentes deben conocer
cada dato y demostrar por qué.

| Parámetro | Requisito |
| --- | --- |
| Red Docker | `10.53.1.0/24` |
| Core Open5GS | `10.53.1.2` |
| Bridge Docker del host | `10.53.1.1` |
| Espacio de usuarios del laboratorio | `10.45.0.0/16` |
| Dirección asignada al UE | `10.45.1.2` |
| PLMN | `00101` |
| MCC / MNC | `001` / `01` |
| TAC | `7` |
| Slice | SST `1`, sin SD |
| DNN | `internet` |
| IMSI | `001010123456780` |
| Ki | `00112233445566778899aabbccddeeff` |
| OPc | `63bfa50ee6523365ff14c1f45f88737d` |
| AMF de autenticación | `8000` |
| IP del abonado | `10.45.1.2` |
| N2 | SCTP `38412` |
| N3 | UDP `2152` |
| Radio virtual descendente | TCP `4556` |
| Radio virtual ascendente | TCP `4557` |
| Banda / ancho / SCS | n78 / 20 MHz / 30 kHz |
| Frecuencia DL/UL | `3489420000 Hz` |

El puerto del host utilizado para acceder a la WebUI no está fijado: si eliges ese método de
alta, debes seleccionar uno libre, justificar la elección y publicar correctamente el servicio
del contenedor.

La variable no evaluada `UE_IP_BASE=10.45.0` es una base utilizada por los scripts del core; no
es la dirección final del UE y no debe convertirse en `10.45.1`. El laboratorio agrega como
espacio de usuarios `10.45.0.0/16`, dentro del cual el perfil del abonado asignará
`10.45.1.2`. Esa dirección no se configura directamente en la interfaz TUN: aparecerá cuando la
sesión PDU sea aceptada.

## 5. Preparación del puesto

### 5.1. Requisitos

- Ubuntu 22.04 x86-64.
- Usuario con acceso a `sudo`.
- Acceso a Internet durante la instalación y el primer build.
- Al menos 12 GB de RAM recomendados.
- Ocho vCPU recomendadas en una máquina virtual; cuatro son el mínimo y pueden resultar justas
  según el rendimiento del host.
- Tres terminales o sesiones `screen`.

No ejecutes simultáneamente varias copias de la práctica: compartirían nombres, interfaces,
direcciones y puertos.

### 5.2. Directorio de trabajo

Todos los comandos parten de la raíz del repositorio clonado:

```bash
cd ~/RIMoai
export PRACTICA_DIR="$PWD"
```

`PRACTICA_DIR` guarda la ruta absoluta de la copia que estás utilizando. Los comandos posteriores
la emplean para no depender del directorio desde el que se ejecuten. Las variables exportadas no
se heredan al abrir una terminal nueva, por lo que debes repetir estas dos órdenes en cada una.

### 5.3. Docker y Compose

Si estos dos comandos funcionan, no reinstales Docker:

```bash
docker --version
docker compose version
```

En una instalación limpia de Ubuntu 22.04:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL \
  https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo mv \
  /etc/apt/sources.list.d/docker.list \
  /etc/apt/sources.list.d/docker.list.disabled \
  2>/dev/null || true

sudo tee \
  /etc/apt/sources.list.d/docker.sources \
  >/dev/null <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: jammy
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

Este bloque utiliza el formato Deb822, con un dato por línea, para que las líneas visuales de un
PDF no puedan partir la entrada de Docker. Si existe un `docker.list` de un intento anterior, se
conserva como `docker.list.disabled` y deja de bloquear APT.

Docker Engine ejecutará el contenedor del core. El plugin Compose interpreta
`core/docker-compose.yml` para construir la imagen, crear la red virtual, asignar la dirección
del contenedor y aplicar sus variables de entorno. Instalar Docker no arranca todavía la red 5G.

Si quieres utilizar Docker sin `sudo`, añade tu usuario al grupo y vuelve a iniciar sesión:

```bash
sudo usermod -aG docker "$USER"
```

### 5.4. Dependencias de OCUDU

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential cmake ninja-build pkg-config screen git \
  libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev \
  libgtest-dev libzmq3-dev libboost-program-options-dev
```

Estas bibliotecas permiten compilar OCUDU con FFT, SCTP, YAML y ZMQ. SCTP se utiliza en N2 y
ZMQ sustituye el dispositivo de radio. `ninja-build` se instala también porque será el generador
empleado al construir OAI.

### 5.5. Comprobación del material

```bash
"$PRACTICA_DIR/scripts/check_material.sh"
```

Este script comprueba que los fuentes, parches y elementos no evaluados siguen íntegros. No
comprueba que hayas resuelto la práctica y no identifica valores correctos de los ejercicios.
Un resultado `OK` significa que el material se puede utilizar; no significa que core, gNB y UE
estén configurados de forma coherente.

### 5.6. Build de OCUDU

```bash
cmake -S "$PRACTICA_DIR/ran/ocudu" \
      -B "$PRACTICA_DIR/ran/ocudu/build" \
      -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_EXPORT=ON \
      -DENABLE_ZEROMQ=ON \
      -DENABLE_UHD=OFF

cmake --build "$PRACTICA_DIR/ran/ocudu/build" \
      --target gnb -j"$(nproc)"
```

La primera orden **configura** el proyecto y genera el sistema de build; la segunda lo
**compila**. Las opciones significan:

- `Release`: activa optimización y evita instrumentación de depuración innecesaria.
- `ENABLE_EXPORT=ON`: genera los componentes exportables requeridos por el proyecto.
- `ENABLE_ZEROMQ=ON`: incluye el frontend de radio virtual.
- `ENABLE_UHD=OFF`: evita depender de hardware USRP que no se utilizará.
- `--target gnb`: limita la compilación al ejecutable de la estación base.
- `-j"$(nproc)"`: permite tantos trabajos paralelos como CPU lógicas detectadas.

Comprobación:

```bash
test -x "$PRACTICA_DIR/ran/ocudu/build/apps/gnb/gnb"
ldd "$PRACTICA_DIR/ran/ocudu/build/apps/gnb/gnb" | grep libzmq
```

`test -x` comprueba que existe un binario ejecutable. `ldd` muestra sus bibliotecas dinámicas;
la aparición de `libzmq` confirma que el soporte de radio virtual quedó enlazado.

### 5.7. Build del OAI UE

```bash
cd "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets"
./build_oai -I
./build_oai --nrUE -w ZMQ --ninja
cd "$PRACTICA_DIR"
```

OpenAirInterface es una implementación software de protocolos de acceso radio. Aquí solo se
construye su UE 5G, cuyo ejecutable es `nr-uesoftmodem`:

- `-I` instala las dependencias externas que OAI necesita, pero no configura el build del UE.
- `--nrUE` selecciona el UE New Radio.
- `-w ZMQ` incorpora el dispositivo de radio ZMQ y genera `liboai_zmqdevif.so`.
- `--ninja` utiliza Ninja como generador desde la primera configuración del UE.

No añadas `-w ZMQ` al primer comando: hacerlo configuraría prematuramente el mismo directorio
con el generador predeterminado y después CMake rechazaría el cambio a Ninja.

Comprobación:

```bash
OAI_DIR="$PRACTICA_DIR/ue/openairinterface5g"
UE_BUILD="$OAI_DIR/cmake_targets/ran_build/build"
test -x "$UE_BUILD/nr-uesoftmodem"
test -f "$UE_BUILD/liboai_zmqdevif.so"
```

El primer test valida el softmodem del UE y el segundo su interfaz de radio. Puedes confirmar el
enlace ZMQ con:

```bash
ldd "$UE_BUILD/liboai_zmqdevif.so" | grep libzmq
```

Si una ejecución anterior dejó el error `Does not match the generator used previously`, limpia
únicamente el build generado por OAI y vuelve a compilar:

```bash
cd "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets"
./build_oai --clean-all --nrUE -w ZMQ --ninja
cd "$PRACTICA_DIR"
```

`--clean-all` elimina el árbol de compilación de OAI; no borra las configuraciones de la
práctica.

## 6. Ejecución de los componentes

La práctica utiliza tres terminales. Puedes usar `screen`; para separar una sesión pulsa
`Ctrl+A` y después `D`, y para recuperarla utiliza `screen -r NOMBRE`.

Los tres procesos permanecen activos y producen logs simultáneamente. Separarlos permite
observar en qué componente aparece cada evento y detener gNB o UE sin cerrar el core.

### Terminal 1: core Open5GS

```bash
cd "$PRACTICA_DIR/core"
docker compose config
docker compose up --build 5gc
```

`docker compose config` valida y muestra la configuración efectiva sin resolver por ti su
coherencia con los requisitos. `up --build 5gc` construye la imagen si es necesario y mantiene
el core en primer plano para que puedas observar sus logs.

### Terminal 2: gNB OCUDU

```bash
cd "$PRACTICA_DIR"
sudo ./ran/ocudu/build/apps/gnb/gnb -c ./ran/gnb_zmq.yaml
```

La opción `-c` indica al gNB qué configuración cargar. Se usa `sudo` porque el gNB debe crear y
enlazar recursos de red del host, incluido N3/UDP.

### Terminal 3: OAI UE

Arranca el UE únicamente cuando el gNB haya completado su inicialización:

```bash
cd "$PRACTICA_DIR"
OAI_DIR="$PRACTICA_DIR/ue/openairinterface5g"
UE_BUILD="$OAI_DIR/cmake_targets/ran_build/build"
sudo "$UE_BUILD/nr-uesoftmodem" \
  -O ./ue/oaiue_zmq.conf
```

La opción `-O` entrega al softmodem la configuración del UE. El gNB debe estar preparado antes
porque el UE comienza inmediatamente a buscar la señal virtual y a ejecutar los procedimientos
de acceso. En las repeticiones, detén ambos extremos y conserva el orden gNB → UE al arrancar.

No corrijas todos los parámetros antes de ejecutar. La observación de los estados intermedios
forma parte de la práctica.

## 7. Desarrollo por hitos

### Hito 1. Inspección de arquitectura

Antes de arrancar el UE, construye un esquema propio que relacione:

- Red Docker, contenedor y bridge del host.
- Extremos de N2 y N3.
- Identidad de red e identidad del abonado.
- Sentidos de transmisión y recepción del enlace virtual.

Debes poder justificar cada relación usando la arquitectura 5G y la configuración disponible.

### Hito 2. Core saludable y topología correcta

Consigue que Open5GS arranque con la red Docker requerida. Demuestra:

- Estado `healthy`.
- Dirección del contenedor.
- Dirección del bridge del host.
- Coherencia de la identidad de red anunciada por el core.

La evidencia solo será válida si muestra exactamente la subred `10.53.1.0/24`, el contenedor
`10.53.1.2` y el bridge `10.53.1.1`. Una red privada distinta puede ser técnicamente coherente,
pero no cumple la topología requerida por este laboratorio.

El estado saludable no implica que el gNB pueda conectarse todavía.

### Hito 3. N2 y NG Setup

Arranca el gNB y observa primero el fallo inicial. Después consigue:

- Que el gNB pueda usar una dirección local existente.
- Que establezca la asociación con el AMF.
- Que el NG Setup sea aceptado para la red requerida.

Conserva una evidencia breve del fallo y otra del resultado correcto.

### Hito 4. Sincronización radio mediante ZMQ

Arranca el UE con el estado inicial del enlace virtual y observa el resultado. Consigue después
que ambos extremos utilicen los canales requeridos y que el UE encuentre la celda.

Debes demostrar la correspondencia entre los dos flujos TCP y explicar su sentido. Cuando
cambies la radio virtual, detén UE y gNB y vuelve a arrancarlos en ese orden: primero gNB y luego
UE.

### Hito 5. UE no registrado en el core

Haz que el UE utilice la identidad final requerida, pero no des todavía de alta ese abonado.
Observa cómo alcanza el core y cómo se rechaza o interrumpe el procedimiento por no existir el
perfil.

Debes explicar por qué en esta etapa todavía no se pueden validar Ki y OPc.

### Hito 6. Alta del abonado

Provisiona el abonado final eligiendo una de estas rutas:

1. **WebUI:** publica la interfaz en un puerto libre del host y crea el perfil de forma
   interactiva. Credenciales de acceso: `admin` / `1423`.
2. **Script Python incluido:** realiza un alta puntual utilizando `add_users.py` y su ayuda.
3. **CSV declarativo:** parte del ejemplo incluido y configura el arranque para importar tu
   fichero.

El argumento puntual de `add_users.py` utiliza este esquema genérico:

```text
IMSI,Ki,tipo_OP,OP_u_OPc,AMF,QCI,IPv4
```

El CSV emplea las mismas columnas precedidas por un nombre descriptivo del UE:

```text
nombre,IMSI,Ki,tipo_OP,OP_u_OPc,AMF,QCI,IPv4
```

`tipo_OP` indica si el campo siguiente contiene OP u OPc; QCI selecciona la clase de QoS del
perfil y la IPv4 es la dirección estática que el core asignará durante la sesión. Estos esquemas
no sustituyen la decisión de qué valores debe tener el abonado ni cómo invocar el método elegido.

Debes justificar la ruta elegida y comprobar que el core contiene el IMSI, seguridad, slice,
DNN e IP exigidos.

MongoDB es efímero. `stop/start` conserva el perfil, mientras que eliminar o recrear el
contenedor pierde las altas interactivas o puntuales. El método CSV puede volver a importarlas
durante un nuevo arranque.

### Hito 7. Fallo de autenticación

Mantén temporalmente en el UE las credenciales iniciales incorrectas después de provisionar el
abonado correcto. Reinicia gNB y UE y conserva una evidencia del fallo de autenticación.

Explica la diferencia entre este resultado y el del hito anterior: ahora el abonado existe, pero
la respuesta criptográfica no puede validarse.

### Hito 8. Registro correcto

Sincroniza las credenciales del UE y del abonado. Mantén todavía la red de datos inicial del UE.
Consigue completar autenticación y registro 5G.

Demuestra que un registro correcto no garantiza por sí solo la existencia de una sesión de datos.

### Hito 9. Registro sin sesión PDU

Observa el intento de sesión con la red de datos inicial. Debes demostrar simultáneamente:

- Registro 5G correcto.
- Sesión PDU ausente o rechazada.
- Ausencia de una interfaz TUN funcional con la dirección final.

Relaciona el resultado con la suscripción que existe en el core.

### Hito 10. Sesión PDU y conectividad

Solicita la DNN requerida y reinicia gNB y UE. El resultado final debe cumplir:

```bash
ip addr show oaitun_ue1
ping -I 10.45.1.2 10.53.1.2 -c 3
```

Debes obtener `oaitun_ue1` con `10.45.1.2` y tres respuestas ICMP.
Un ping correcto dirigido a cualquier otra dirección del core no satisface este hito.

## 8. Método de trabajo y diagnóstico

Cuando un componente falle:

1. Identifica el último hito completado.
2. Decide si el fallo pertenece al core, N2, radio, registro o sesión PDU.
3. Observa procesos, interfaces, sockets y logs del componente implicado.
4. Formula una hipótesis antes de editar.
5. Cambia un único concepto y repite la prueba.

No trates como fatal el aviso repetido de OAI sobre manejo de CSI-RS para tracking. Sí debes
investigar violaciones de segmento, errores de bind, puertos ocupados y cierres inesperados.

## 9. Apagado y recuperación

### Apagado ordenado

1. Detén el UE con `Ctrl+C` y espera su cierre.
2. Detén el gNB con `Ctrl+C`.
3. Detén el core:

   ```bash
   docker compose -f "$PRACTICA_DIR/core/docker-compose.yml" down --remove-orphans
   ```

### Volver al estado inicial

Desde la raíz de la práctica:

```bash
./reset.sh
```

El reset solicita confirmación, detiene exclusivamente los componentes de esta práctica,
elimina el contenedor, la base efímera, la interfaz TUN y el CSV generado, y restaura las
configuraciones degradadas iniciales. Conserva fuentes y builds.

Para omitir la confirmación:

```bash
./reset.sh --yes
```

El reset no recupera cambios arbitrarios dentro de los fuentes OCUDU/OAI ni puede repararse a sí
mismo si se modifica `.reset`. En esos casos solicita una copia limpia al profesor.

## 10. Demostración final

La evaluación se realizará en el aula. No se exige memoria ni entrega de configuraciones. Cada
grupo deberá mostrar y explicar:

- Core saludable, dirección del contenedor y bridge.
- NG Setup correcto.
- Correspondencia del transporte ZMQ y sincronización radio.
- Evidencia del IMSI no provisionado.
- Método elegido para el alta y perfil final del abonado.
- Diferencia entre abonado desconocido y fallo de autenticación.
- Registro correcto sin sesión PDU para la DNN inicial.
- Sesión PDU final, interfaz `oaitun_ue1` y ping 3/3.

El profesor puede pedir que repitas cualquier comprobación o que expliques qué interfaz o plano
de la arquitectura interviene.

### Rúbrica resumida

| Bloque | Peso |
| --- | ---: |
| Core y topología IP | 15 % |
| N2 y coherencia de PLMN | 15 % |
| ZMQ y sincronización | 15 % |
| Abonado y autenticación | 20 % |
| Sesión PDU y DNN | 15 % |
| TUN y conectividad | 15 % |
| Explicación y diagnóstico | 5 % |
| **Total** | **100 %** |

Mostrar únicamente una configuración final funcional no demuestra la resolución de los hitos.
