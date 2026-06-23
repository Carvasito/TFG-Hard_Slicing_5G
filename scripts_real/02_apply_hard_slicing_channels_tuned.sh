#!/usr/bin/env bash
set -euo pipefail

SLICE_A_RATE="${SLICE_A_RATE:-6mbit}"
SLICE_B_RATE="${SLICE_B_RATE:-3mbit}"

BURST="${BURST:-128k}"
QUEUE_LIMIT="${QUEUE_LIMIT:-10000}"

echo "===================================================="
echo " APLICANDO HTB TUNED POR CANAL"
echo "===================================================="
echo "Slice A -> eth3.10 / eth1.10 -> $SLICE_A_RATE"
echo "Slice B -> eth3.20 / eth1.20 -> $SLICE_B_RATE"
echo "Burst/cburst -> $BURST"
echo "Queue limit -> $QUEUE_LIMIT paquetes"

echo "[1] Limpieza previa..."

for DEV in eth3.10 eth3.20; do
  sudo lxc-attach -n hs_r1 -- tc qdisc del dev "$DEV" root 2>/dev/null || true
done

for DEV in eth1.10 eth1.20; do
  sudo lxc-attach -n hs_r2 -- tc qdisc del dev "$DEV" root 2>/dev/null || true
done

echo "[2] Slice A: hs_r1 eth3.10"

sudo lxc-attach -n hs_r1 -- tc qdisc add dev eth3.10 root handle 1: htb default 10
sudo lxc-attach -n hs_r1 -- tc class add dev eth3.10 parent 1: classid 1:10 htb \
  rate "$SLICE_A_RATE" ceil "$SLICE_A_RATE" burst "$BURST" cburst "$BURST"
sudo lxc-attach -n hs_r1 -- tc qdisc add dev eth3.10 parent 1:10 handle 10: pfifo limit "$QUEUE_LIMIT"

echo "[3] Slice A retorno: hs_r2 eth1.10"

sudo lxc-attach -n hs_r2 -- tc qdisc add dev eth1.10 root handle 1: htb default 10
sudo lxc-attach -n hs_r2 -- tc class add dev eth1.10 parent 1: classid 1:10 htb \
  rate "$SLICE_A_RATE" ceil "$SLICE_A_RATE" burst "$BURST" cburst "$BURST"
sudo lxc-attach -n hs_r2 -- tc qdisc add dev eth1.10 parent 1:10 handle 10: pfifo limit "$QUEUE_LIMIT"

echo "[4] Slice B: hs_r1 eth3.20"

sudo lxc-attach -n hs_r1 -- tc qdisc add dev eth3.20 root handle 1: htb default 20
sudo lxc-attach -n hs_r1 -- tc class add dev eth3.20 parent 1: classid 1:20 htb \
  rate "$SLICE_B_RATE" ceil "$SLICE_B_RATE" burst "$BURST" cburst "$BURST"
sudo lxc-attach -n hs_r1 -- tc qdisc add dev eth3.20 parent 1:20 handle 20: pfifo limit "$QUEUE_LIMIT"

echo "[5] Slice B retorno: hs_r2 eth1.20"

sudo lxc-attach -n hs_r2 -- tc qdisc add dev eth1.20 root handle 1: htb default 20
sudo lxc-attach -n hs_r2 -- tc class add dev eth1.20 parent 1: classid 1:20 htb \
  rate "$SLICE_B_RATE" ceil "$SLICE_B_RATE" burst "$BURST" cburst "$BURST"
sudo lxc-attach -n hs_r2 -- tc qdisc add dev eth1.20 parent 1:20 handle 20: pfifo limit "$QUEUE_LIMIT"

echo "===================================================="
echo " HTB TUNED APLICADO"
echo " Slice A: $SLICE_A_RATE"
echo " Slice B: $SLICE_B_RATE"
echo "===================================================="
