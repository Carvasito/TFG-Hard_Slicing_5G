#!/usr/bin/env bash

validate_flexible_state() {
  local failed=0
  local node dev

  for node in hs_r1 hs_r2; do
    if lxc_cmd "$node" ip link show vrfA >/dev/null 2>&1 || \
       lxc_cmd "$node" ip link show vrfB >/dev/null 2>&1; then
      error "$node todavía contiene VRF"
      failed=1
    fi
  done

  for dev in eth3.10 eth3.20; do
    if lxc_cmd hs_r1 ip link show "$dev" >/dev/null 2>&1; then
      error "hs_r1 todavía contiene $dev"
      failed=1
    fi
  done

  lxc_cmd hs_r1 tc qdisc show dev eth3 | grep -q htb || {
    error "Falta HTB en hs_r1 eth3"
    failed=1
  }
  lxc_cmd hs_r1 tc class show dev eth3 | grep -q 'class htb 1:10' || {
    error "Falta la clase 1:10"
    failed=1
  }
  lxc_cmd hs_r1 tc class show dev eth3 | grep -q 'class htb 1:20' || {
    error "Falta la clase 1:20"
    failed=1
  }
  lxc_cmd hs_r1 tc filter show dev eth3 parent 1: | grep -q 'flowid 1:10' || {
    error "Falta el filtro del Canal A"
    failed=1
  }
  lxc_cmd hs_r1 tc filter show dev eth3 parent 1: | grep -q 'flowid 1:20' || {
    error "Falta el filtro del Canal B"
    failed=1
  }
  lxc_cmd hs_h1 ping -c 1 -W 2 "$FLEX_A_IP" >/dev/null 2>&1 || {
    error "No hay conectividad en el Canal A"
    failed=1
  }
  lxc_cmd hs_h2 ping -c 1 -W 2 "$FLEX_B_IP" >/dev/null 2>&1 || {
    error "No hay conectividad en el Canal B"
    failed=1
  }

  return "$failed"
}

read_flexible_profile() {
  local total_input a_input b_input

  echo
  echo "Configuración de Flexible Channels"
  read -r -p "Capacidad total [${FLEX_TOTAL_DEFAULT} Mbit/s]: " total_input
  read -r -p "Capacidad del Canal A [${FLEX_A_DEFAULT} Mbit/s]: " a_input
  read -r -p "Capacidad del Canal B [${FLEX_B_DEFAULT} Mbit/s]: " b_input

  FLEX_TOTAL="${total_input:-$FLEX_TOTAL_DEFAULT}"
  FLEX_A="${a_input:-$FLEX_A_DEFAULT}"
  FLEX_B="${b_input:-$FLEX_B_DEFAULT}"

  FLEX_TOTAL="${FLEX_TOTAL//,/.}"
  FLEX_A="${FLEX_A//,/.}"
  FLEX_B="${FLEX_B//,/.}"

  awk -v t="$FLEX_TOTAL" -v a="$FLEX_A" -v b="$FLEX_B" 'BEGIN {
    number = "^([0-9]+([.][0-9]+)?|[.][0-9]+)$"
    if (t !~ number || a !~ number || b !~ number) exit 1
    if (t <= 0 || a <= 0 || b <= 0 || a + b > t) exit 1
  }' || {
    error "Perfil inválido: se requieren valores positivos y debe cumplirse A+B<=total"
    return 1
  }
}

prepare_flexible() {
  read_flexible_profile || return 1

  CURRENT_SCENARIO="flexible"
  CURRENT_PROFILE="${FLEX_A}_${FLEX_B}"
  new_run_dir "$CURRENT_SCENARIO" "$CURRENT_PROFILE"
  stop_test_processes

  run_logged "00_configuracion_base" \
    bash "$PROJECT_ROOT/scripts_flexible/01_setup_flexible_channels_base.sh" || return 1

  info "Aplicando perfil Flexible Channels ${FLEX_A}/${FLEX_B} sobre ${FLEX_TOTAL} Mbit/s"
  if (cd "$PROJECT_ROOT" && \
      bash scripts_flexible/02_flexible_channel_controller.sh \
        --total "$FLEX_TOTAL" --a "$FLEX_A" --b "$FLEX_B") \
        2>&1 | tee "$RUN_DIR/01_perfil_flexible.log"; then
    record_result "perfil_flexible" "OK" \
      "total=$FLEX_TOTAL A=$FLEX_A B=$FLEX_B"
  else
    local rc=${PIPESTATUS[0]}
    error "No se pudo aplicar el perfil Flexible Channels (código $rc)"
    record_result "perfil_flexible" "ERROR" "codigo=$rc"
    return "$rc"
  fi

  cp -f "$PROJECT_ROOT/resultados_flexible/current_flexible_channels.conf" \
    "$RUN_DIR/perfil_aplicado.conf" 2>/dev/null || true

  if validate_flexible_state 2>&1 | tee "$RUN_DIR/02_verificacion_escenario.log"; then
    ok "Escenario Flexible Channels preparado y validado"
    record_result "verificacion_escenario" "OK" \
      "sin VRF/VLAN; HTB en interfaz base; conectividad correcta"
  else
    error "El escenario Flexible Channels no supera la validación"
    record_result "verificacion_escenario" "ERROR" \
      "$RUN_DIR/02_verificacion_escenario.log"
    return 1
  fi
}

fx_show_state() {
  {
    echo "===== Direccionamiento hs_r1 ====="
    lxc_cmd hs_r1 ip -4 addr
    echo "===== Direccionamiento hs_r2 ====="
    lxc_cmd hs_r2 ip -4 addr
    echo "===== HTB hs_r1 eth3 ====="
    lxc_cmd hs_r1 tc -s qdisc show dev eth3
    lxc_cmd hs_r1 tc -s class show dev eth3
    echo "===== Filtros hs_r1 eth3 ====="
    lxc_cmd hs_r1 tc filter show dev eth3 parent 1:
    echo "===== HTB hs_r2 eth1 ====="
    lxc_cmd hs_r2 tc -s class show dev eth1
    echo "===== Perfil aplicado ====="
    cat "$PROJECT_ROOT/resultados_flexible/current_flexible_channels.conf"
  } | tee "$RUN_DIR/fx_estado_completo.log"
  record_result "estado_flexible" "OK" "$RUN_DIR/fx_estado_completo.log"
}

fx_connectivity() {
  local failed=0
  lxc_cmd hs_h1 ping -c 3 "$FLEX_A_IP" | tee "$RUN_DIR/fx_ping_A.log" || failed=1
  lxc_cmd hs_h2 ping -c 3 "$FLEX_B_IP" | tee "$RUN_DIR/fx_ping_B.log" || failed=1
  if ((failed == 0)); then
    record_result "conectividad_flexible" "OK" "Canales A y B"
  else
    record_result "conectividad_flexible" "ERROR" "fallo de conectividad"
  fi
  return "$failed"
}

fx_test_single() {
  local channel="$1" ip rate host port log offered
  if [[ "$channel" == "A" ]]; then
    ip="$FLEX_A_IP"; rate="$FLEX_A"; host=hs_h1; port="$PORT_A"
  else
    ip="$FLEX_B_IP"; rate="$FLEX_B"; host=hs_h2; port="$PORT_B"
  fi
  offered="$(float_mul "$rate" 0.90)"
  start_iperf_servers || return 1
  log="$RUN_DIR/fx_individual_${channel}.log"
  lxc_cmd "$host" iperf3 -u -c "$ip" -p "$port" \
    -b "${offered}M" -t "$TEST_DURATION" -i 5 -l 1400 --udp-counters-64bit | tee "$log"
  stop_test_processes
  validate_iperf_result "flexible_individual_${channel}" "$log" "$offered"
}

fx_test_simultaneous() {
  local offered_a offered_b prefix="fx_simultanea" rc=0
  offered_a="$(float_mul "$FLEX_A" 0.90)"
  offered_b="$(float_mul "$FLEX_B" 0.90)"
  run_two_udp_clients "$FLEX_A_IP" "$offered_a" "$FLEX_B_IP" "$offered_b" "$prefix" || return 1
  validate_iperf_result "flexible_canal_A" "$RUN_DIR/${prefix}_A.log" "$offered_a" || rc=1
  validate_iperf_result "flexible_canal_B" "$RUN_DIR/${prefix}_B.log" "$offered_b" || rc=1
  fx_show_counters
  return "$rc"
}

fx_show_counters() {
  {
    echo "===== HTB hs_r1 eth3 ====="
    lxc_cmd hs_r1 tc -s qdisc show dev eth3
    lxc_cmd hs_r1 tc -s class show dev eth3
    echo "===== Filtros hs_r1 eth3 ====="
    lxc_cmd hs_r1 tc filter show dev eth3 parent 1:
    echo "===== HTB hs_r2 eth1 ====="
    lxc_cmd hs_r2 tc -s class show dev eth1
    echo "===== Filtros hs_r2 eth1 ====="
    lxc_cmd hs_r2 tc filter show dev eth1 parent 1:
  } | tee "$RUN_DIR/fx_contadores_htb.log"
  record_result "contadores_flexible" "OK" "$RUN_DIR/fx_contadores_htb.log"
}

fx_saturation_test() {
  run_two_udp_clients "$FLEX_A_IP" 20 "$FLEX_B_IP" 20 "fx_saturacion" || true
  fx_show_counters
  record_result "saturacion_flexible" "OK" \
    "tráfico ofrecido 20 Mbit/s por canal; revisar pérdidas y descartes"
}

fx_recommended_battery() {
  local failed=0
  fx_show_state || failed=1
  fx_connectivity || failed=1
  fx_test_single A || failed=1
  fx_test_single B || failed=1
  fx_test_simultaneous || failed=1
  fx_show_counters || failed=1
  return "$failed"
}

flexible_menu() {
  while true; do
    cat <<MENU

============================================================
 PRUEBAS: FLEXIBLE CHANNELS (${FLEX_A}/${FLEX_B} de ${FLEX_TOTAL} Mbit/s)
 Resultados: $RUN_DIR
============================================================
 1) Mostrar configuración, perfil, clases y filtros
 2) Validar conectividad de ambos canales
 3) Prueba individual del Canal A
 4) Prueba individual del Canal B
 5) Prueba simultánea de ambos canales
 6) Mostrar contadores HTB y filtros
 7) Prueba de saturación controlada
 8) Ejecutar batería recomendada
 9) Cambiar capacidades y repreparar el escenario
 0) Volver al menú principal
MENU
    read -r -p "Seleccione una o varias opciones separadas por espacios: " choices
    [[ "$choices" == "0" ]] && return 0
    local choice
    for choice in $choices; do
      case "$choice" in
        1) fx_show_state || true ;;
        2) fx_connectivity || true ;;
        3) fx_test_single A || true ;;
        4) fx_test_single B || true ;;
        5) fx_test_simultaneous || true ;;
        6) fx_show_counters || true ;;
        7) fx_saturation_test || true ;;
        8) fx_recommended_battery || true ;;
        9) prepare_flexible || true ;;
        *) warn "Opción no válida: $choice" ;;
      esac
    done
    pause
  done
}
