#!/usr/bin/env bash

validate_channelized_state() {
  local failed=0
  for node in hs_r1 hs_r2; do
    lxc_cmd "$node" ip link show vrfA >/dev/null 2>&1 || { error "$node: falta vrfA"; failed=1; }
    lxc_cmd "$node" ip link show vrfB >/dev/null 2>&1 || { error "$node: falta vrfB"; failed=1; }
  done
  lxc_cmd hs_r1 ip link show eth3.10 >/dev/null 2>&1 || { error "hs_r1: falta eth3.10"; failed=1; }
  lxc_cmd hs_r1 ip link show eth3.20 >/dev/null 2>&1 || { error "hs_r1: falta eth3.20"; failed=1; }
  lxc_cmd hs_r2 ip link show eth1.10 >/dev/null 2>&1 || { error "hs_r2: falta eth1.10"; failed=1; }
  lxc_cmd hs_r2 ip link show eth1.20 >/dev/null 2>&1 || { error "hs_r2: falta eth1.20"; failed=1; }
  lxc_cmd hs_r1 tc qdisc show dev eth3.10 | grep -q htb || { error "Falta HTB en hs_r1 eth3.10"; failed=1; }
  lxc_cmd hs_r1 tc qdisc show dev eth3.20 | grep -q htb || { error "Falta HTB en hs_r1 eth3.20"; failed=1; }
  lxc_cmd hs_h1 ping -c 1 -W 2 "$CH_A_IP" >/dev/null 2>&1 || { error "No hay conectividad Slice A"; failed=1; }
  lxc_cmd hs_h2 ping -c 1 -W 2 "$CH_B_IP" >/dev/null 2>&1 || { error "No hay conectividad Slice B"; failed=1; }
  return "$failed"
}

prepare_channelized() {
  CURRENT_SCENARIO="channelized"
  CURRENT_PROFILE="${CH_A_LIMIT_MBIT}_${CH_B_LIMIT_MBIT}"
  new_run_dir "$CURRENT_SCENARIO" "$CURRENT_PROFILE"
  stop_test_processes
  run_logged "00_configuracion_vrf_vlan" bash "$PROJECT_ROOT/scripts_real/01_setup_vrf_subinterfaces.sh" || return 1
  if ! (cd "$PROJECT_ROOT" && SLICE_A_RATE="${CH_A_LIMIT_MBIT}mbit" SLICE_B_RATE="${CH_B_LIMIT_MBIT}mbit" bash scripts_real/02_apply_hard_slicing_channels_tuned.sh) 2>&1 | tee "$RUN_DIR/01_aplicacion_htb.log"; then
    error "No se pudo aplicar HTB channelized"
    record_result "aplicacion_htb" "ERROR" "$RUN_DIR/01_aplicacion_htb.log"
    return 1
  fi
  record_result "aplicacion_htb" "OK" "$RUN_DIR/01_aplicacion_htb.log"
  if validate_channelized_state 2>&1 | tee "$RUN_DIR/02_verificacion_escenario.log"; then
    ok "Escenario Channelized preparado y validado"
    record_result "verificacion_escenario" "OK" "VRF,VLAN,HTB,conectividad"
  else
    error "El escenario Channelized no supera la validación"
    record_result "verificacion_escenario" "ERROR" "$RUN_DIR/02_verificacion_escenario.log"
    return 1
  fi
}

ch_show_state() {
  run_logged "ch_estado_completo" bash "$PROJECT_ROOT/scripts_real/03_show_real_slicing.sh"
}

ch_test_isolation() {
  run_logged "ch_aislamiento" bash "$PROJECT_ROOT/scripts_real/04_test_vrf_isolation.sh"
}

ch_test_throughput() {
  local prefix="ch_caudal_estable"
  if run_two_udp_clients "$CH_A_IP" "$CH_A_STABLE_MBIT" "$CH_B_IP" "$CH_B_STABLE_MBIT" "$prefix"; then
    local rc=0
    validate_iperf_result "channelized_slice_A" "$RUN_DIR/${prefix}_A.log" "$CH_A_STABLE_MBIT" || rc=1
    validate_iperf_result "channelized_slice_B" "$RUN_DIR/${prefix}_B.log" "$CH_B_STABLE_MBIT" || rc=1
    {
      echo "===== hs_r1 eth3.10 ====="; lxc_cmd hs_r1 tc -s class show dev eth3.10
      echo "===== hs_r1 eth3.20 ====="; lxc_cmd hs_r1 tc -s class show dev eth3.20
    } | tee "$RUN_DIR/${prefix}_tc.log"
    return "$rc"
  fi
  return 1
}

ch_capture_vlans() {
  local cap="$RUN_DIR/ch_captura_vlan.log"
  stop_test_processes
  info "Capturando VLAN 10 y 20 durante ${CAPTURE_DURATION}s"
  (timeout "$CAPTURE_DURATION" sudo lxc-attach -n hs_r1 -- tcpdump -i eth3 -e -n -l 'vlan' > "$cap" 2>&1) &
  local cap_pid=$!
  sleep 2
  lxc_cmd hs_h1 ping -c 4 "$CH_A_IP" >/dev/null 2>&1 || true
  lxc_cmd hs_h2 ping -c 4 "$CH_B_IP" >/dev/null 2>&1 || true
  wait "$cap_pid" || true
  cat "$cap"
  local ok10=0 ok20=0
  grep -Eq 'vlan 10[, ]' "$cap" && ok10=1
  grep -Eq 'vlan 20[, ]' "$cap" && ok20=1
  if (( ok10 && ok20 )); then
    ok "La captura contiene VLAN 10 y VLAN 20"
    record_result "captura_vlan" "OK" "VLAN10 y VLAN20"
  else
    error "No se han observado ambas VLAN en la captura"
    record_result "captura_vlan" "ERROR" "vlan10=$ok10 vlan20=$ok20"
    return 1
  fi
}

ch_show_counters() {
  {
    echo "===== hs_r1 eth3.10 ====="; lxc_cmd hs_r1 tc -s qdisc show dev eth3.10; lxc_cmd hs_r1 tc -s class show dev eth3.10
    echo "===== hs_r1 eth3.20 ====="; lxc_cmd hs_r1 tc -s qdisc show dev eth3.20; lxc_cmd hs_r1 tc -s class show dev eth3.20
    echo "===== hs_r2 eth1.10 ====="; lxc_cmd hs_r2 tc -s class show dev eth1.10
    echo "===== hs_r2 eth1.20 ====="; lxc_cmd hs_r2 tc -s class show dev eth1.20
  } | tee "$RUN_DIR/ch_contadores_htb.log"
  record_result "contadores_htb" "OK" "$RUN_DIR/ch_contadores_htb.log"
}

ch_test_rtt_isolation() {
  local solo="$RUN_DIR/ch_ping_A_sola.log" load="$RUN_DIR/ch_ping_A_con_B.log" blog="$RUN_DIR/ch_carga_B.log"
  stop_test_processes
  lxc_cmd hs_h4 iperf3 -s -p "$PORT_B" -D
  lxc_cmd hs_h1 ping -c 20 -i 0.2 "$CH_A_IP" | tee "$solo"
  (lxc_cmd hs_h2 iperf3 -u -c "$CH_B_IP" -p "$PORT_B" -b "${CH_B_STABLE_MBIT}M" -t "$RTT_DURATION" -i 5 -l 1400 > "$blog" 2>&1) &
  local pid=$!
  sleep 2
  lxc_cmd hs_h1 ping -c 20 -i 0.2 "$CH_A_IP" | tee "$load"
  wait "$pid" || true
  stop_test_processes
  local loss_solo loss_load
  loss_solo="$(grep -oE '[0-9.]+% packet loss' "$solo" | tail -1 | cut -d% -f1)"
  loss_load="$(grep -oE '[0-9.]+% packet loss' "$load" | tail -1 | cut -d% -f1)"
  if [[ "$loss_solo" == "0" && "$loss_load" == "0" ]]; then
    ok "RTT: 0 % de pérdidas con Slice A sola y con carga en B"
    record_result "rtt_aislamiento" "OK" "loss_solo=0 loss_con_B=0"
  else
    warn "RTT: pérdidas solo=$loss_solo% con_B=$loss_load%"
    record_result "rtt_aislamiento" "AVISO" "loss_solo=$loss_solo loss_con_B=$loss_load"
  fi
}

ch_shared_queue_comparison() {
  local previous_run="$RUN_DIR"
  info "Preparando temporalmente el escenario de cola compartida"
  if ! (cd "$PROJECT_ROOT" && bash scripts_real/09_setup_shared_queue_baseline.sh) 2>&1 | tee "$previous_run/shared_00_setup.log"; then
    error "No se pudo preparar la cola compartida"
    return 1
  fi
  start_iperf_servers || return 1
  local alog="$previous_run/shared_A.log" blog="$previous_run/shared_B.log"
  (lxc_cmd hs_h1 iperf3 -u -c "$FLEX_A_IP" -p "$PORT_A" -b 1.05M -t "$TEST_DURATION" -i 5 -l 1400 > "$alog" 2>&1) & local pa=$!
  (lxc_cmd hs_h2 iperf3 -u -c "$FLEX_B_IP" -p "$PORT_B" -b 20M -t "$TEST_DURATION" -i 5 -l 1400 > "$blog" 2>&1) & local pb=$!
  wait "$pa" || true; wait "$pb" || true
  stop_test_processes
  cat "$alog"; cat "$blog"
  record_result "cola_compartida" "OK" "resultados capturados; restauracion automatica"
  info "Restaurando automáticamente Channelized"
  if ! (cd "$PROJECT_ROOT" && bash scripts_real/01_setup_vrf_subinterfaces.sh && SLICE_A_RATE="${CH_A_LIMIT_MBIT}mbit" SLICE_B_RATE="${CH_B_LIMIT_MBIT}mbit" bash scripts_real/02_apply_hard_slicing_channels_tuned.sh) > "$previous_run/shared_99_restore.log" 2>&1; then
    error "Fallo al restaurar Channelized. Consulte shared_99_restore.log"
    return 1
  fi
  validate_channelized_state || return 1
  ok "Escenario Channelized restaurado"
}

ch_recommended_battery() {
  local failed=0
  ch_show_state || failed=1
  ch_test_isolation || failed=1
  ch_capture_vlans || failed=1
  ch_test_throughput || failed=1
  ch_test_rtt_isolation || failed=1
  ch_show_counters || failed=1
  return "$failed"
}

channelized_menu() {
  while true; do
    cat <<MENU

============================================================
 PRUEBAS: CHANNELIZED SUBINTERFACES (${CH_A_LIMIT_MBIT}/${CH_B_LIMIT_MBIT} Mbit/s)
 Resultados: $RUN_DIR
============================================================
 1) Mostrar configuración completa
 2) Validar aislamiento entre slices
 3) Prueba simultánea de caudal estable
 4) Captura automática de VLAN 10 y VLAN 20
 5) Mostrar contadores HTB
 6) Validar RTT de Slice A con carga en Slice B
 7) Comparar con cola compartida y restaurar Channelized
 8) Ejecutar batería recomendada
 9) Repreparar el escenario Channelized
 0) Volver al menú principal
MENU
    read -r -p "Seleccione una o varias opciones separadas por espacios: " choices
    [[ "$choices" == "0" ]] && return 0
    local choice
    for choice in $choices; do
      case "$choice" in
        1) ch_show_state || true ;;
        2) ch_test_isolation || true ;;
        3) ch_test_throughput || true ;;
        4) ch_capture_vlans || true ;;
        5) ch_show_counters || true ;;
        6) ch_test_rtt_isolation || true ;;
        7) ch_shared_queue_comparison || true ;;
        8) ch_recommended_battery || true ;;
        9) prepare_channelized || true ;;
        *) warn "Opción no válida: $choice" ;;
      esac
    done
    pause
  done
}
