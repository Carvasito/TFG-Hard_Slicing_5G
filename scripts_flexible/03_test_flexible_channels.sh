#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

OUT_DIR="resultados_flexible"
mkdir -p "$OUT_DIR"

sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR" 2>/dev/null || true
chmod -R u+rwX "$OUT_DIR" 2>/dev/null || true

STATE_FILE="$OUT_DIR/current_flexible_channels.conf"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: no existe $STATE_FILE"
  echo "Ejecuta antes scripts_flexible/02_flexible_channel_controller.sh"
  exit 1
fi

A="$(grep '^channel_a_mbit=' "$STATE_FILE" | cut -d= -f2)"
B="$(grep '^channel_b_mbit=' "$STATE_FILE" | cut -d= -f2)"

TAG="A${A}_B${B}"
TAG="${TAG//./p}"

A_LOG="$OUT_DIR/iperf_A_${TAG}.txt"
B_LOG="$OUT_DIR/iperf_B_${TAG}.txt"

echo "===================================================="
echo " PRUEBA FLEXIBLE CHANNELS"
echo "===================================================="
echo "Canal A configurado: ${A} Mbit/s"
echo "Canal B configurado: ${B} Mbit/s"
echo

echo "[1] Limpiando iperf"

for H in hs_h1 hs_h2 hs_h3 hs_h4; do
  sudo lxc-attach -n "$H" -- pkill iperf3 2>/dev/null || true
  sudo lxc-attach -n "$H" -- pkill iperf 2>/dev/null || true
done

sleep 2

echo "[2] Arrancando servidores"

sudo lxc-attach -n hs_h3 -- iperf3 -s -p 5001 -D
sudo lxc-attach -n hs_h4 -- iperf3 -s -p 5002 -D

sleep 2

sudo lxc-attach -n hs_h3 -- ps -ef | grep "[i]perf3" || true
sudo lxc-attach -n hs_h4 -- ps -ef | grep "[i]perf3" || true

echo
echo "[3] Comprobando conectividad"

sudo lxc-attach -n hs_h1 -- ping -c 3 10.0.3.2
sudo lxc-attach -n hs_h2 -- ping -c 3 10.0.4.2

echo
echo "[4] Lanzando tráfico UDP de saturación"

sudo rm -f "$A_LOG" "$B_LOG"
touch "$A_LOG" "$B_LOG"
chmod u+rw "$A_LOG" "$B_LOG"

(
  sudo lxc-attach -n hs_h1 -- iperf3 -u -c 10.0.3.2 -p 5001 \
    -b 20M -t 60 -i 10 -l 1400 --udp-counters-64bit
) > "$A_LOG" 2>&1 &

PID_A=$!

(
  sudo lxc-attach -n hs_h2 -- iperf3 -u -c 10.0.4.2 -p 5002 \
    -b 20M -t 60 -i 10 -l 1400 --udp-counters-64bit
) > "$B_LOG" 2>&1 &

PID_B=$!

wait "$PID_A" || true
wait "$PID_B" || true

sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR" 2>/dev/null || true
chmod -R u+rwX "$OUT_DIR" 2>/dev/null || true

echo
echo "===================================================="
echo " RESULTADOS"
echo "===================================================="

echo
echo "===== Canal A ====="
tail -n 12 "$A_LOG"

echo
echo "===== Canal B ====="
tail -n 12 "$B_LOG"

echo
echo "===== HTB hs_r1 eth3 ====="
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3

echo
echo "===== Estado Flexible Channels ====="
cat "$STATE_FILE"

echo
echo "===================================================="
echo " PRUEBA FINALIZADA"
echo "===================================================="
echo "Logs:"
echo "$A_LOG"
echo "$B_LOG"
echo "===================================================="
