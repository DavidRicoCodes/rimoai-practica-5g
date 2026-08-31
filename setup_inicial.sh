#!/usr/bin/env bash

set -euo pipefail

PRACTICA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="$PRACTICA_DIR/.setup-inicial-completado"
FORCE=false

usage()
{
  cat <<'EOF'
Uso: ./setup_inicial.sh [--force]

Prepara y valida el estado inicial degradado de la práctica.
  --force     repite el setup y descarta el progreso actual
  --help, -h  muestra esta ayuda
EOF
}

case "${1:-}" in
  "") ;;
  --force) FORCE=true ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

[[ $# -le 1 ]] || { usage >&2; exit 2; }

if [[ -e "$MARKER" && "$FORCE" != true ]]; then
  printf '%s\n' \
    'ERROR: el setup inicial ya se ejecutó en esta copia.' \
    'Volver a ejecutarlo descartaría el progreso de la práctica.' \
    'Usa ./reset.sh para una recuperación voluntaria o ./setup_inicial.sh --force si realmente quieres reiniciar.' >&2
  exit 1
fi

printf '%s\n' \
  'Preparando el estado inicial degradado...' \
  'Esta operación restaura las configuraciones de partida y elimina cualquier runtime anterior.'

"$PRACTICA_DIR/reset.sh" --yes
"$PRACTICA_DIR/scripts/check_release.sh"

warnings=0

warn()
{
  printf 'AVISO: %s\n' "$1" >&2
  warnings=$((warnings + 1))
}

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 22.04 ]] \
    || warn "el entorno validado es Ubuntu 22.04; se ha detectado ${PRETTY_NAME:-un sistema diferente}"
else
  warn 'no se ha podido identificar el sistema operativo'
fi

[[ "$(uname -m)" == x86_64 ]] \
  || warn "la arquitectura validada es x86-64; se ha detectado $(uname -m)"

ram_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
if [[ "$ram_kib" =~ ^[0-9]+$ ]] && ((ram_kib < 12 * 1024 * 1024)); then
  warn 'se recomiendan al menos 12 GB de RAM'
fi

free_kib="$(df -Pk "$PRACTICA_DIR" | awk 'NR==2 {print $4}')"
if [[ "$free_kib" =~ ^[0-9]+$ ]] && ((free_kib < 20 * 1024 * 1024)); then
  warn 'se recomiendan al menos 20 GB libres para imágenes y compilaciones'
fi

missing=()
for command_name in git cmake ninja pkg-config gcc g++ screen docker; do
  command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
done

if ((${#missing[@]} > 0)); then
  warn "faltan herramientas que se instalarán siguiendo la guía: ${missing[*]}"
fi

if command -v docker >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
  warn 'Docker está instalado, pero no se encuentra el plugin Compose'
fi

printf '%s\n' \
  "tag=practica-5g-v1.1.0" \
  "fecha_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "avisos=$warnings" > "$MARKER"

printf '%s\n' \
  'Setup inicial completado.' \
  'No se han instalado dependencias ni compilado componentes.' \
  'Continúa con guia_alumno.md.'

if ((warnings > 0)); then
  printf 'Se han mostrado %d avisos de entorno; revísalos durante la instalación.\n' "$warnings"
fi
