#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_ROOT/resultados_flexible"
STATE_FILE="$OUT_DIR/current_flexible_channels.conf"
mkdir -p "$OUT_DIR"

usage() {
  cat <<'USAGE'
Uso:
  ./scripts_flexible/02_flexible_channel_controller.sh
  ./scripts_flexible/02_flexible_channel_controller.sh --total 10 --a 6 --b 3

Parámetros:
  --total N   Capacidad total controlada en Mbit/s.
  --a N       Capacidad asignada al Canal A en Mbit/s.
  --b N       Capacidad asignada al Canal B en Mbit/s.
  -h, --help  Muestra esta ayuda.

Se admiten valores decimales con punto o coma. Debe cumplirse A + B <= total.
USAGE
}

normalize_number() {
  local value="${1:-}"
  value="${value,,}"
  value="${value//mbit\/s/}"
  value="${value//mbps/}"
  value="${value//mbit/}"
  value="${value// /}"
  value="${value//,/.}"
  printf '%s' "$value"
}

is_number() {
  [[ "$1" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]
}

is_positive() {
  awk -v v="$1" 'BEGIN { exit !(v > 0) }'
}

leq() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a <= b) }'
}

sum() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", a + b }'
}

sub() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", a - b }'
}

rate() {
  printf '%smbit' "$1"
}

lxc() {
  local node="$1"
  shift
  sudo lxc-attach -n "$node" -- "$@"
}

apply_htb() {
  local node="$1" dev="$2" dst_a="$3" dst_b="$4"
  local total_rate="$5" rate_a="$6" rate_b="$7" default_rate="$8"

  lxc "$node" tc qdisc del dev "$dev" root 2>/dev/null || true
  lxc "$node" tc qdisc add dev "$dev" root handle 1: htb default 30
  lxc "$node" tc class add dev "$dev" parent 1: classid 1:1 htb \
    rate "$total_rate" ceil "$total_rate" burst 128k cburst 128k
  lxc "$node" tc class add dev "$dev" parent 1:1 classid 1:10 htb \
    rate "$rate_a" ceil "$rate_a" burst 128k cburst 128k
  lxc "$node" tc class add dev "$dev" parent 1:1 classid 1:20 htb \
    rate "$rate_b" ceil "$rate_b" burst 128k cburst 128k
  lxc "$node" tc class add dev "$dev" parent 1:1 classid 1:30 htb \
    rate "$default_rate" ceil "$default_rate" burst 32k cburst 32k

  lxc "$node" tc qdisc add dev "$dev" parent 1:10 handle 10: pfifo limit 10000
  lxc "$node" tc qdisc add dev "$dev" parent 1:20 handle 20: pfifo limit 10000
  lxc "$node" tc qdisc add dev "$dev" parent 1:30 handle 30: pfifo limit 1000

  lxc "$node" tc filter add dev "$dev" protocol ip parent 1: prio 1 u32 \
    match ip dst "$dst_a" flowid 1:10
  lxc "$node" tc filter add dev "$dev" protocol ip parent 1: prio 1 u32 \
    match ip dst "$dst_b" flowid 1:20
}

TOTAL_INPUT=""
A_INPUT=""
B_INPUT=""

while (($#)); do
  case "$1" in
    --total)
      [[ $# -ge 2 ]] || { echo "ERROR: falta el valor de --total" >&2; exit 2; }
      TOTAL_INPUT="$2"; shift 2 ;;
    --a)
      [[ $# -ge 2 ]] || { echo "ERROR: falta el valor de --a" >&2; exit 2; }
      A_INPUT="$2"; shift 2 ;;
    --b)
      [[ $# -ge 2 ]] || { echo "ERROR: falta el valor de --b" >&2; exit 2; }
      B_INPUT="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: parámetro no reconocido: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

echo "===================================================="
echo " CONTROLADOR DE FLEXIBLE CHANNELS"
echo "===================================================="
echo "Sin VRF, sin VLAN y sin subinterfaces"
echo "Particionado de capacidad sobre la interfaz base"
echo

if [[ -z "$TOTAL_INPUT" ]]; then
  read -r -p "Capacidad total del enlace [Mbit/s, defecto 10]: " TOTAL_INPUT
  TOTAL_INPUT="${TOTAL_INPUT:-10}"
fi
if [[ -z "$A_INPUT" ]]; then
  read -r -p "Capacidad para el Canal A [Mbit/s, defecto 6]: " A_INPUT
  A_INPUT="${A_INPUT:-6}"
fi
if [[ -z "$B_INPUT" ]]; then
  read -r -p "Capacidad para el Canal B [Mbit/s, defecto 3]: " B_INPUT
  B_INPUT="${B_INPUT:-3}"
fi

TOTAL="$(normalize_number "$TOTAL_INPUT")"
A="$(normalize_number "$A_INPUT")"
B="$(normalize_number "$B_INPUT")"

for pair in "total:$TOTAL" "Canal A:$A" "Canal B:$B"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if ! is_number "$value" || ! is_positive "$value"; then
    echo "ERROR: $name debe ser un número mayor que 0." >&2
    exit 1
  fi
done

ASSIGNED="$(sum "$A" "$B")"
if ! leq "$ASSIGNED" "$TOTAL"; then
  echo "ERROR: la suma de los canales supera la capacidad total." >&2
  echo "Capacidad total: $TOTAL Mbit/s" >&2
  echo "Capacidad asignada: $ASSIGNED Mbit/s" >&2
  exit 1
fi

UNUSED="$(sub "$TOTAL" "$ASSIGNED")"
TOTAL_RATE="$(rate "$TOTAL")"
A_RATE="$(rate "$A")"
B_RATE="$(rate "$B")"

if awk -v u="$UNUSED" 'BEGIN { exit !(u > 0) }'; then
  DEFAULT_RATE="$(rate "$UNUSED")"
else
  DEFAULT_RATE="1kbit"
fi

echo
echo "===== Perfil validado ====="
echo "Capacidad total: $TOTAL Mbit/s"
echo "Canal A: $A Mbit/s"
echo "Canal B: $B Mbit/s"
echo "Capacidad no asignada: $UNUSED Mbit/s"
echo
echo "===== Aplicando perfil ====="

apply_htb hs_r1 eth3 10.0.3.2/32 10.0.4.2/32 \
  "$TOTAL_RATE" "$A_RATE" "$B_RATE" "$DEFAULT_RATE"
apply_htb hs_r2 eth1 10.0.1.2/32 10.0.2.2/32 \
  "$TOTAL_RATE" "$A_RATE" "$B_RATE" "$DEFAULT_RATE"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
cat > "$STATE_FILE" <<EOF_STATE
timestamp=$TIMESTAMP
mode=flexible_channels_without_vrf_without_vlan
total_mbit=$TOTAL
channel_a_mbit=$A
channel_b_mbit=$B
assigned_mbit=$ASSIGNED
unused_mbit=$UNUSED
forward_interface=hs_r1:eth3
reverse_interface=hs_r2:eth1
channel_a_filter_forward=dst_10.0.3.2
channel_b_filter_forward=dst_10.0.4.2
channel_a_filter_reverse=dst_10.0.1.2
channel_b_filter_reverse=dst_10.0.2.2
EOF_STATE

sudo chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$STATE_FILE" 2>/dev/null || true

echo
echo "===== Estado guardado ====="
cat "$STATE_FILE"
echo
echo "===== HTB hs_r1 eth3 ====="
lxc hs_r1 tc -s class show dev eth3
echo
echo "===== HTB hs_r2 eth1 ====="
lxc hs_r2 tc -s class show dev eth1
echo
echo "===================================================="
echo " FLEXIBLE CHANNELS APLICADOS CORRECTAMENTE"
echo "===================================================="
