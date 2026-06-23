# Resolución de problemas

## Un contenedor no está RUNNING

```bash
sudo lxc-info -n hs_h1
sudo vnx -f tfg_hardslicing_v1.xml --destroy
sudo vnx -f tfg_hardslicing_v1.xml --create
```

## iperf3 indica que el servidor está ocupado

```bash
for h in hs_h1 hs_h2 hs_h3 hs_h4; do
  sudo lxc-attach -n "$h" -- pkill -9 iperf3 2>/dev/null || true
done
```

## No aparecen las VLAN

Capture sobre la interfaz base `hs_r1 eth3`, no sobre las subinterfaces, y genere tráfico en ambas slices.

## Permission denied en resultados

```bash
sudo chown -R "$USER:$USER" automatizacion_tfg/resultados resultados_flexible 2>/dev/null || true
chmod -R u+rwX automatizacion_tfg/resultados resultados_flexible 2>/dev/null || true
```

## Persisten elementos del escenario anterior

Reprepare el escenario desde el controlador. La fase de limpieza elimina VRF, subinterfaces, qdisc, filtros y procesos residuales antes de aplicar la nueva configuración.
