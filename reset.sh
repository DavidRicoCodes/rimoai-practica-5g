#!/usr/bin/env bash

set -euo pipefail

PRACTICA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESET_DIR="$PRACTICA_DIR/.reset"
BASE_DIR="$RESET_DIR/base"
MANIFEST="$RESET_DIR/manifest.sha256"
ASSUME_YES=false

usage()
{
  cat <<'EOF'
Uso: ./reset.sh [--yes]

Restaura el material inicial degradado y limpia el runtime de esta práctica.
  --yes, -y   omite la confirmación interactiva
  --help, -h  muestra esta ayuda
EOF
}

case "${1:-}" in
  "") ;;
  --yes|-y) ASSUME_YES=true ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

[[ $# -le 1 ]] || { usage >&2; exit 2; }
[[ -f "$MANIFEST" ]] || {
  printf 'ERROR: falta el manifiesto protegido de reset. Solicita una copia limpia.\n' >&2
  exit 1
}

if ! (cd "$RESET_DIR" && sha256sum -c manifest.sha256 --status); then
  printf 'ERROR: la copia protegida de reset ha sido modificada. Solicita una copia limpia.\n' >&2
  exit 1
fi

printf '%s\n' \
  'Este reset realizará las siguientes acciones:' \
  '  - detener el gNB y el UE de esta copia, si están activos;' \
  '  - eliminar el contenedor open5gs_5gc y su base de datos efímera;' \
  '  - eliminar la interfaz oaitun_ue1 y los logs/PCAP del gNB;' \
  '  - eliminar el CSV de abonados generado durante la práctica;' \
  '  - restaurar configuraciones, guía y verificador al estado degradado inicial;' \
  '  - conservar fuentes, parches, imágenes Docker y builds.'

if [[ "$ASSUME_YES" != true ]]; then
  printf 'Escribe RESTABLECER para continuar: '
  read -r confirmation
  if [[ "$confirmation" != "RESTABLECER" ]]; then
    printf 'Reset cancelado.\n'
    exit 0
  fi
fi

as_root()
{
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

exact_pids_for_executable()
{
  local expected="$1"
  local process_name
  local pid
  local actual
  process_name="$(basename "$expected")"

  while read -r pid; do
    [[ -n "$pid" ]] || continue
    actual="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
    if [[ -z "$actual" ]]; then
      actual="$(as_root readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
    fi
    [[ "$actual" == "$expected" ]] && printf '%s\n' "$pid"
  done < <(pgrep -f "$process_name" 2>/dev/null || true)
}

stop_exact_executable()
{
  local executable="$1"
  local label="$2"
  local -a pids=()
  local -a remaining=()
  local attempt
  local pid

  [[ -e "$executable" ]] || return 0
  mapfile -t pids < <(exact_pids_for_executable "$(readlink -f "$executable")")
  ((${#pids[@]} > 0)) || return 0

  printf 'Deteniendo %s (PID: %s)...\n' "$label" "${pids[*]}"
  as_root kill -INT "${pids[@]}"

  for attempt in {1..50}; do
    remaining=()
    for pid in "${pids[@]}"; do
      if as_root kill -0 "$pid" 2>/dev/null; then
        remaining+=("$pid")
      fi
    done
    ((${#remaining[@]} == 0)) && return 0
    sleep 0.1
  done

  printf 'ERROR: %s no terminó tras SIGINT (PID: %s).\n' "$label" "${remaining[*]}" >&2
  printf 'Ciérralo manualmente y vuelve a ejecutar el reset. No se utilizará SIGKILL.\n' >&2
  exit 1
}

stop_exact_executable \
  "$PRACTICA_DIR/ue/openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem" \
  'OAI UE'
stop_exact_executable \
  "$PRACTICA_DIR/ran/ocudu/build/apps/gnb/gnb" \
  'OCUDU gNB'

DOCKER_CMD=()
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
  elif as_root docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo docker)
  fi
fi

if ((${#DOCKER_CMD[@]} > 0)); then
  if "${DOCKER_CMD[@]}" container inspect open5gs_5gc >/dev/null 2>&1; then
    printf 'Eliminando el contenedor open5gs_5gc...\n'
    "${DOCKER_CMD[@]}" container rm -f open5gs_5gc >/dev/null
  fi
  if "${DOCKER_CMD[@]}" network inspect rim-practica-ran >/dev/null 2>&1; then
    if ! "${DOCKER_CMD[@]}" network rm rim-practica-ran >/dev/null 2>&1; then
      printf 'Aviso: la red rim-practica-ran sigue en uso y no se ha eliminado.\n' >&2
    fi
  fi
else
  printf 'Aviso: Docker no está disponible; no había un runtime accesible que limpiar.\n' >&2
fi

if ip link show oaitun_ue1 >/dev/null 2>&1; then
  printf 'Eliminando la interfaz oaitun_ue1...\n'
  as_root ip link delete oaitun_ue1
fi

for runtime_file in /tmp/gnb.log /tmp/gnb_mac.pcap /tmp/gnb_ngap.pcap; do
  if [[ -e "$runtime_file" ]]; then
    as_root rm -f -- "$runtime_file"
  fi
done

rm -f -- \
  "$PRACTICA_DIR/core/open5gs/subscriber_db.csv" \
  "$PRACTICA_DIR/deployment.md"

install -D -m 0644 "$BASE_DIR/core/docker-compose.yml" \
  "$PRACTICA_DIR/core/docker-compose.yml"
install -D -m 0644 "$BASE_DIR/core/open5gs/open5gs.env" \
  "$PRACTICA_DIR/core/open5gs/open5gs.env"
install -D -m 0644 "$BASE_DIR/ran/gnb_zmq.yaml" \
  "$PRACTICA_DIR/ran/gnb_zmq.yaml"
install -D -m 0644 "$BASE_DIR/ue/oaiue_zmq.conf" \
  "$PRACTICA_DIR/ue/oaiue_zmq.conf"
install -D -m 0644 "$BASE_DIR/guia_alumno.md" \
  "$PRACTICA_DIR/guia_alumno.md"
install -D -m 0755 "$BASE_DIR/scripts/check_material.sh" \
  "$PRACTICA_DIR/scripts/check_material.sh"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose -f "$PRACTICA_DIR/core/docker-compose.yml" config --quiet
fi

"$PRACTICA_DIR/scripts/check_material.sh"
printf 'Reset completado: la práctica está en su estado degradado inicial.\n'
