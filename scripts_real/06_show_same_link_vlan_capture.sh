#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " DEMOSTRACIÓN: MISMO ENLACE, CANALES VLAN DISTINTOS"
echo "===================================================="

echo
echo "En hs_r1, las subinterfaces eth3.10 y eth3.20 cuelgan del mismo enlace eth3:"
sudo lxc-attach -n hs_r1 -- ip -d link show eth3
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.10
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.20

echo
echo "Para ver tráfico etiquetado por VLAN en el enlace común, abre otra terminal y ejecuta:"
echo
echo "  sudo lxc-attach -n hs_r1 -- tcpdump -i eth3 -e -n 'vlan'"
echo
echo "Después, en esta terminal ejecuta la prueba UDP:"
echo
echo "  ./scripts_real/05_run_udp_hard_slicing_tests.sh"
echo
echo "En tcpdump deberías ver tramas VLAN 10 y VLAN 20 saliendo por eth3."
echo "===================================================="
