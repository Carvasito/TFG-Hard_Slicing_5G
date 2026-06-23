# Hard Slicing en redes de transporte 5G

Plataforma experimental para el diseño, configuración, automatización y validación de mecanismos de **hard slicing** en una red de transporte 5G virtualizada sobre Linux.

El repositorio forma parte del Trabajo Fin de Grado:

**Diseño e implementación de rodajas de red con recursos dedicados para redes de transporte 5G**

- **Autor:** Álvaro Carvajal Montes
- **Universidad:** Universidad Politécnica de Madrid
- **Escuela:** Escuela Técnica Superior de Ingenieros de Telecomunicación
- **Departamento:** DIT-UPM
- **Año:** 2026

---

## 1. Objetivo del proyecto

El objetivo de esta plataforma es estudiar cómo proporcionar aislamiento y control de capacidad entre varios flujos que comparten un mismo tramo de transporte.

Se implementan y evalúan dos escenarios independientes:

1. **Channelized Subinterfaces**
   - Separación de encaminamiento mediante VRF.
   - Separación lógica mediante VLAN y subinterfaces.
   - Políticas HTB independientes por subinterfaz.
   - Perfil principal: 6 Mbit/s para la Slice A y 3 Mbit/s para la Slice B.

2. **Flexible Channels**
   - Uso directo de la interfaz base compartida.
   - Clasificación mediante filtros IP.
   - Clases HTB independientes dentro de una jerarquía común.
   - Configuración dinámica de:
     - capacidad total;
     - capacidad del Canal A;
     - capacidad del Canal B.
   - Validación obligatoria:

     ```text
     Capacidad A + Capacidad B <= Capacidad total
     ```

La implementación es una **aproximación funcional basada en Linux**. No reproduce hardware FlexE ni funciones propietarias internas de equipos comerciales.

---

## 2. Arquitectura experimental

La topología está formada por cuatro hosts y dos routers Linux desplegados mediante VNX y contenedores LXC.

```text
hs_h1 ---- hs_r1 ===== hs_r2 ---- hs_h3
              ||         ||
hs_h2 --------           -------- hs_h4
```

El tramo compartido principal es:

```text
hs_r1 eth3 <-> hs_r2 eth1
```

Flujos utilizados:

```text
Flujo A: hs_h1 -> hs_r1 -> hs_r2 -> hs_h3
Flujo B: hs_h2 -> hs_r1 -> hs_r2 -> hs_h4
```

---

## 3. Escenarios implementados

### 3.1. Channelized Subinterfaces

Cada slice utiliza:

- una VRF propia;
- una VLAN propia;
- una subinterfaz propia;
- una tabla de encaminamiento independiente;
- una política HTB independiente.

Asignación principal:

| Elemento | Slice A | Slice B |
|---|---:|---:|
| VRF | `vrfA` | `vrfB` |
| Tabla de rutas | `10` | `20` |
| VLAN | `10` | `20` |
| Subinterfaz en `hs_r1` | `eth3.10` | `eth3.20` |
| Subinterfaz en `hs_r2` | `eth1.10` | `eth1.20` |
| Capacidad | `6 Mbit/s` | `3 Mbit/s` |

Este escenario permite validar:

- aislamiento de encaminamiento;
- ausencia de conectividad cruzada;
- uso simultáneo de VLAN 10 y VLAN 20;
- control de capacidad independiente;
- comportamiento bajo sobresuscripción;
- comparación frente a una cola compartida.

### 3.2. Flexible Channels

Los dos canales utilizan la misma interfaz base:

```text
hs_r1 eth3
```

La clasificación se realiza mediante dirección IP de destino:

| Canal | Destino | Clase HTB |
|---|---|---|
| Canal A | `10.0.3.2` | `1:10` |
| Canal B | `10.0.4.2` | `1:20` |
| Tráfico no clasificado | resto | `1:30` |

El controlador solicita únicamente:

```text
Capacidad total
Capacidad Canal A
Capacidad Canal B
```

No se utilizan slots ni tamaños de slot.

Ejemplo válido:

```text
Capacidad total: 10
Canal A: 6
Canal B: 3
```

Ejemplo inválido:

```text
Capacidad total: 10
Canal A: 8
Canal B: 3
```

El segundo ejemplo se rechaza porque `8 + 3 > 10`.

---

## 4. Estructura del repositorio

```text
tfg-hard-slicing-5g/
├── tfg_hardslicing_v1.xml
├── scripts_real/
│   ├── 00_prepare_real_hard_slicing.sh
│   ├── 01_setup_vrf_subinterfaces.sh
│   ├── 02_apply_hard_slicing_channels_tuned.sh
│   ├── 03_show_real_slicing.sh
│   ├── 04_test_vrf_isolation.sh
│   ├── 05_run_udp_hard_slicing_tests.sh
│   ├── 06_show_same_link_vlan_capture.sh
│   ├── 08_validacion_final_hard_slicing.sh
│   └── 09_setup_shared_queue_baseline.sh
├── scripts_flexible/
│   ├── 01_setup_flexible_channels_base.sh
│   ├── 02_flexible_channel_controller.sh
│   └── 03_test_flexible_channels.sh
├── automatizacion_tfg/
│   ├── controlador_tfg.sh
│   ├── instalar.sh
│   ├── README.md
│   ├── config/
│   │   └── automatizacion.conf
│   ├── lib/
│   │   ├── common.sh
│   │   ├── channelized.sh
│   │   └── flexible.sh
│   └── resultados/
│       └── .gitkeep
├── docs/
├── tools/
│   └── check_repository.sh
├── README.md
├── LICENSE
└── .gitignore
```

---

## 5. Requisitos

La plataforma está pensada para ejecutarse sobre Linux.

Dependencias principales:

- Bash;
- VNX;
- LXC;
- `iproute2`;
- `tc`;
- `ping`;
- `tcpdump`;
- `iperf3`;
- permisos de administración mediante `sudo`;
- módulos del kernel `vrf` y `8021q`.

Comprobación rápida:

```bash
for CMD in bash awk grep sed timeout tee lxc-attach lxc-info lxc-ls vnx ip tc ping iperf3 tcpdump; do
    command -v "$CMD" >/dev/null 2>&1 \
        && echo "[OK] $CMD" \
        || echo "[FALTA] $CMD"
done
```

Carga de módulos:

```bash
sudo modprobe vrf
sudo modprobe 8021q
```

---

## 6. Instalación

Clonar el repositorio:

```bash
git clone <URL_DEL_REPOSITORIO>
cd tfg-hard-slicing-5g
```

Aplicar permisos:

```bash
chmod +x tools/check_repository.sh
chmod +x automatizacion_tfg/*.sh
chmod +x automatizacion_tfg/lib/*.sh
chmod +x scripts_real/*.sh
chmod +x scripts_flexible/*.sh
```

Ejecutar el instalador:

```bash
./automatizacion_tfg/instalar.sh
```

Validar la estructura:

```bash
./tools/check_repository.sh
```

El resultado esperado es:

```text
Repositorio validado correctamente.
```

---

## 7. Despliegue de la maqueta

Crear el escenario:

```bash
sudo vnx -f tfg_hardslicing_v1.xml --create
```

Comprobar contenedores:

```bash
sudo lxc-ls --fancy
```

Deben aparecer en estado `RUNNING`:

```text
hs_h1
hs_h2
hs_h3
hs_h4
hs_r1
hs_r2
```

---

## 8. Ejecución del controlador

Desde la raíz del proyecto:

```bash
./automatizacion_tfg/controlador_tfg.sh
```

El menú principal permite:

- preparar Channelized Subinterfaces;
- preparar Flexible Channels;
- ejecutar comprobaciones previas;
- detener procesos de prueba;
- abrir la última carpeta de resultados;
- salir.

La preparación de cada escenario incluye:

1. limpieza de configuraciones incompatibles;
2. aplicación de direccionamiento y rutas;
3. configuración de interfaces o clases;
4. validación del estado resultante;
5. apertura de un menú de pruebas específico.

---

## 9. Pruebas de Channelized Subinterfaces

### 9.1. Preparación manual

```bash
sudo ./scripts_real/00_prepare_real_hard_slicing.sh
sudo ./scripts_real/01_setup_vrf_subinterfaces.sh
sudo ./scripts_real/02_apply_hard_slicing_channels_tuned.sh
sudo ./scripts_real/03_show_real_slicing.sh
```

### 9.2. Comprobación de VRF

```bash
sudo lxc-attach -n hs_r1 -- ip -d link show type vrf
sudo lxc-attach -n hs_r2 -- ip -d link show type vrf
```

### 9.3. Comprobación de subinterfaces

```bash
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.10
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.20
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.10
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.20
```

### 9.4. Validación de aislamiento

```bash
sudo ./scripts_real/04_test_vrf_isolation.sh
```

Debe existir conectividad interna:

```text
hs_h1 -> hs_h3
hs_h2 -> hs_h4
```

Deben fallar las comunicaciones cruzadas:

```text
hs_h1 -> hs_h4
hs_h2 -> hs_h3
```

### 9.5. Captura VLAN

```bash
sudo lxc-attach -n hs_r1 -- tcpdump -i eth3 -e -n 'vlan'
```

La captura debe mostrar tráfico con:

```text
vlan 10
vlan 20
```

### 9.6. Contadores HTB

```bash
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.10
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.20
```

---

## 10. Pruebas de Flexible Channels

### 10.1. Preparación manual

```bash
sudo ./scripts_flexible/01_setup_flexible_channels_base.sh
sudo ./scripts_flexible/02_flexible_channel_controller.sh
```

El controlador solicitará:

```text
Capacidad total
Capacidad Canal A
Capacidad Canal B
```

### 10.2. Ejecución no interactiva

```bash
sudo ./scripts_flexible/01_setup_flexible_channels_base.sh

./scripts_flexible/02_flexible_channel_controller.sh \
    --total 10 \
    --a 6 \
    --b 3
```

### 10.3. Comprobación de clases

```bash
sudo lxc-attach -n hs_r1 -- tc -s qdisc show dev eth3
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3
sudo lxc-attach -n hs_r1 -- tc filter show dev eth3 parent 1:
```

Deben aparecer:

```text
class htb 1:1
class htb 1:10
class htb 1:20
class htb 1:30
```

### 10.4. Conectividad

```bash
sudo lxc-attach -n hs_h1 -- ping -c 3 10.0.3.2
sudo lxc-attach -n hs_h2 -- ping -c 3 10.0.4.2
```

### 10.5. Pruebas de tráfico

```bash
sudo ./scripts_flexible/03_test_flexible_channels.sh
```

---

## 11. Automatización y trazabilidad

Cada preparación crea un directorio independiente dentro de:

```text
automatizacion_tfg/resultados/
```

Formato de nombre:

```text
AAAAMMDD_HHMMSS_<escenario>_<perfil>
```

Ejemplos:

```text
20260623_120000_channelized_6_3
20260623_121500_flexible_6_3
```

Cada ejecución puede incluir:

```text
metadata.txt
resultados.tsv
perfil_aplicado.conf
*.log
```

El enlace:

```text
automatizacion_tfg/resultados/ultima_ejecucion
```

apunta a la ejecución más reciente.

Consulta rápida:

```bash
cat automatizacion_tfg/resultados/ultima_ejecucion/resultados.tsv
```

---

## 12. Limpieza y apagado

Detener procesos de prueba:

```bash
for NODO in hs_h1 hs_h2 hs_h3 hs_h4 hs_r1 hs_r2; do
    sudo lxc-attach -n "$NODO" -- pkill iperf3 2>/dev/null || true
    sudo lxc-attach -n "$NODO" -- pkill ping 2>/dev/null || true
    sudo lxc-attach -n "$NODO" -- pkill tcpdump 2>/dev/null || true
done
```

Eliminar el escenario:

```bash
sudo vnx -f tfg_hardslicing_v1.xml --destroy
```

---

## 13. Validación del repositorio

Comprobación estática:

```bash
./tools/check_repository.sh
```

Comprobación de sintaxis Bash:

```bash
find . -name "*.sh" -type f -exec bash -n {} \;
```

Búsqueda de errores en resultados:

```bash
grep -RniE 'ERROR|command not found|No such file|Permission denied' \
    automatizacion_tfg/resultados/
```

---

## 14. Resultados principales del TFG

El perfil principal utilizado en ambos escenarios es:

```text
Slice o Canal A: 6 Mbit/s
Slice o Canal B: 3 Mbit/s
```

En las pruebas de sobresuscripción:

- Channelized Subinterfaces mantuvo estable el tráfico de la Slice A mientras la Slice B ofrecía tráfico por encima de su capacidad.
- Flexible Channels limitó el exceso dentro de la clase asociada al Canal B, manteniendo estable el tráfico del Canal A.
- La comparación frente a una cola compartida mostró una degradación significativa cuando ambos flujos competían en la misma cola.

Los valores exactos, capturas y discusión completa se documentan en la memoria del TFG.

---

## 15. Alcance y limitaciones

La plataforma demuestra:

- separación de encaminamiento mediante VRF;
- diferenciación mediante VLAN y subinterfaces;
- control de capacidad mediante HTB;
- clasificación por filtros;
- comportamiento bajo tráfico simultáneo;
- aislamiento funcional ante sobresuscripción;
- automatización y trazabilidad de pruebas.

La plataforma no demuestra:

- reserva física de recursos;
- implementación hardware FlexE;
- arquitectura interna de equipos comerciales;
- garantías equivalentes a un despliegue de operador;
- caracterización estadística completa del rendimiento.

Las conclusiones deben interpretarse dentro del alcance de una plataforma virtualizada basada en Linux, VNX y LXC.

---

## 16. Reproducibilidad

Para reproducir el entorno:

1. instalar VNX, LXC y las dependencias;
2. clonar el repositorio;
3. ejecutar `./tools/check_repository.sh`;
4. crear la maqueta VNX;
5. ejecutar `./automatizacion_tfg/controlador_tfg.sh`;
6. seleccionar el escenario;
7. ejecutar las pruebas;
8. consultar los resultados generados.

---

## 17. Versión asociada a la memoria

La versión estable asociada a la memoria puede publicarse mediante una etiqueta Git:

```bash
git tag -a v1.0-TFG -m "Versión asociada a la memoria del TFG"
git push origin v1.0-TFG
```

También puede identificarse mediante el commit exacto:

```bash
git rev-parse HEAD
```

---

## 18. Autor

**Álvaro Carvajal Montes**

Trabajo Fin de Grado, Universidad Politécnica de Madrid, 2026.

---


