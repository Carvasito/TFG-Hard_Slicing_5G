#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "===================================================="
echo " PREPARACIÓN COMPLETA HARD SLICING REAL"
echo "===================================================="

bash scripts_real/01_setup_vrf_subinterfaces.sh
bash scripts_real/02_apply_hard_slicing_channels.sh
bash scripts_real/03_show_real_slicing.sh

echo
echo "===================================================="
echo " ESCENARIO LISTO"
echo " Slice A: VRF-A + VLAN 10 + HTB 6 Mbit/s"
echo " Slice B: VRF-B + VLAN 20 + HTB 3 Mbit/s"
echo " Enlace común: hs_r1 eth3 <====> hs_r2 eth1"
echo "===================================================="
