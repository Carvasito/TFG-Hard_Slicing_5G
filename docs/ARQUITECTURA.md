# Arquitectura

## Topología común

```text
hs_h1 ---- hs_r1 ===== hs_r2 ---- hs_h3
             ||
             ||
hs_h2 -------++------------------- hs_h4
```

El tramo compartido es `hs_r1 eth3 <-> hs_r2 eth1`.

## Channelized Subinterfaces

- Slice A: VRF `vrfA`, VLAN 10, `eth3.10/eth1.10`, límite 6 Mbit/s.
- Slice B: VRF `vrfB`, VLAN 20, `eth3.20/eth1.20`, límite 3 Mbit/s.
- Las políticas HTB se aplican sobre subinterfaces distintas.

## Flexible Channels

- No utiliza VRF, VLAN ni subinterfaces.
- Los dos flujos comparten la interfaz base.
- Canal A: tráfico hacia `10.0.3.2`, clase `1:10`.
- Canal B: tráfico hacia `10.0.4.2`, clase `1:20`.
- La capacidad total y las asignaciones A/B son configurables.
- La clase `1:30` recibe tráfico no clasificado.

## Automatización

El controlador se divide en:

- `common.sh`: comprobaciones, procesos, registros y funciones comunes.
- `channelized.sh`: preparación y pruebas del escenario canalizado.
- `flexible.sh`: preparación y pruebas de Flexible Channels.
- `automatizacion.conf`: parámetros generales y valores por defecto.
