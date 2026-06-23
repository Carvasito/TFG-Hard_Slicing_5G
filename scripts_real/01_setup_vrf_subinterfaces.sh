#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " CONFIGURANDO HARD SLICING REAL: VRF + SUBINTERFACES"
echo "===================================================="

echo "[0] Activando modulos necesarios en host si existen..."
sudo modprobe vrf 2>/dev/null || true
sudo modprobe 8021q 2>/dev/null || true

echo "[1] Limpieza previa en hosts finales..."

for H in hs_h1 hs_h2 hs_h3 hs_h4; do
  sudo lxc-attach -n "$H" -- ip addr flush dev eth1 || true
  sudo lxc-attach -n "$H" -- ip route flush dev eth1 || true
  sudo lxc-attach -n "$H" -- ip route del default 2>/dev/null || true
  sudo lxc-attach -n "$H" -- ip link set eth1 up || true
done

echo "[2] Limpieza previa en routers..."

for R in hs_r1 hs_r2; do
  sudo lxc-attach -n "$R" -- tc qdisc del dev eth1 root 2>/dev/null || true
  sudo lxc-attach -n "$R" -- tc qdisc del dev eth2 root 2>/dev/null || true
  sudo lxc-attach -n "$R" -- tc qdisc del dev eth3 root 2>/dev/null || true
  sudo lxc-attach -n "$R" -- tc qdisc del dev eth1.10 root 2>/dev/null || true
  sudo lxc-attach -n "$R" -- tc qdisc del dev eth1.20 root 2>/dev/null || true
  sudo lxc-attach -n "$R" -- tc qdisc del dev eth3.10 root 2>/dev/null || true
  sudo lxc-attach -n "$R" -- tc qdisc del dev eth3.20 root 2>/dev/null || true

  for DEV in eth1 eth2 eth3 eth1.10 eth1.20 eth3.10 eth3.20; do
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

echo "[3] Configurando hosts finales..."

# Slice A
sudo lxc-attach -n hs_h1 -- ip addr add 10.10.1.2/24 dev eth1
sudo lxc-attach -n hs_h1 -- ip route replace default via 10.10.1.1

sudo lxc-attach -n hs_h3 -- ip addr add 10.10.3.2/24 dev eth1
sudo lxc-attach -n hs_h3 -- ip route replace default via 10.10.3.1

# Slice B
sudo lxc-attach -n hs_h2 -- ip addr add 10.20.1.2/24 dev eth1
sudo lxc-attach -n hs_h2 -- ip route replace default via 10.20.1.1

sudo lxc-attach -n hs_h4 -- ip addr add 10.20.4.2/24 dev eth1
sudo lxc-attach -n hs_h4 -- ip route replace default via 10.20.4.1

echo "[4] Creando VRFs en hs_r1 y hs_r2..."

for R in hs_r1 hs_r2; do
  sudo lxc-attach -n "$R" -- ip link add vrfA type vrf table 10
  sudo lxc-attach -n "$R" -- ip link add vrfB type vrf table 20
  sudo lxc-attach -n "$R" -- ip link set vrfA up
  sudo lxc-attach -n "$R" -- ip link set vrfB up
done

echo "[5] Creando subinterfaces VLAN sobre EL MISMO ENLACE entre routers..."

# Enlace común real de la maqueta:
# hs_r1 eth3 ================= hs_r2 eth1
sudo lxc-attach -n hs_r1 -- ip link add link eth3 name eth3.10 type vlan id 10
sudo lxc-attach -n hs_r1 -- ip link add link eth3 name eth3.20 type vlan id 20

sudo lxc-attach -n hs_r2 -- ip link add link eth1 name eth1.10 type vlan id 10
sudo lxc-attach -n hs_r2 -- ip link add link eth1 name eth1.20 type vlan id 20

sudo lxc-attach -n hs_r1 -- ip link set eth3.10 up
sudo lxc-attach -n hs_r1 -- ip link set eth3.20 up
sudo lxc-attach -n hs_r2 -- ip link set eth1.10 up
sudo lxc-attach -n hs_r2 -- ip link set eth1.20 up

echo "[6] Asignando interfaces y subinterfaces a cada VRF..."

# hs_r1:
# Slice A: entrada eth1 + canal eth3.10
sudo lxc-attach -n hs_r1 -- ip link set eth1 master vrfA
sudo lxc-attach -n hs_r1 -- ip link set eth3.10 master vrfA

# Slice B: entrada eth2 + canal eth3.20
sudo lxc-attach -n hs_r1 -- ip link set eth2 master vrfB
sudo lxc-attach -n hs_r1 -- ip link set eth3.20 master vrfB

# hs_r2:
# Slice A: canal eth1.10 + salida eth2
sudo lxc-attach -n hs_r2 -- ip link set eth1.10 master vrfA
sudo lxc-attach -n hs_r2 -- ip link set eth2 master vrfA

# Slice B: canal eth1.20 + salida eth3
sudo lxc-attach -n hs_r2 -- ip link set eth1.20 master vrfB
sudo lxc-attach -n hs_r2 -- ip link set eth3 master vrfB

echo "[7] Direccionamiento de routers dentro de cada VRF..."

# hs_r1 - Slice A
sudo lxc-attach -n hs_r1 -- ip addr add 10.10.1.1/24 dev eth1
sudo lxc-attach -n hs_r1 -- ip addr add 10.10.12.1/30 dev eth3.10

# hs_r1 - Slice B
sudo lxc-attach -n hs_r1 -- ip addr add 10.20.1.1/24 dev eth2
sudo lxc-attach -n hs_r1 -- ip addr add 10.20.12.1/30 dev eth3.20

# hs_r2 - Slice A
sudo lxc-attach -n hs_r2 -- ip addr add 10.10.12.2/30 dev eth1.10
sudo lxc-attach -n hs_r2 -- ip addr add 10.10.3.1/24 dev eth2

# hs_r2 - Slice B
sudo lxc-attach -n hs_r2 -- ip addr add 10.20.12.2/30 dev eth1.20
sudo lxc-attach -n hs_r2 -- ip addr add 10.20.4.1/24 dev eth3

echo "[8] Activando forwarding IPv4..."

sudo lxc-attach -n hs_r1 -- sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo lxc-attach -n hs_r2 -- sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "[9] Rutas independientes por VRF..."

# Rutas en hs_r1
sudo lxc-attach -n hs_r1 -- ip route replace vrf vrfA 10.10.3.0/24 via 10.10.12.2
sudo lxc-attach -n hs_r1 -- ip route replace vrf vrfB 10.20.4.0/24 via 10.20.12.2

# Rutas en hs_r2
sudo lxc-attach -n hs_r2 -- ip route replace vrf vrfA 10.10.1.0/24 via 10.10.12.1
sudo lxc-attach -n hs_r2 -- ip route replace vrf vrfB 10.20.1.0/24 via 10.20.12.1

echo "===================================================="
echo " CONFIGURACIÓN VRF + SUBINTERFACES COMPLETADA"
echo " Slice A: vrfA + VLAN 10 + red 10.10.x.x"
echo " Slice B: vrfB + VLAN 20 + red 10.20.x.x"
echo " Enlace común: hs_r1 eth3 <====> hs_r2 eth1"
echo "===================================================="
