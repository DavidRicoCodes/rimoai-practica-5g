# Práctica 5G SA emulada

Material del alumno para desplegar y diagnosticar una red 5G Standalone formada por Open5GS,
OCUDU, OpenAirInterface y ZeroMQ.

Este repositorio contiene únicamente la versión degradada de la práctica. No incluye la solución
docente ni builds precompilados.

## Inicio rápido

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

Continúa con [`guia_alumno.md`](guia_alumno.md). La versión oficial de esta distribución es
`practica-5g-v1.1.0`.

No utilices `git pull` durante la resolución. Una actualización de la práctica se publicará con
un tag distinto y se realizará mediante una clonación limpia.

Los componentes de terceros conservan sus licencias y avisos originales dentro de sus
respectivos árboles.
