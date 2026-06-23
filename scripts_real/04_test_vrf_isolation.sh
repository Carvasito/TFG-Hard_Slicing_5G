#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " PRUEBAS DE AISLAMIENTO ENTRE SLICES"
echo "===================================================="

echo
echo "[1] Prueba positiva Slice A: hs_h1 debe llegar a hs_h3"
sudo lxc-attach -n hs_h1 -- ping -c 3 10.10.3.2

echo
echo "[2] Prueba positiva Slice B: hs_h2 debe llegar a hs_h4"
sudo lxc-attach -n hs_h2 -- ping -c 3 10.20.4.2

echo
echo "[3] Prueba negativa A -> B: hs_h1 NO debe llegar a hs_h4"
set +e
sudo lxc-attach -n hs_h1 -- ping -c 3 -W 1 10.20.4.2
RET_A_TO_B=$?
set -e

echo
echo "[4] Prueba negativa B -> A: hs_h2 NO debe llegar a hs_h3"
set +e
sudo lxc-attach -n hs_h2 -- ping -c 3 -W 1 10.10.3.2
RET_B_TO_A=$?
set -e

echo
echo "===================================================="
if [[ "$RET_A_TO_B" -ne 0 && "$RET_B_TO_A" -ne 0 ]]; then
  echo "AISLAMIENTO CORRECTO:"
  echo "  - Slice A funciona internamente."
  echo "  - Slice B funciona internamente."
  echo "  - Slice A no alcanza Slice B."
  echo "  - Slice B no alcanza Slice A."
else
  echo "AISLAMIENTO INCORRECTO: existe conectividad cruzada."
  exit 1
fi
echo "===================================================="
