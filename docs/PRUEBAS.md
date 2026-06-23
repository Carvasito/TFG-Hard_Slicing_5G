# Pruebas disponibles

## Channelized Subinterfaces

- Estado de VRF, rutas, VLAN y políticas HTB.
- Conectividad interna y ausencia de conectividad cruzada.
- Caudal simultáneo de ambas slices.
- Captura automática de VLAN 10 y VLAN 20.
- Contadores HTB.
- RTT de la Slice A con tráfico simultáneo en la Slice B.
- Comparación temporal con una cola compartida y restauración automática.

## Flexible Channels

- Estado de direccionamiento, clases y filtros.
- Conectividad de ambos canales.
- Prueba individual del Canal A.
- Prueba individual del Canal B.
- Prueba simultánea de ambos canales.
- Contadores HTB y filtros.
- Sobresuscripción controlada.
- Cambio dinámico de capacidad total y asignaciones A/B.

## Criterios

Las pruebas estables utilizan una tasa ofrecida inferior al límite configurado para evitar que las cabeceras y las variaciones instantáneas produzcan una sobresuscripción involuntaria.
