# Hard Slicing en redes de transporte 5G

Plataforma experimental para diseñar, configurar, automatizar y validar mecanismos de **hard slicing** en una red de transporte 5G virtualizada sobre Linux.

Este repositorio forma parte del Trabajo Fin de Grado:

**Diseño e implementación de rodajas de red con recursos dedicados para redes de transporte 5G**

- **Autor:** Álvaro Carvajal Montes
- **Universidad:** Universidad Politécnica de Madrid
- **Escuela:** Escuela Técnica Superior de Ingenieros de Telecomunicación
- **Departamento:** DIT-UPM
- **Año:** 2026

---

## 1. Alcance del proyecto

La plataforma evalúa dos escenarios independientes sobre una topología común formada por cuatro hosts y dos routers Linux:

1. **Channelized Subinterfaces**
   - separación de encaminamiento mediante VRF;
   - diferenciación mediante VLAN y subinterfaces;
   - políticas HTB independientes por subinterfaz;
   - perfil principal de 6 Mbit/s para la Slice A y 3 Mbit/s para la Slice B.

2. **Flexible Channels**
   - utilización directa de la interfaz base compartida;
   - clasificación mediante filtros IP;
   - clases HTB independientes dentro de una jerarquía común;
   - configuración dinámica de la capacidad total y de las asignaciones de los canales A y B;
   - validación obligatoria de que `A + B <= capacidad total`.

La implementación es una **aproximación funcional basada en Linux**. No implementa hardware FlexE ni reproduce funciones propietarias internas de equipos comerciales.

---

## 2. Arquitectura experimental

La topología se define en:

```text
tfg_hardslicing_v1.xml
```

Nodos:

```text
hs_h1 ---- hs_r1 ===== hs_r2 ---- hs_h3
              ||         ||
hs_h2 --------           -------- hs_h4
```

Flujos principales:

```text
Flujo A: hs_h1 -> hs_r1 -> hs_r2 -> hs_h3
Flujo B: hs_h2 -> hs_r1 -> hs_r2 -> hs_h4
```

Tramo de transporte compartido:

```text
hs_r1 eth3 <-> hs_r2 eth1
```

---

## 3. Estructura del repositorio

```text
TFG-Hard_Slicing_5G/
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
│   ├── ARQUITECTURA.md
│   ├── PRUEBAS.md
│   └── RESOLUCION_DE_PROBLEMAS.md
├── tools/
│   └── check_repository.sh
├── README.md
├── LICENSE
└── .gitignore
```

---

## 4. Entorno necesario

La plataforma necesita un sistema Linux con **VNX** y **LXC** operativos. El repositorio contiene el escenario y los scripts, pero no instala VNX ni crea su sistema de archivos base.

### 4.1. Dependencias del equipo anfitrión

Herramientas requeridas:

- Git;
- Bash;
- VNX;
- LXC;
- `sudo`;
- `awk`;
- `grep`;
- `sed`;
- `date`;
- `timeout`;
- `tee`;
- `iproute2`;
- `ping`;
- `iperf3`;
- `tcpdump`;
- `procps`;
- módulos del kernel `vrf` y `8021q`.

En una distribución basada en Debian o Ubuntu pueden instalarse las herramientas disponibles en los repositorios mediante:

```bash
sudo apt update
sudo apt install -y \
  git bash gawk grep sed coreutils \
  lxc lxc-utils \
  iproute2 iputils-ping \
  iperf3 tcpdump procps
```

VNX debe instalarse siguiendo la documentación oficial del DIT-UPM. Después de instalarlo, debe existir el comando:

```bash
command -v vnx
```

Comprobación completa del anfitrión:

```bash
for CMD in \
  git bash sudo awk grep sed date timeout tee \
  lxc-attach lxc-info lxc-ls \
  vnx ip tc ping iperf3 tcpdump pkill ss; do
    if command -v "$CMD" >/dev/null 2>&1; then
        echo "[OK] $CMD"
    else
        echo "[FALTA] $CMD"
    fi
done
```

### 4.2. Módulos del kernel

Cargar los módulos requeridos:

```bash
sudo modprobe vrf
sudo modprobe 8021q
```

Comprobarlos:

```bash
lsmod | grep -E '(^vrf|8021q)'
```

### 4.3. Sistema de archivos utilizado por VNX

El fichero XML utiliza esta imagen LXC:

```text
/usr/share/vnx/filesystems/rootfs_lxc_modern
```

Debe existir antes de desplegar la maqueta:

```bash
if [ -e /usr/share/vnx/filesystems/rootfs_lxc_modern ]; then
    echo "[OK] rootfs_lxc_modern disponible"
else
    echo "[ERROR] Falta /usr/share/vnx/filesystems/rootfs_lxc_modern"
fi
```

Si no existe, debe instalarse o prepararse conforme a la documentación de VNX antes de continuar.

### 4.4. Herramientas requeridas dentro de los contenedores

Los hosts `hs_h1`, `hs_h2`, `hs_h3` y `hs_h4` necesitan:

```text
ip
ping
iperf3
pkill
ss
```

Los routers `hs_r1` y `hs_r2` necesitan:

```text
ip
tc
ping
tcpdump
```

El controlador comprueba automáticamente estas dependencias durante la fase de comprobaciones previas.

Si la imagen LXC está basada en Debian o Ubuntu y falta alguna herramienta, puede instalarse dentro del contenedor correspondiente. Ejemplo:

```bash
sudo lxc-attach -n hs_h1 -- apt update
sudo lxc-attach -n hs_h1 -- apt install -y \
  iproute2 iputils-ping iperf3 procps
```

Para los routers:

```bash
sudo lxc-attach -n hs_r1 -- apt update
sudo lxc-attach -n hs_r1 -- apt install -y \
  iproute2 iputils-ping tcpdump procps
```

Repita la instalación en los demás nodos que lo necesiten.

---

## 5. Descarga del repositorio

Clonar el proyecto usando un nombre local uniforme:

```bash
git clone \
  https://github.com/Carvasito/TFG-Hard_Slicing_5G.git \
  tfg-hard-slicing-5g

cd tfg-hard-slicing-5g
```

Comprobar el contenido:

```bash
ls
```

Deben aparecer:

```text
README.md
LICENSE
tfg_hardslicing_v1.xml
scripts_real
scripts_flexible
automatizacion_tfg
docs
tools
```

---

## 6. Preparación inicial

Aplicar permisos de ejecución:

```bash
chmod +x tools/check_repository.sh
chmod +x automatizacion_tfg/*.sh
chmod +x automatizacion_tfg/lib/*.sh
chmod +x scripts_real/*.sh
chmod +x scripts_flexible/*.sh
```

Ejecutar el preparador local:

```bash
./automatizacion_tfg/instalar.sh
```

Este script **no instala VNX ni paquetes del sistema**. Su función es:

- aplicar permisos a la automatización;
- crear el directorio de resultados;
- mostrar el comando de ejecución del controlador.

Validar el contenido del repositorio:

```bash
./tools/check_repository.sh
```

Resultado esperado:

```text
Repositorio validado correctamente.
```

El comprobador revisa:

- existencia de los ficheros esenciales;
- sintaxis Bash;
- permisos de ejecución;
- ausencia de rutas y nombres obsoletos en los componentes principales.

---

## 7. Despliegue de la maqueta VNX

La automatización puede intentar iniciar VNX cuando detecta que los contenedores no están activos. No obstante, para la primera ejecución se recomienda desplegar la maqueta manualmente y comprobar el resultado.

Crear el escenario:

```bash
sudo vnx -f tfg_hardslicing_v1.xml --create
```

Comprobar los contenedores:

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

Comprobación individual:

```bash
for NODO in hs_h1 hs_h2 hs_h3 hs_h4 hs_r1 hs_r2; do
    echo "===== $NODO ====="
    sudo lxc-info -n "$NODO"
done
```

Si alguno no está activo, no continúe con las pruebas. Revise primero:

- instalación de VNX;
- estado de LXC;
- existencia de `rootfs_lxc_modern`;
- salida del comando de creación;
- posibles escenarios VNX parciales anteriores.

Para destruir un estado parcial:

```bash
sudo vnx -f tfg_hardslicing_v1.xml --destroy
```

Después puede volver a crearse:

```bash
sudo vnx -f tfg_hardslicing_v1.xml --create
```

---

## 8. Ejecución recomendada

Con los contenedores activos, ejecutar:

```bash
./automatizacion_tfg/controlador_tfg.sh
```

El menú principal permite:

1. preparar Channelized Subinterfaces y abrir sus pruebas;
2. preparar Flexible Channels y abrir sus pruebas;
3. ejecutar comprobaciones previas;
4. detener procesos de prueba;
5. abrir la última carpeta de resultados;
6. salir.

En la primera ejecución se recomienda seleccionar primero:

```text
Ejecutar comprobaciones previas
```

El controlador valida:

- permisos `sudo`;
- dependencias del anfitrión;
- scripts requeridos;
- estado de los seis contenedores;
- comandos necesarios dentro de cada contenedor.

La preparación de un escenario solo debe considerarse válida cuando el controlador muestra que todas sus comprobaciones han sido superadas.

---

## 9. Channelized Subinterfaces

### 9.1. Diseño aplicado

| Elemento | Slice A | Slice B |
|---|---:|---:|
| Flujo | `hs_h1 -> hs_h3` | `hs_h2 -> hs_h4` |
| VRF | `vrfA` | `vrfB` |
| Tabla de rutas | `10` | `20` |
| VLAN | `10` | `20` |
| Subinterfaz en `hs_r1` | `eth3.10` | `eth3.20` |
| Subinterfaz en `hs_r2` | `eth1.10` | `eth1.20` |
| Límite HTB | `6 Mbit/s` | `3 Mbit/s` |

Las políticas de capacidad se aplican principalmente en el sentido:

```text
hs_r1 -> hs_r2
```

### 9.2. Preparación manual

```bash
sudo ./scripts_real/00_prepare_real_hard_slicing.sh
sudo ./scripts_real/01_setup_vrf_subinterfaces.sh
sudo ./scripts_real/02_apply_hard_slicing_channels_tuned.sh
sudo ./scripts_real/03_show_real_slicing.sh
sudo ./scripts_real/04_test_vrf_isolation.sh
```

### 9.3. Comprobación de VRF y rutas

```bash
sudo lxc-attach -n hs_r1 -- ip -d link show type vrf
sudo lxc-attach -n hs_r1 -- ip route show vrf vrfA
sudo lxc-attach -n hs_r1 -- ip route show vrf vrfB

sudo lxc-attach -n hs_r2 -- ip -d link show type vrf
sudo lxc-attach -n hs_r2 -- ip route show vrf vrfA
sudo lxc-attach -n hs_r2 -- ip route show vrf vrfB
```

### 9.4. Comprobación de subinterfaces

```bash
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.10
sudo lxc-attach -n hs_r1 -- ip -d link show eth3.20
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.10
sudo lxc-attach -n hs_r2 -- ip -d link show eth1.20
```

### 9.5. Aislamiento de encaminamiento

```bash
sudo ./scripts_real/04_test_vrf_isolation.sh
```

Resultados esperados:

```text
hs_h1 -> hs_h3: conectividad
hs_h2 -> hs_h4: conectividad
hs_h1 -> hs_h4: sin conectividad
hs_h2 -> hs_h3: sin conectividad
```

### 9.6. Captura VLAN

Con tráfico activo en ambas slices:

```bash
sudo lxc-attach -n hs_r1 -- \
  tcpdump -i eth3 -e -n 'vlan'
```

La captura debe mostrar tráfico con:

```text
vlan 10
vlan 20
```

### 9.7. Contadores HTB

```bash
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.10
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3.20
```

---

## 10. Flexible Channels

### 10.1. Diseño aplicado

Los dos canales comparten:

```text
hs_r1 eth3
```

Clasificación principal:

| Canal | Destino | Clase HTB |
|---|---|---|
| Canal A | `10.0.3.2` | `1:10` |
| Canal B | `10.0.4.2` | `1:20` |
| Tráfico no clasificado | resto | `1:30` |

El controlador solicita:

```text
capacidad total
capacidad Canal A
capacidad Canal B
```

Debe cumplirse:

```text
A + B <= capacidad total
```

No se utilizan parámetros adicionales de granularidad.

### 10.2. Preparación interactiva

```bash
sudo ./scripts_flexible/01_setup_flexible_channels_base.sh
./scripts_flexible/02_flexible_channel_controller.sh
```

### 10.3. Preparación no interactiva

Perfil principal:

```bash
sudo ./scripts_flexible/01_setup_flexible_channels_base.sh

./scripts_flexible/02_flexible_channel_controller.sh \
  --total 10 \
  --a 6 \
  --b 3
```

Se admiten valores decimales con punto o coma.

Ejemplo válido:

```bash
./scripts_flexible/02_flexible_channel_controller.sh \
  --total 12 \
  --a 7 \
  --b 4
```

Ejemplo inválido:

```bash
./scripts_flexible/02_flexible_channel_controller.sh \
  --total 10 \
  --a 8 \
  --b 3
```

El último perfil debe rechazarse antes de modificar la jerarquía porque `8 + 3 > 10`.

### 10.4. Comprobación de clases y filtros

```bash
sudo lxc-attach -n hs_r1 -- tc -s qdisc show dev eth3
sudo lxc-attach -n hs_r1 -- tc -s class show dev eth3
sudo lxc-attach -n hs_r1 -- tc filter show dev eth3 parent 1:
```

Deben aparecer las clases:

```text
1:1
1:10
1:20
1:30
```

### 10.5. Conectividad

```bash
sudo lxc-attach -n hs_h1 -- ping -c 3 10.0.3.2
sudo lxc-attach -n hs_h2 -- ping -c 3 10.0.4.2
```

### 10.6. Pruebas específicas

```bash
sudo ./scripts_flexible/03_test_flexible_channels.sh
```

También pueden ejecutarse desde el menú Flexible Channels del controlador transversal.

---

## 11. Resultados y trazabilidad

Cada preparación automatizada crea un directorio independiente:

```text
automatizacion_tfg/resultados/
└── AAAAMMDD_HHMMSS_escenario_perfil/
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
ls -la automatizacion_tfg/resultados
cat automatizacion_tfg/resultados/ultima_ejecucion/metadata.txt
cat automatizacion_tfg/resultados/ultima_ejecucion/resultados.tsv
```

Los resultados locales están excluidos del control de versiones mediante `.gitignore`.

---

## 12. Configuración general de las pruebas

Los parámetros generales se encuentran en:

```text
automatizacion_tfg/config/automatizacion.conf
```

Valores principales de la versión publicada:

```text
Duración de tráfico: 30 s
Duración de RTT: 20 s
Duración de captura: 15 s
Puerto Canal A: 5001
Puerto Canal B: 5002
Channelized A: 6 Mbit/s
Channelized B: 3 Mbit/s
Tasa estable A: 5,20 Mbit/s
Tasa estable B: 2,60 Mbit/s
Flexible total: 10 Mbit/s
Flexible A: 6 Mbit/s
Flexible B: 3 Mbit/s
```

Antes de modificar estos valores, debe comprobarse que las tasas ofrecidas y los límites siguen siendo coherentes con las validaciones implementadas.

---

## 13. Detención y limpieza

Detener procesos de prueba:

```bash
for NODO in hs_h1 hs_h2 hs_h3 hs_h4; do
    sudo lxc-attach -n "$NODO" -- pkill -x iperf3 2>/dev/null || true
    sudo lxc-attach -n "$NODO" -- pkill -x iperf 2>/dev/null || true
    sudo lxc-attach -n "$NODO" -- pkill -x ping 2>/dev/null || true
done

for NODO in hs_r1 hs_r2; do
    sudo lxc-attach -n "$NODO" -- pkill -x tcpdump 2>/dev/null || true
done
```

Destruir la maqueta:

```bash
sudo vnx -f tfg_hardslicing_v1.xml --destroy
```

---

## 14. Resolución de problemas

### 14.1. `vnx: command not found`

VNX no está instalado o no se encuentra en `PATH`.

```bash
command -v vnx
```

Instale VNX conforme a la documentación oficial del DIT-UPM y vuelva a abrir el terminal.

### 14.2. Falta `rootfs_lxc_modern`

Comprobar:

```bash
ls -ld /usr/share/vnx/filesystems/rootfs_lxc_modern
```

La imagen debe instalarse o generarse antes de desplegar el escenario.

### 14.3. Un contenedor no está `RUNNING`

```bash
sudo lxc-info -n hs_h1
```

Destruir un posible estado parcial y recrear:

```bash
sudo vnx -f tfg_hardslicing_v1.xml --destroy
sudo vnx -f tfg_hardslicing_v1.xml --create
```

### 14.4. Falta una herramienta dentro de un contenedor

Ejemplo:

```bash
sudo lxc-attach -n hs_h1 -- command -v iperf3
```

Instale el paquete correspondiente dentro de la imagen o del contenedor y repita las comprobaciones previas.

### 14.5. `iperf3` indica que el servidor está ocupado

```bash
for NODO in hs_h1 hs_h2 hs_h3 hs_h4; do
    sudo lxc-attach -n "$NODO" -- pkill -x iperf3 2>/dev/null || true
done
```

Después vuelva a ejecutar la prueba.

### 14.6. No aparecen VLAN en `tcpdump`

Compruebe que:

- captura sobre `hs_r1 eth3`;
- las dos slices están generando tráfico;
- existen `eth3.10` y `eth3.20`;
- se ha preparado el escenario Channelized Subinterfaces.

### 14.7. `Permission denied` en resultados

```bash
sudo chown -R "$USER:$USER" automatizacion_tfg/resultados
chmod -R u+rwX automatizacion_tfg/resultados
```

Aplique estos permisos únicamente sobre el directorio de resultados.

### 14.8. Persisten elementos del escenario anterior

No corrija únicamente una interfaz aislada. Vuelva al menú principal y prepare de nuevo el escenario deseado. La automatización elimina las configuraciones incompatibles antes de aplicar la nueva.

### 14.9. La validación estática falla por permisos

```bash
chmod +x tools/check_repository.sh
chmod +x automatizacion_tfg/*.sh
chmod +x automatizacion_tfg/lib/*.sh
chmod +x scripts_real/*.sh
chmod +x scripts_flexible/*.sh

./tools/check_repository.sh
```

---

## 15. Secuencia mínima completa

Una vez instalados VNX, LXC y las dependencias:

```bash
git clone \
  https://github.com/Carvasito/TFG-Hard_Slicing_5G.git \
  tfg-hard-slicing-5g

cd tfg-hard-slicing-5g

chmod +x tools/check_repository.sh
chmod +x automatizacion_tfg/*.sh
chmod +x automatizacion_tfg/lib/*.sh
chmod +x scripts_real/*.sh
chmod +x scripts_flexible/*.sh

./automatizacion_tfg/instalar.sh
./tools/check_repository.sh

sudo modprobe vrf
sudo modprobe 8021q

test -e /usr/share/vnx/filesystems/rootfs_lxc_modern

sudo vnx -f tfg_hardslicing_v1.xml --create
sudo lxc-ls --fancy

./automatizacion_tfg/controlador_tfg.sh
```

La ejecución solo debe continuar si:

- `check_repository.sh` termina correctamente;
- existe `rootfs_lxc_modern`;
- los seis contenedores están en estado `RUNNING`;
- las comprobaciones previas del controlador se superan.

---

## 16. Reproducibilidad y limitaciones

El repositorio permite reproducir:

- la topología VNX;
- la configuración de VRF;
- las VLAN y subinterfaces;
- las jerarquías HTB;
- los filtros de clasificación;
- las pruebas de conectividad;
- las pruebas de caudal;
- las capturas VLAN;
- las pruebas de sobresuscripción;
- la comparación con cola compartida;
- la generación estructurada de resultados.

La plataforma no garantiza compatibilidad con cualquier distribución, versión de VNX, versión del kernel o imagen LXC. El comportamiento validado corresponde a un entorno Linux compatible con los requisitos descritos.

La maqueta demuestra aislamiento y control de capacidad mediante mecanismos software. No demuestra:

- reserva física de recursos;
- implementación hardware FlexE;
- arquitectura interna de equipos comerciales;
- prestaciones equivalentes a una red de operador;
- escalabilidad estadística o de gran tamaño.

---

## 17. Documentación adicional

- [Arquitectura](docs/ARQUITECTURA.md)
- [Pruebas disponibles](docs/PRUEBAS.md)
- [Resolución de problemas](docs/RESOLUCION_DE_PROBLEMAS.md)
- [Automatización](automatizacion_tfg/README.md)

---

## 18. Versión asociada al TFG

Repositorio:

```text
https://github.com/Carvasito/TFG-Hard_Slicing_5G
```

Para identificar una versión concreta:

```bash
git rev-parse HEAD
```

Si existe una etiqueta estable:

```bash
git checkout v1.0-TFG
```

---

## 19. Licencia

El proyecto se distribuye bajo la licencia incluida en:

```text
LICENSE
```

---

## 20. Autor

**Álvaro Carvajal Montes**  
Trabajo Fin de Grado  
Universidad Politécnica de Madrid  
2026
