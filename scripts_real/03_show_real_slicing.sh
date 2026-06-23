#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " ESTADO DE VRFs"
echo "===================================================="

echo "--- hs_r1 VRFs ---"
sudo lxc-attach -n hs_r1 -- ip -d link show type vrf
echo
sudo lxc-attach -n hs_r1 -- ip route show vrf vrfA
sudo lxc-attach -n hs_r1 -- ip route show vrf vrfB

echo
echo "--- hs_r2 VRFs ---"
sudo lxc-attach -n hs_r2 -- ip -d link show type vrf
echo
sudo lxc-attach -n hs_r2 -- ip route show vrf vrfA
sudo lxc-attach -n hs_r2 -- ip route show vrf vrfB

echo
echo "===================================================="
echo " SUBINTERFACES SOBRE EL MISMO ENLACE"
echo "===================================================="

echo "--- hs_r1: eth3.10 y eth3.20 cuelgan de eth3 ---"
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.10
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.20

echo
echo "--- hs_r2: eth1.10 y eth1.20 cuelgan de eth1 ---"
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.10
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.20

echo
echo "===================================================="
echo " HTB POR CANAL"
echo "===================================================="

echo "--- Slice A en hs_r1 eth3.10 ---"
sudo lxc-attach -n hs_r1 -- tc -s qdisc show dev eth3.10
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.10

echo
echo "--- Slice B en hs_r1 eth3.20 ---"
sudo lxc-attach -n hs_r1 -- tc -s qdisc show dev eth3.20
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.20

echo
echo "--- Slice A retorno en hs_r2 eth1.10 ---"
sudo lxc-attach -n hs_r2 -- tc -s qdisc show dev eth1.10
sudo lxc-attach -n hs_r2 -- tc -s class show dev eth1.10

echo
echo "--- Slice B retorno en hs_r2 eth1.20 ---"
sudo lxc-attach -n hs_r2 -- tc -s qdisc show dev eth1.20
sudo lxc-attach -n hs_r2 -- tc -s class show dev eth1.20
