# Automatización transversal

Ejecute desde la raíz del repositorio:

```bash
./automatizacion_tfg/instalar.sh
./automatizacion_tfg/controlador_tfg.sh
```

El controlador permite seleccionar Channelized Subinterfaces o Flexible Channels, valida el estado de la maqueta y guarda cada ejecución en `automatizacion_tfg/resultados/`.

Para Flexible Channels solicita únicamente capacidad total, capacidad del Canal A y capacidad del Canal B. Se valida que los tres valores sean positivos y que `A+B<=total`.
