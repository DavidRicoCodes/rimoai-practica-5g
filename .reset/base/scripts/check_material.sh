#!/usr/bin/env bash

set -euo pipefail

PRACTICA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$PRACTICA_DIR/ran/ocudu/apps/units/o_cu_cp/o_cu_cp_builder.cpp"
FORMATTER="$PRACTICA_DIR/ran/ocudu/include/ocudu/phy/upper/channel_processors/pdsch/formatters.h"
COMPOSE="$PRACTICA_DIR/core/docker-compose.yml"
CORE_ENV="$PRACTICA_DIR/core/open5gs/open5gs.env"
GNB_CONFIG="$PRACTICA_DIR/ran/gnb_zmq.yaml"
UE_CONFIG="$PRACTICA_DIR/ue/oaiue_zmq.conf"
GUIDE="$PRACTICA_DIR/guia_alumno.md"
RESET_DIR="$PRACTICA_DIR/.reset"

fail()
{
  printf 'ERROR de integridad: %s\n' "$1" >&2
  exit 1
}

require_file()
{
  [[ -f "$1" ]] || fail "falta un archivo necesario del material"
}

require_match()
{
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || fail "se ha alterado un elemento no evaluado del material"
}

for required in \
  "$BUILDER" \
  "$FORMATTER" \
  "$COMPOSE" \
  "$CORE_ENV" \
  "$GNB_CONFIG" \
  "$UE_CONFIG" \
  "$GUIDE" \
  "$PRACTICA_DIR/reset.sh" \
  "$RESET_DIR/README.md" \
  "$RESET_DIR/manifest.sha256"
do
  require_file "$required"
done

# Correcciones de código proporcionadas por el profesorado. No forman parte del ejercicio.
grep -Fq 'cu_cp_cfg.ngap.n2_gws.reserve(n2_clients.size());' "$BUILDER" \
  || fail "falta una corrección integrada de OCUDU"
grep -Fq 'cu_cp_cfg.ngap.n2_gws.push_back(n2_client.get());' "$BUILDER" \
  || fail "falta una corrección integrada de OCUDU"
grep -Fq '#include "fmt/ranges.h"' "$FORMATTER" \
  || fail "falta una corrección integrada de OCUDU"
grep -Fq 'fmt::join(pdu.codewords, " ")' "$FORMATTER" \
  || fail "falta una corrección integrada de OCUDU"

# Parámetros de PHY y drivers que deben permanecer fijos durante la práctica.
require_match '^[[:space:]]*device_driver:[[:space:]]*zmq([[:space:]]|$)' "$GNB_CONFIG"
require_match '^[[:space:]]*tx_gain:[[:space:]]*-12([[:space:]]|$)' "$GNB_CONFIG"
require_match '^[[:space:]]*band:[[:space:]]*78([[:space:]]|$)' "$GNB_CONFIG"
require_match '^[[:space:]]*channel_bandwidth_MHz:[[:space:]]*20([[:space:]]|$)' "$GNB_CONFIG"
require_match '^[[:space:]]*common_scs:[[:space:]]*30([[:space:]]|$)' "$GNB_CONFIG"
require_match '^[[:space:]]*name[[:space:]]*=[[:space:]]*"oai_zmqdevif";' "$UE_CONFIG"
require_match '^[[:space:]]*C[[:space:]]*=[[:space:]]*3489420000L;' "$UE_CONFIG"
require_match '^[[:space:]]*band[[:space:]]*=[[:space:]]*78;' "$UE_CONFIG"
require_match '^[[:space:]]*numerology[[:space:]]*=[[:space:]]*1;' "$UE_CONFIG"
require_match 'uecap_ports1\.xml' "$UE_CONFIG"

# Estructura mínima. Los valores de los ejercicios no se validan aquí.
for key in MONGODB_IP OPEN5GS_IP UE_IP_BASE UPF_ADVERTISE_IP SUBSCRIBER_DB MCC MNC; do
  grep -Eq "^[[:space:]]*${key}=" "$CORE_ENV" \
    || fail "la configuración del core ha perdido campos necesarios"
done

for key in addr port bind_addr plmn device_args; do
  grep -Eq "^[[:space:]-]*${key}:" "$GNB_CONFIG" \
    || fail "la configuración del gNB ha perdido campos necesarios"
done

for key in imsi key opc pdu_sessions tx_channels rx_channels; do
  grep -Eq "^[[:space:]]*${key}[[:space:]=]" "$UE_CONFIG" \
    || fail "la configuración del UE ha perdido campos necesarios"
done

[[ ! -e "$PRACTICA_DIR/deployment.md" ]] \
  || fail "se ha restaurado una guía obsoleta que no pertenece al material del alumno"

bash -n "$PRACTICA_DIR/reset.sh" || fail "el script de reset tiene sintaxis inválida"

(
  cd "$RESET_DIR"
  sha256sum -c manifest.sha256 --status
) || fail "la copia protegida de reset no supera su manifiesto"

cmp -s "$GUIDE" "$RESET_DIR/base/guia_alumno.md" \
  || fail "la guía del alumno ha sido modificada"
cmp -s "${BASH_SOURCE[0]}" "$RESET_DIR/base/scripts/check_material.sh" \
  || fail "el verificador del material ha sido modificado"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose -f "$COMPOSE" config --quiet \
    || fail "la configuración Compose no es sintácticamente válida"
fi

printf '%s\n' \
  'OK: el material no evaluado está íntegro y las configuraciones conservan su estructura.' \
  'Este resultado no valida las soluciones de la práctica.'
