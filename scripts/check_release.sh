#!/usr/bin/env bash

set -euo pipefail

PRACTICA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_MODE=false

case "${1:-}" in
  "") ;;
  --source) SOURCE_MODE=true ;;
  --help|-h)
    printf '%s\n' 'Uso: scripts/check_release.sh [--source]'
    exit 0
    ;;
  *) printf 'Argumento desconocido: %s\n' "$1" >&2; exit 2 ;;
esac

fail()
{
  printf 'ERROR de distribución: %s\n' "$1" >&2
  exit 1
}

for required in \
  README.md guia_alumno.md setup_inicial.sh reset.sh .gitignore .gitattributes \
  scripts/check_material.sh core/docker-compose.yml core/open5gs/open5gs.env \
  ran/gnb_zmq.yaml ue/oaiue_zmq.conf patches/ocudu-local-fixes.patch
do
  [[ -e "$PRACTICA_DIR/$required" ]] || fail "falta $required"
done

for forbidden in profesor varios student deployment.md; do
  [[ ! -e "$PRACTICA_DIR/$forbidden" ]] || fail "aparece contenido prohibido: $forbidden"
done

for pair in \
  'core/docker-compose.yml base/core/docker-compose.yml' \
  'core/open5gs/open5gs.env base/core/open5gs/open5gs.env' \
  'ran/gnb_zmq.yaml base/ran/gnb_zmq.yaml' \
  'ue/oaiue_zmq.conf base/ue/oaiue_zmq.conf' \
  'guia_alumno.md base/guia_alumno.md' \
  'scripts/check_material.sh base/scripts/check_material.sh'
do
  set -- $pair
  cmp -s "$PRACTICA_DIR/$1" "$PRACTICA_DIR/.reset/$2" \
    || fail "el estado activo no coincide con el baseline degradado: $1"
done

(
  cd "$PRACTICA_DIR/.reset"
  sha256sum -c manifest.sha256 --status
) || fail 'el baseline de reset no supera su manifiesto'

[[ -x "$PRACTICA_DIR/setup_inicial.sh" ]] || fail 'setup_inicial.sh no es ejecutable'
[[ -x "$PRACTICA_DIR/reset.sh" ]] || fail 'reset.sh no es ejecutable'
[[ -x "$PRACTICA_DIR/scripts/check_material.sh" ]] || fail 'check_material.sh no es ejecutable'
[[ -x "$PRACTICA_DIR/scripts/check_release.sh" ]] || fail 'check_release.sh no es ejecutable'
[[ -x "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets/build_oai" ]] \
  || fail 'falta el ejecutable de build del UE'

for guide in \
  "$PRACTICA_DIR/guia_alumno.md" \
  "$PRACTICA_DIR/.reset/base/guia_alumno.md"
do
  ! grep -Fq './build_oai -I -w ZMQ' "$guide" \
    || fail 'una guía conserva la secuencia OAI incompatible con Ninja'
  grep -Fq './build_oai -I' "$guide" \
    || fail 'falta la instalación de dependencias OAI corregida'
  grep -Fq './build_oai --nrUE -w ZMQ --ninja' "$guide" \
    || fail 'falta el build OAI con Ninja'
done

grep -Eq '^[[:space:]]*ipv4_address:[[:space:]]*10\.54\.1\.2([[:space:]]|$)' \
  "$PRACTICA_DIR/core/docker-compose.yml" \
  || fail 'el contenedor no conserva el decoy de red esperado'
grep -Eq '^[[:space:]-]*subnet:[[:space:]]*10\.54\.1\.0/24([[:space:]]|$)' \
  "$PRACTICA_DIR/core/docker-compose.yml" \
  || fail 'la subred no conserva el decoy esperado'
grep -Fxq 'OPEN5GS_IP=10.55.1.2' "$PRACTICA_DIR/core/open5gs/open5gs.env" \
  || fail 'OPEN5GS_IP no conserva el decoy incoherente esperado'
grep -Fxq 'UPF_ADVERTISE_IP=10.56.1.2' "$PRACTICA_DIR/core/open5gs/open5gs.env" \
  || fail 'UPF_ADVERTISE_IP no conserva el decoy incoherente esperado'

[[ -L "$PRACTICA_DIR/ran/ocudu/cmake/modules/FindBackward.cmake" ]] \
  || fail 'se ha perdido un enlace simbólico de OCUDU'
[[ -L "$PRACTICA_DIR/ran/ocudu/LICENSES/BSD-3-Clause-Open-MPI.txt" ]] \
  || fail 'se ha perdido un enlace simbólico de licencias'

if [[ "$SOURCE_MODE" != true ]]; then
  [[ ! -e "$PRACTICA_DIR/ran/ocudu/build" ]] || fail 'el release contiene el build de OCUDU'
  [[ ! -e "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets/ran_build" ]] \
    || fail 'el release contiene el build del UE'
  [[ ! -e "$PRACTICA_DIR/core/open5gs/subscriber_db.csv" ]] \
    || fail 'el release contiene un CSV generado'

  if find "$PRACTICA_DIR" -type f \( -name '*.log' -o -name '*.pcap' \) -print -quit | grep -q .; then
    fail 'el release contiene logs o PCAP'
  fi

  if grep -Eq '@@(REPO_URL|RELEASE_TAG)@@|github\.com/OWNER/' \
    "$PRACTICA_DIR/README.md" \
    "$PRACTICA_DIR/guia_alumno.md" \
    "$PRACTICA_DIR/.reset/base/guia_alumno.md" \
    "$PRACTICA_DIR/setup_inicial.sh"; then
    fail 'quedan marcadores de URL o versión sin renderizar'
  fi

  oversized="$(find "$PRACTICA_DIR" -type f -size +100M -print -quit)"
  [[ -z "$oversized" ]] || fail "hay un archivo mayor de 100 MiB: $oversized"
fi

"$PRACTICA_DIR/scripts/check_material.sh"
printf '%s\n' 'OK: la distribución está degradada, íntegra y libre de contenido docente.'
