#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required=(
  "tfg_hardslicing_v1.xml"
  "scripts_real/01_setup_vrf_subinterfaces.sh"
  "scripts_real/02_apply_hard_slicing_channels_tuned.sh"
  "scripts_flexible/01_setup_flexible_channels_base.sh"
  "scripts_flexible/02_flexible_channel_controller.sh"
  "automatizacion_tfg/controlador_tfg.sh"
  "automatizacion_tfg/lib/common.sh"
  "automatizacion_tfg/lib/channelized.sh"
  "automatizacion_tfg/lib/flexible.sh"
)

for file in "${required[@]}"; do
  [[ -f "$ROOT/$file" ]] || { echo "FALTA: $file" >&2; exit 1; }
done

while IFS= read -r -d '' script; do
  bash -n "$script"
  [[ -x "$script" ]] || { echo "SIN PERMISO DE EJECUCIÓN: $script" >&2; exit 1; }
done < <(find "$ROOT" -type f -name '*.sh' -print0)

if grep -RniE 'scripts_flexe|resultados_flexe|current_flexe|slot_mbit|slots_' \
  "$ROOT/scripts_flexible" "$ROOT/automatizacion_tfg" >/dev/null; then
  echo "Se han encontrado referencias obsoletas." >&2
  grep -RniE 'scripts_flexe|resultados_flexe|current_flexe|slot_mbit|slots_' \
    "$ROOT/scripts_flexible" "$ROOT/automatizacion_tfg" >&2
  exit 1
fi

echo "Repositorio validado correctamente."
