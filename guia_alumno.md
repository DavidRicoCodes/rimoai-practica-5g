# Práctica de laboratorio: despliegue y diagnóstico de una red 5G SA emulada

## Obtener el material

La versión oficial de la práctica se distribuye mediante el tag `practica-5g-v1.0.0` de un
repositorio público. En una máquina que todavía no tenga Git:

```bash
sudo apt-get update
sudo apt-get install -y git

git clone --depth 1 \
  --branch practica-5g-v1.0.0 \
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

Si el profesor proporciona el archivo alternativo `rimoai-practica-5g-v1.0.0.tar.gz`,
descarga también su fichero `.sha256` y ejecuta:

```bash
sha256sum -c rimoai-practica-5g-v1.0.0.tar.gz.sha256
tar -xzf rimoai-practica-5g-v1.0.0.tar.gz -C ~
cd ~/RIMoai
./setup_inicial.sh
export PRACTICA_DIR="$PWD"
```

No continúes si la verificación SHA-256 falla.

## 1. Introducción

En esta práctica desplegarás una red 5G Standalone completa sobre una única máquina Ubuntu:

- Open5GS proporcionará el core 5G.
- OCUDU actuará como gNB.
- OpenAirInterface actuará como un UE emulado.
- ZeroMQ transportará las muestras de radio sin utilizar hardware RF.

El material inicial contiene configuraciones coherentes desde el punto de vista sintáctico, pero
no describe todavía la red requerida. Tu tarea es diagnosticar cada etapa, relacionar los
parámetros distribuidos entre core, gNB y UE y conseguir conectividad extremo a extremo.

No se busca únicamente alcanzar el resultado final. Durante la demostración deberás explicar
qué subsistema intervenía en cada fallo y qué evidencia permitió localizarlo.

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

## 5. Preparación del puesto

### 5.1. Requisitos

- Ubuntu 22.04 x86-64.
- Usuario con acceso a `sudo`.
- Acceso a Internet durante la instalación y el primer build.
- Al menos 12 GB de RAM recomendados.
- Cuatro núcleos de CPU como mínimo recomendado.
- Tres terminales o sesiones `screen`.

No ejecutes simultáneamente varias copias de la práctica: compartirían nombres, interfaces,
direcciones y puertos.

### 5.2. Directorio de trabajo

Todos los comandos parten de la raíz del repositorio clonado:

```bash
cd ~/RIMoai
export PRACTICA_DIR="$PWD"
```

Mantén esta variable en cada terminal nueva.

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
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

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

### 5.5. Comprobación del material

```bash
"$PRACTICA_DIR/scripts/check_material.sh"
```

Este script comprueba que los fuentes, parches y elementos no evaluados siguen íntegros. No
comprueba que hayas resuelto la práctica y no identifica valores correctos de los ejercicios.

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

Comprobación:

```bash
test -x "$PRACTICA_DIR/ran/ocudu/build/apps/gnb/gnb"
ldd "$PRACTICA_DIR/ran/ocudu/build/apps/gnb/gnb" | grep libzmq
```

### 5.7. Build del OAI UE

```bash
cd "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets"
./build_oai -I -w ZMQ
./build_oai --nrUE -w ZMQ --ninja
cd "$PRACTICA_DIR"
```

Comprobación:

```bash
test -x "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem"
test -f "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets/ran_build/build/liboai_zmqdevif.so"
```

## 6. Ejecución de los componentes

La práctica utiliza tres terminales. Puedes usar `screen`; para separar una sesión pulsa
`Ctrl+A` y después `D`, y para recuperarla utiliza `screen -r NOMBRE`.

### Terminal 1: core Open5GS

```bash
cd "$PRACTICA_DIR/core"
docker compose config
docker compose up --build 5gc
```

### Terminal 2: gNB OCUDU

```bash
cd "$PRACTICA_DIR"
sudo ./ran/ocudu/build/apps/gnb/gnb -c ./ran/gnb_zmq.yaml
```

### Terminal 3: OAI UE

Arranca el UE únicamente cuando el gNB haya completado su inicialización:

```bash
cd "$PRACTICA_DIR"
sudo ./ue/openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem \
  -O ./ue/oaiue_zmq.conf
```

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
