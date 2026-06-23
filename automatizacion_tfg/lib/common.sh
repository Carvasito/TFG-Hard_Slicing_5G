#!/usr/bin/env bash

# Funciones comunes del controlador. Este archivo se carga mediante source.

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

info()  { printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$*"; }
ok()    { printf "${COLOR_GREEN}[OK]${COLOR_RESET} %s\n" "$*"; }
warn()  { printf "${COLOR_YELLOW}[AVISO]${COLOR_RESET} %s\n" "$*"; }
error() { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$*" >&2; }

pause() {
  echo
  read -r -p "Pulse Intro para continuar..." _
}

require_sudo() {
  if ! sudo -v; then
    error "No se pudieron obtener permisos sudo."
    return 1
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

check_host_dependencies() {
  local missing=0 cmd
  for cmd in bash sudo lxc-attach lxc-info awk grep sed date timeout tee; do
    if ! command_exists "$cmd"; then
      error "Falta la dependencia del host: $cmd"
      missing=1
    fi
  done
  return "$missing"
}

container_state() {
  sudo lxc-info -n "$1" -sH 2>/dev/null || true
}

container_running() {
  [[ "$(container_state "$1")" == "RUNNING" ]]
}

all_containers_running() {
  local c
  for c in "${CONTAINERS[@]}"; do
    container_running "$c" || return 1
  done
}

wait_for_containers() {
  local deadline=$((SECONDS + CONTAINER_START_TIMEOUT)) c pending
  while (( SECONDS < deadline )); do
    pending=0
    for c in "${CONTAINERS[@]}"; do
      container_running "$c" || pending=1
    done
    (( pending == 0 )) && return 0
    sleep 2
  done
  return 1
}

start_vnx_scenario() {
  local log="$AUTO_DIR/resultados/arranque_vnx_$(date +%Y%m%d_%H%M%S).log"
  mkdir -p "$AUTO_DIR/resultados"

  if [[ ! -f "$SCENARIO_XML" ]]; then
    error "No se encuentra el escenario VNX: $SCENARIO_XML"
    return 1
  fi
  if ! command_exists vnx; then
    error "Los contenedores no están arrancados y no se encuentra el comando vnx."
    error "Instale o cargue VNX antes de ejecutar el controlador."
    return 1
  fi

  info "La maqueta no está arrancada. Iniciando automáticamente el escenario VNX..."
  if (cd "$PROJECT_ROOT" && sudo vnx -f "$SCENARIO_XML" --create) 2>&1 | tee "$log"; then
    :
  else
    warn "El arranque directo no se completó. Limpiando un posible estado parcial y recreando la maqueta..."
    (cd "$PROJECT_ROOT" && sudo vnx -f "$SCENARIO_XML" --destroy) >>"$log" 2>&1 || true
    if ! (cd "$PROJECT_ROOT" && sudo vnx -f "$SCENARIO_XML" --create) 2>&1 | tee -a "$log"; then
      error "No se pudo crear el escenario VNX. Consulte: $log"
      return 1
    fi
  fi

  info "Esperando a que arranquen los contenedores..."
  if wait_for_containers; then
    ok "Escenario VNX arrancado correctamente"
    return 0
  fi

  error "Los contenedores no alcanzaron el estado RUNNING en ${CONTAINER_START_TIMEOUT}s."
  error "Consulte el log de arranque: $log"
  return 1
}

ensure_containers_running() {
  all_containers_running && return 0
  start_vnx_scenario
}

check_containers() {
  local failed=0 c state
  for c in "${CONTAINERS[@]}"; do
    state="$(container_state "$c")"
    if [[ "$state" == "RUNNING" ]]; then
      ok "$c está RUNNING"
    else
      error "$c no está arrancado (estado: ${state:-NO CREADO})"
      failed=1
    fi
  done
  return "$failed"
}

check_container_commands() {
  local failed=0 c cmd
  for c in hs_h1 hs_h2 hs_h3 hs_h4; do
    for cmd in ip ping iperf3 pkill ss; do
      if ! sudo lxc-attach -n "$c" -- sh -c "command -v $cmd >/dev/null 2>&1"; then
        error "Falta $cmd dentro de $c"
        failed=1
      fi
    done
  done
  for c in hs_r1 hs_r2; do
    for cmd in ip tc ping tcpdump; do
      if ! sudo lxc-attach -n "$c" -- sh -c "command -v $cmd >/dev/null 2>&1"; then
        error "Falta $cmd dentro de $c"
        failed=1
      fi
    done
  done
  return "$failed"
}

check_required_scripts() {
  local failed=0 f
  local required=(
    "$PROJECT_ROOT/scripts_real/01_setup_vrf_subinterfaces.sh"
    "$PROJECT_ROOT/scripts_real/02_apply_hard_slicing_channels_tuned.sh"
    "$PROJECT_ROOT/scripts_real/03_show_real_slicing.sh"
    "$PROJECT_ROOT/scripts_real/04_test_vrf_isolation.sh"
    "$PROJECT_ROOT/scripts_real/09_setup_shared_queue_baseline.sh"
    "$PROJECT_ROOT/scripts_flexible/01_setup_flexible_channels_base.sh"
    "$PROJECT_ROOT/scripts_flexible/02_flexible_channel_controller.sh"
  )
  for f in "${required[@]}"; do
    if [[ ! -f "$f" ]]; then
      error "No existe el script requerido: $f"
      failed=1
    fi
  done
  return "$failed"
}

preflight() {
  info "Comprobando dependencias, scripts y contenedores..."
  require_sudo || return 1
  check_host_dependencies || return 1
  check_required_scripts || return 1
  ensure_containers_running || return 1
  check_containers || return 1
  check_container_commands || return 1
  ok "Comprobaciones previas superadas"
}

stop_test_processes() {
  local c
  info "Deteniendo procesos de prueba anteriores..."
  for c in hs_h1 hs_h2 hs_h3 hs_h4; do
    sudo lxc-attach -n "$c" -- pkill -x iperf3 2>/dev/null || true
    sudo lxc-attach -n "$c" -- pkill -x iperf 2>/dev/null || true
    sudo lxc-attach -n "$c" -- pkill -x ping 2>/dev/null || true
  done
  for c in hs_r1 hs_r2; do
    sudo lxc-attach -n "$c" -- pkill -x tcpdump 2>/dev/null || true
  done
}

new_run_dir() {
  local scenario="$1" profile="$2" ts
  ts="$(date +%Y%m%d_%H%M%S)"
  RUN_DIR="$AUTO_DIR/resultados/${ts}_${scenario}_${profile}"
  mkdir -p "$RUN_DIR"
  ln -sfn "$RUN_DIR" "$AUTO_DIR/resultados/ultima_ejecucion"
  RESULT_FILE="$RUN_DIR/resultados.tsv"
  printf "fecha\tescenario\tprueba\testado\tdetalle\n" > "$RESULT_FILE"
  cat > "$RUN_DIR/metadata.txt" <<META
fecha=$(date '+%Y-%m-%d %H:%M:%S')
escenario=$scenario
perfil=$profile
usuario=${SUDO_USER:-$USER}
host=$(hostname)
proyecto=$PROJECT_ROOT
META
}

record_result() {
  local test="$1" status="$2" detail="${3:-}"
  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/ }"
  printf "%s\t%s\t%s\t%s\t%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$CURRENT_SCENARIO" "$test" "$status" "$detail" >> "$RESULT_FILE"
}

run_logged() {
  local name="$1"; shift
  local logfile="$RUN_DIR/${name}.log"
  info "Ejecutando: $name"
  if (cd "$PROJECT_ROOT" && "$@") 2>&1 | tee "$logfile"; then
    ok "$name completado"
    record_result "$name" "OK" "$logfile"
    return 0
  else
    local rc=${PIPESTATUS[0]}
    error "$name falló (código $rc). Consulte $logfile"
    record_result "$name" "ERROR" "codigo=$rc log=$logfile"
    return "$rc"
  fi
}

lxc_cmd() {
  local c="$1"; shift
  sudo lxc-attach -n "$c" -- "$@"
}

start_iperf_servers() {
  stop_test_processes
  lxc_cmd hs_h3 iperf3 -s -p "$PORT_A" -D
  lxc_cmd hs_h4 iperf3 -s -p "$PORT_B" -D
  sleep 2
  if ! lxc_cmd hs_h3 sh -c "ss -ltn | grep -q ':${PORT_A} '"; then
    error "No se ha iniciado el servidor iperf3 A en hs_h3:${PORT_A}"
    return 1
  fi
  if ! lxc_cmd hs_h4 sh -c "ss -ltn | grep -q ':${PORT_B} '"; then
    error "No se ha iniciado el servidor iperf3 B en hs_h4:${PORT_B}"
    return 1
  fi
}

extract_receiver_mbps() {
  local file="$1"
  awk '/receiver$/ {
    for (i=2; i<=NF; i++) {
      if ($i=="Mbits/sec") last=$(i-1)
      else if ($i=="Kbits/sec") last=$(i-1)/1000
      else if ($i=="Gbits/sec") last=$(i-1)*1000
    }
  } END {if(last!="") printf "%.3f", last}' "$file"
}

extract_receiver_loss() {
  local file="$1"
  awk '/receiver$/ {for(i=1;i<=NF;i++) if($i ~ /%\)/){gsub(/[()%]/,"",$i); last=$i}} END {if(last!="") print last}' "$file"
}

float_ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }
float_le() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<=b)}'; }
float_mul() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f",a*b}'; }

validate_iperf_result() {
  local label="$1" file="$2" offered="$3"
  local mbps loss minimum
  mbps="$(extract_receiver_mbps "$file")"
  loss="$(extract_receiver_loss "$file")"
  minimum="$(float_mul "$offered" "$MIN_THROUGHPUT_RATIO")"
  if [[ -z "$mbps" ]]; then
    error "$label: no se pudo extraer el caudal receiver"
    record_result "$label" "ERROR" "sin resultado receiver"
    return 1
  fi
  [[ -n "$loss" ]] || loss="N/D"
  if float_ge "$mbps" "$minimum" && { [[ "$loss" == "N/D" ]] || float_le "$loss" "$MAX_STABLE_LOSS_PERCENT"; }; then
    ok "$label: ${mbps} Mbit/s, pérdidas ${loss}%"
    record_result "$label" "OK" "mbps=$mbps loss=$loss offered=$offered"
    return 0
  fi
  warn "$label: ${mbps} Mbit/s, pérdidas ${loss}% (fuera del criterio estable)"
  record_result "$label" "AVISO" "mbps=$mbps loss=$loss offered=$offered"
  return 1
}

run_two_udp_clients() {
  local ip_a="$1" rate_a="$2" ip_b="$3" rate_b="$4" prefix="$5"
  local log_a="$RUN_DIR/${prefix}_A.log" log_b="$RUN_DIR/${prefix}_B.log"
  start_iperf_servers || return 1
  info "Lanzando tráfico simultáneo A=${rate_a}M y B=${rate_b}M durante ${TEST_DURATION}s"
  (lxc_cmd hs_h1 iperf3 -u -c "$ip_a" -p "$PORT_A" -b "${rate_a}M" -t "$TEST_DURATION" -i 5 -l 1400 --udp-counters-64bit > "$log_a" 2>&1) &
  local pid_a=$!
  (lxc_cmd hs_h2 iperf3 -u -c "$ip_b" -p "$PORT_B" -b "${rate_b}M" -t "$TEST_DURATION" -i 5 -l 1400 --udp-counters-64bit > "$log_b" 2>&1) &
  local pid_b=$!
  local rc=0
  wait "$pid_a" || rc=1
  wait "$pid_b" || rc=1
  cat "$log_a"
  cat "$log_b"
  stop_test_processes
  return "$rc"
}

show_last_results() {
  if [[ -L "$AUTO_DIR/resultados/ultima_ejecucion" ]]; then
    echo "Última ejecución: $(readlink -f "$AUTO_DIR/resultados/ultima_ejecucion")"
    find -L "$AUTO_DIR/resultados/ultima_ejecucion" -maxdepth 1 -type f -printf '  %f\n' | sort
  else
    warn "Todavía no hay ejecuciones registradas"
  fi
}
