#!/usr/bin/env bash
set -uo pipefail

AUTO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$AUTO_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$AUTO_DIR/config/automatizacion.conf"
# shellcheck source=/dev/null
source "$AUTO_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$AUTO_DIR/lib/channelized.sh"
# shellcheck source=/dev/null
source "$AUTO_DIR/lib/flexible.sh"

CURRENT_SCENARIO="ninguno"
CURRENT_PROFILE="ninguno"
RUN_DIR="$AUTO_DIR/resultados"
RESULT_FILE="/dev/null"

cleanup_on_exit() {
  stop_test_processes >/dev/null 2>&1 || true
}
trap cleanup_on_exit EXIT INT TERM

main_menu() {
  while true; do
    clear 2>/dev/null || true
    cat <<'MENU'
============================================================
 CONTROLADOR EXPERIMENTAL DE HARD SLICING EN TRANSPORTE 5G
============================================================
 1) Preparar Channelized Subinterfaces y abrir sus pruebas
 2) Preparar Flexible Channels y abrir sus pruebas
 3) Ejecutar comprobaciones previas
 4) Detener procesos de prueba
 5) Mostrar última carpeta de resultados
 0) Salir
============================================================
MENU
    read -r -p "Seleccione una opción: " option
    case "$option" in
      1)
        if preflight && prepare_channelized; then channelized_menu; else pause; fi
        ;;
      2)
        if preflight && prepare_flexible; then flexible_menu; else pause; fi
        ;;
      3) preflight || true; pause ;;
      4) require_sudo && stop_test_processes; ok "Procesos detenidos"; pause ;;
      5) show_last_results; pause ;;
      0) echo "Saliendo del controlador."; exit 0 ;;
      *) warn "Opción no válida"; pause ;;
    esac
  done
}

main_menu
