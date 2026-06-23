#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$DIR/controlador_tfg.sh" "$DIR/instalar.sh" "$DIR/lib/"*.sh
mkdir -p "$DIR/resultados"
echo "Permisos aplicados correctamente."
echo "Ejecute: $DIR/controlador_tfg.sh"
