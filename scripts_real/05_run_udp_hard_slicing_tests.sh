#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " PRUEBA UDP HARD SLICING REAL"
echo "===================================================="

echo "[1] Preparando servidores iperf3..."

sudo lxc-attach -n hs_h3 -- pkill iperf3 2>/dev/null || true
sudo lxc-attach -n hs_h4 -- pkill iperf3 2>/dev/null || true

sudo lxc-attach -n hs_h3 -- iperf3 -s -p 5001 -D
sudo lxc-attach -n hs_h4 -- iperf3 -s -p 5002 -D

sudo lxc-attach -n hs_h3 -- ss -ltnp | grep 5001 || true
sudo lxc-attach -n hs_h4 -- ss -ltnp | grep 5002 || true

echo
echo "[2] Ejecutando prueba simultánea UDP..."
echo "Slice A: ofrece 20 Mbit/s, canal configurado 6 Mbit/s"
echo "Slice B: ofrece 20 Mbit/s, canal configurado 3 Mbit/s"

( sudo lxc-attach -n hs_h1 -- iperf3 -u -c 10.10.3.2 -p 5001 -b 20M -t 30 -i 5 2>&1 | sed 's/^/[SLICE A VLAN10 VRF-A 6M] /' ) &
( sudo lxc-attach -n hs_h2 -- iperf3 -u -c 10.20.4.2 -p 5002 -b 20M -t 30 -i 5 2>&1 | sed 's/^/[SLICE B VLAN20 VRF-B 3M] /' ) &
wait

echo
echo "[3] Contadores HTB tras la prueba..."

echo "--- Slice A: hs_r1 eth3.10 ---"
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.10

echo
echo "--- Slice B: hs_r1 eth3.20 ---"
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.20
