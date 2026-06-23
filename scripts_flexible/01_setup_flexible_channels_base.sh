#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " ESCENARIO FLEXIBLE CHANNELS"
echo " Sin VRF, sin VLAN, sin subinterfaces"
echo " Enlace compartido: hs_r1 eth3 <-> hs_r2 eth1"
echo "===================================================="

echo "[1] Limpieza previa en hosts"

for H in hs_h1 hs_h2 hs_h3 hs_h4; do
  sudo lxc-attach -n "$H" -- pkill iperf3 2>/dev/null || true
  sudo lxc-attach -n "$H" -- pkill iperf 2>/dev/null || true
  sudo lxc-attach -n "$H" -- ip addr flush dev eth1 || true
  sudo lxc-attach -n "$H" -- ip route del default 2>/dev/null || true
  sudo lxc-attach -n "$H" -- ip link set eth1 up || true
done

echo "[2] Limpieza previa en routers"

for R in hs_r1 hs_r2; do
  for DEV in eth1 eth2 eth3 eth1.10 eth1.20 eth3.10 eth3.20; do
    sudo lxc-attach -n "$R" -- tc qdisc del dev "$DEV" root 2>/dev/null || true
    sudo lxc-attach -n "$R" -- ip link set dev "$DEV" nomaster 2>/dev/null || true
  done

  sudo lxc-attach -n "$R" -- ip link del eth1.10 2>/dev/null || true
  sudo lxc-attach -n "$R" -- ip link del eth1.20 2>/dev/null || true
  sudo lxc-attach -n "$R" -- ip link del eth3.10 2>/dev/null || true
  sudo lxc-attach -n "$R" -- ip link del eth3.20 2>/dev/null || true

  sudo lxc-attach -n "$R" -- ip link del vrfA 2>/dev/null || true
  sudo lxc-attach -n "$R" -- ip link del vrfB 2>/dev/null || true

  sudo lxc-attach -n "$R" -- ip addr flush dev eth1 || true
  sudo lxc-attach -n "$R" -- ip addr flush dev eth2 || true
  sudo lxc-attach -n "$R" -- ip addr flush dev eth3 || true

  sudo lxc-attach -n "$R" -- ip link set eth1 up || true
  sudo lxc-attach -n "$R" -- ip link set eth2 up || true
  sudo lxc-attach -n "$R" -- ip link set eth3 up || true
done

echo "[3] Direccionamiento plano"

sudo lxc-attach -n hs_h1 -- ip addr add 10.0.1.2/24 dev eth1
sudo lxc-attach -n hs_h2 -- ip addr add 10.0.2.2/24 dev eth1
sudo lxc-attach -n hs_h3 -- ip addr add 10.0.3.2/24 dev eth1
sudo lxc-attach -n hs_h4 -- ip addr add 10.0.4.2/24 dev eth1

sudo lxc-attach -n hs_r1 -- ip addr add 10.0.1.1/24 dev eth1
sudo lxc-attach -n hs_r1 -- ip addr add 10.0.2.1/24 dev eth2
sudo lxc-attach -n hs_r1 -- ip addr add 10.0.12.1/24 dev eth3

sudo lxc-attach -n hs_r2 -- ip addr add 10.0.12.2/24 dev eth1
sudo lxc-attach -n hs_r2 -- ip addr add 10.0.3.1/24 dev eth2
sudo lxc-attach -n hs_r2 -- ip addr add 10.0.4.1/24 dev eth3

echo "[4] Activando encaminamiento IPv4"

sudo lxc-attach -n hs_r1 -- sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo lxc-attach -n hs_r2 -- sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "[5] Rutas"

sudo lxc-attach -n hs_h1 -- ip route replace default via 10.0.1.1
sudo lxc-attach -n hs_h2 -- ip route replace default via 10.0.2.1
sudo lxc-attach -n hs_h3 -- ip route replace default via 10.0.3.1
sudo lxc-attach -n hs_h4 -- ip route replace default via 10.0.4.1

sudo lxc-attach -n hs_r1 -- ip route replace 10.0.3.0/24 via 10.0.12.2
sudo lxc-attach -n hs_r1 -- ip route replace 10.0.4.0/24 via 10.0.12.2

sudo lxc-attach -n hs_r2 -- ip route replace 10.0.1.0/24 via 10.0.12.1
sudo lxc-attach -n hs_r2 -- ip route replace 10.0.2.0/24 via 10.0.12.1

echo "[6] Comprobación de conectividad"

echo "Slice A: hs_h1 -> hs_h3"
sudo lxc-attach -n hs_h1 -- ping -c 3 10.0.3.2

echo "Slice B: hs_h2 -> hs_h4"
sudo lxc-attach -n hs_h2 -- ping -c 3 10.0.4.2

echo "===================================================="
echo " ESCENARIO FLEXIBLE CHANNELS PREPARADO"
echo "===================================================="
echo "Sin VRF"
echo "Sin VLAN"
echo "Sin subinterfaces"
echo "Canal compartido: hs_r1 eth3 <-> hs_r2 eth1"
echo "===================================================="
