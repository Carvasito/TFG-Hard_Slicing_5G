#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="resultados_hard_slicing_$TS"
mkdir -p "$OUT_DIR"

echo "===================================================="
echo " VALIDACIÓN FINAL HARD SLICING"
echo "===================================================="
echo "Directorio de resultados: $OUT_DIR"
echo

echo "===================================================="
echo "[1] ESTADO DE VRFs"
echo "===================================================="

{
echo "===== hs_r1 VRFs ====="
sudo lxc-attach -n hs_r1 -- ip -d link show type vrf
echo
echo "===== hs_r1 rutas vrfA ====="
sudo lxc-attach -n hs_r1 -- ip route show vrf vrfA
echo
echo "===== hs_r1 rutas vrfB ====="
sudo lxc-attach -n hs_r1 -- ip route show vrf vrfB
echo
echo "===== hs_r2 VRFs ====="
sudo lxc-attach -n hs_r2 -- ip -d link show type vrf
echo
echo "===== hs_r2 rutas vrfA ====="
sudo lxc-attach -n hs_r2 -- ip route show vrf vrfA
echo
echo "===== hs_r2 rutas vrfB ====="
sudo lxc-attach -n hs_r2 -- ip route show vrf vrfB
} | tee "$OUT_DIR/01_vrf_y_rutas.txt"

echo
echo "===================================================="
echo "[2] SUBINTERFACES SOBRE EL MISMO ENLACE"
echo "===================================================="

{
echo "===== Enlace base hs_r1 eth3 ====="
sudo lxc-attach -n hs_r1 -- ip -d link show eth3
echo
echo "===== Slice A sobre hs_r1 eth3.10 ====="
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.10
echo
echo "===== Slice B sobre hs_r1 eth3.20 ====="
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.20
echo
echo "===== Enlace base hs_r2 eth1 ====="
sudo lxc-attach -n hs_r2 -- ip -d link show eth1
echo
echo "===== Slice A sobre hs_r2 eth1.10 ====="
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.10
echo
echo "===== Slice B sobre hs_r2 eth1.20 ====="
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.20
} | tee "$OUT_DIR/02_subinterfaces_vlan.txt"

echo
echo "===================================================="
echo "[3] CONFIGURACIÓN HTB POR CANAL"
echo "===================================================="

{
echo "===== HTB Slice A hs_r1 eth3.10 ====="
sudo lxc-attach -n hs_r1 -- tc -s qdisc show dev eth3.10
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.10
echo
echo "===== HTB Slice B hs_r1 eth3.20 ====="
sudo lxc-attach -n hs_r1 -- tc -s qdisc show dev eth3.20
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.20
echo
echo "===== HTB Slice A retorno hs_r2 eth1.10 ====="
sudo lxc-attach -n hs_r2 -- tc -s qdisc show dev eth1.10
sudo lxc-attach -n hs_r2 -- tc -s class show dev eth1.10
echo
echo "===== HTB Slice B retorno hs_r2 eth1.20 ====="
sudo lxc-attach -n hs_r2 -- tc -s qdisc show dev eth1.20
sudo lxc-attach -n hs_r2 -- tc -s class show dev eth1.20
} | tee "$OUT_DIR/03_htb_canales.txt"

echo
echo "===================================================="
echo "[4] PRUEBAS DE AISLAMIENTO ENTRE SLICES"
echo "===================================================="

{
echo "===== Prueba positiva Slice A: hs_h1 -> hs_h3 ====="
sudo lxc-attach -n hs_h1 -- ping -c 3 10.10.3.2
echo
echo "===== Prueba positiva Slice B: hs_h2 -> hs_h4 ====="
sudo lxc-attach -n hs_h2 -- ping -c 3 10.20.4.2
echo
echo "===== Prueba negativa A -> B: hs_h1 NO debe llegar a hs_h4 ====="
set +e
sudo lxc-attach -n hs_h1 -- ping -c 3 -W 1 10.20.4.2
RET_A_TO_B=$?
set -e
echo "Código resultado A->B: $RET_A_TO_B"
echo
echo "===== Prueba negativa B -> A: hs_h2 NO debe llegar a hs_h3 ====="
set +e
sudo lxc-attach -n hs_h2 -- ping -c 3 -W 1 10.10.3.2
RET_B_TO_A=$?
set -e
echo "Código resultado B->A: $RET_B_TO_A"
echo
if [[ "$RET_A_TO_B" -ne 0 && "$RET_B_TO_A" -ne 0 ]]; then
  echo "RESULTADO AISLAMIENTO: CORRECTO"
else
  echo "RESULTADO AISLAMIENTO: INCORRECTO"
  exit 1
fi
} | tee "$OUT_DIR/04_aislamiento.txt"

echo
echo "===================================================="
echo "[5] PREPARANDO SERVIDORES IPERF3"
echo "===================================================="

sudo lxc-attach -n hs_h3 -- pkill iperf3 2>/dev/null || true
sudo lxc-attach -n hs_h4 -- pkill iperf3 2>/dev/null || true

sudo lxc-attach -n hs_h3 -- iperf3 -s -p 5001 -D
sudo lxc-attach -n hs_h4 -- iperf3 -s -p 5002 -D

{
echo "===== Servidor Slice A hs_h3:5001 ====="
sudo lxc-attach -n hs_h3 -- ss -ltnp | grep 5001
echo
echo "===== Servidor Slice B hs_h4:5002 ====="
sudo lxc-attach -n hs_h4 -- ss -ltnp | grep 5002
} | tee "$OUT_DIR/05_servidores_iperf.txt"

echo
echo "===================================================="
echo "[6] PRUEBA FINA 6/3 CON CORRECCIÓN DE CABECERAS"
echo "===================================================="
echo "Slice A: iperf útil 5.72 Mbit/s -> aprox. 6 Mbit/s en enlace"
echo "Slice B: iperf útil 2.86 Mbit/s -> aprox. 3 Mbit/s en enlace"
echo "Payload UDP iperf3: 1400 bytes"
echo "Factor aproximado cabeceras: 1470/1400 = 1.05"
echo

( sudo lxc-attach -n hs_h1 -- iperf3 -u -c 10.10.3.2 -p 5001 \
  -b 5.72M -t 180 -i 10 -l 1400 --udp-counters-64bit \
  2>&1 | tee "$OUT_DIR/06_iperf_sliceA_fino.txt" ) &

( sudo lxc-attach -n hs_h2 -- iperf3 -u -c 10.20.4.2 -p 5002 \
  -b 2.86M -t 180 -i 10 -l 1400 --udp-counters-64bit \
  2>&1 | tee "$OUT_DIR/06_iperf_sliceB_fino.txt" ) &

wait

echo
echo "===================================================="
echo "[7] CONTADORES HTB TRAS PRUEBA FINA"
echo "===================================================="

{
echo "===== HTB Slice A hs_r1 eth3.10 ====="
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.10
echo
echo "===== HTB Slice B hs_r1 eth3.20 ====="
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.20
} | tee "$OUT_DIR/07_htb_tras_prueba_fina.txt"

echo
echo "===================================================="
echo "[8] PRUEBA DE SATURACIÓN CONTROLADA"
echo "===================================================="
echo "Esta prueba fuerza exceso de tráfico para demostrar que HTB descarta lo que supera el canal."
echo "Slice A ofrece 20 Mbit/s sobre canal 6 Mbit/s."
echo "Slice B ofrece 20 Mbit/s sobre canal 3 Mbit/s."
echo

( sudo lxc-attach -n hs_h1 -- iperf3 -u -c 10.10.3.2 -p 5001 \
  -b 20M -t 60 -i 10 -l 1400 --udp-counters-64bit \
  2>&1 | tee "$OUT_DIR/08_iperf_sliceA_saturacion.txt" ) &

( sudo lxc-attach -n hs_h2 -- iperf3 -u -c 10.20.4.2 -p 5002 \
  -b 20M -t 60 -i 10 -l 1400 --udp-counters-64bit \
  2>&1 | tee "$OUT_DIR/08_iperf_sliceB_saturacion.txt" ) &

wait

echo
echo "===================================================="
echo "[9] CONTADORES HTB TRAS SATURACIÓN"
echo "===================================================="

{
echo "===== HTB Slice A hs_r1 eth3.10 tras saturación ====="
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.10
echo
echo "===== HTB Slice B hs_r1 eth3.20 tras saturación ====="
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.20
} | tee "$OUT_DIR/09_htb_tras_saturacion.txt"

echo
echo "===================================================="
echo " VALIDACIÓN FINAL COMPLETADA"
echo "===================================================="
echo "Resultados guardados en: $OUT_DIR"
echo
echo "Resumen esperado:"
echo "  - VRF-A y VRF-B existen y tienen rutas separadas."
echo "  - VLAN 10 y VLAN 20 cuelgan del mismo enlace físico/lógico."
echo "  - No hay conectividad cruzada entre slices."
echo "  - Prueba fina: 5.72 x 1.05 ≈ 6 Mbit/s; 2.86 x 1.05 ≈ 3 Mbit/s."
echo "  - Prueba de saturación: aparecen pérdidas/drops porque se supera la capacidad de cada canal."
echo "===================================================="
