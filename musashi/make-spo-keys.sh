#!/usr/bin/env bash
#
# Generate the credentials for a musashi block producer, and issue the
# operational certificate. Entirely offline: the op-cert's KES period comes from
# the node when one is reachable and from the wall clock plus the genesis
# systemStart otherwise, so this works before the producer can start — which it
# must, since the producer will not start without the certificate.
#
# Usage:
#   ./make-spo-keys.sh            # keys, addresses, and op-cert (if the node is reachable)
#   ./make-spo-keys.sh keys       # keys and addresses only
#   ./make-spo-keys.sh opcert     # (re)issue the op-cert from existing keys — also the KES-rotation step
#   ./make-spo-keys.sh show       # print the summary again, generating nothing
#
# Env:
#   CARDANO_CLI   path to cardano-cli (else ./build, else PATH, else the pod)
#   KEYS_DIR      where credentials land (default ./keys)
#   CONFIG_DIR    pinned network config (default ./config) — read for magic and KES period length
#   SOCKET        node socket (default ./data/node.socket)
#
# Existing key files are never overwritten — not for secrecy (these are
# throwaway testnet credentials) but because a new cold key is a new pool, which
# costs another registration and another faucet delegation. Move KEYS_DIR aside
# yourself if that is what you want.

set -euo pipefail
umask 077

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${KEYS_DIR:-$HERE/keys}"
CONFIG_DIR="${CONFIG_DIR:-$HERE/config}"
SOCKET="${SOCKET:-$HERE/data/node.socket}"
STEP="${1:-all}"

# --- locate cardano-cli -------------------------------------------------------
find_cli() {
  if [ -n "${CARDANO_CLI:-}" ]; then echo "$CARDANO_CLI"; return; fi
  local c
  for c in "$HERE/build/cardano-cli" "$HERE/build/bin/cardano-cli"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  if [ -d "$HERE/build" ]; then
    c="$(find "$HERE/build" -type f -name cardano-cli -perm -u+x 2>/dev/null | head -1)"
    [ -n "$c" ] && { echo "$c"; return; }
  fi
  command -v cardano-cli 2>/dev/null && return
  echo ""
}
CLI="$(find_cli)"
if [ -z "$CLI" ]; then
  cat >&2 <<'EOF'
error: no cardano-cli found. Either
  - build it into ./build (the script searches ./build recursively),
  - set CARDANO_CLI=/path/to/cardano-cli, or
  - enter the repository's dev shell, which provides it: nix develop
  - or copy it out of the running pod (container name follows the pod):
      podman cp musashi-bp-node:/usr/local/bin/cardano-cli ./build/cardano-cli
EOF
  exit 1
fi

# --- network parameters, read rather than assumed -----------------------------
SHELLEY="$CONFIG_DIR/shelley-genesis.json"
[ -r "$SHELLEY" ] || { echo "error: $SHELLEY not found — run ./pin-config.sh first" >&2; exit 1; }
# json_field <file> <top-level key> — jq when available, python3 otherwise.
json_field() {
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$2" '.[$k]' "$1"
  else
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
  fi
}
MAGIC="$(json_field "$SHELLEY" networkMagic)"
KES_PERIOD_SLOTS="$(json_field "$SHELLEY" slotsPerKESPeriod)"
MAX_KES="$(json_field "$SHELLEY" maxKESEvolutions)"
SYSTEM_START="$(json_field "$SHELLEY" systemStart)"
SLOT_LENGTH="$(json_field "$SHELLEY" slotLength)"
NET=(--testnet-magic "$MAGIC")

echo "cardano-cli:  $CLI"
echo "              $("$CLI" --version | head -1)"
echo "network:      magic $MAGIC, slotsPerKESPeriod $KES_PERIOD_SLOTS, maxKESEvolutions $MAX_KES"
echo "keys:         $KEYS_DIR"

# --- helpers ------------------------------------------------------------------
refuse_existing() {
  local f found=0
  for f in "$@"; do
    [ -e "$KEYS_DIR/$f" ] && { echo "  present: $f" >&2; found=1; }
  done
  if [ "$found" = 1 ]; then
    cat >&2 <<EOF
error: refusing to overwrite existing credentials in $KEYS_DIR.
A regenerated cold key is a different pool. Move the directory aside if you
really mean to start over:  mv "$KEYS_DIR" "$KEYS_DIR.$(date -u +%Y%m%dT%H%M%SZ)"
EOF
    exit 1
  fi
}

have_node() { [ -S "$SOCKET" ]; }

pool_id() { "$CLI" dijkstra stake-pool id --output-bech32 \
  --cold-verification-key-file "$KEYS_DIR/cold.vkey"; }

summary() {
  echo
  echo "=== credentials in $KEYS_DIR ==="
  find "$KEYS_DIR" -maxdepth 1 -type f -printf '  %M %10s %p\n' 2>/dev/null \
    || (cd "$KEYS_DIR" && for f in *; do printf '  %s\n' "$f"; done)
  echo
  echo "pool id (bech32):  $(pool_id)"
  echo "pool id (hex):     $("$CLI" dijkstra stake-pool id --output-hex \
                              --cold-verification-key-file "$KEYS_DIR/cold.vkey")"
  echo "payment address:   $(cat "$KEYS_DIR/payment.addr")"
  echo "stake address:     $(cat "$KEYS_DIR/stake.addr")"
  if [ -r "$KEYS_DIR/opcert.cert" ]; then
    echo "op-cert:           issued at KES period $(cat "$KEYS_DIR/opcert.kesperiod" 2>/dev/null || echo '?')"
  else
    echo "op-cert:           NOT ISSUED — run './make-spo-keys.sh opcert' with the node running"
  fi
  cat <<EOF

Next:
  1. Fund the payment address:  https://faucet.leios.play.dev.cardano.org/basic-faucet
  2. Register:                  ./register-pool.sh        (see block-producer.md)
  3. Delegate stake to the pool id with the faucet's *delegate* widget.
EOF
}

# --- step: keys ---------------------------------------------------------------
gen_keys() {
  refuse_existing cold.vkey cold.skey cold.counter vrf.vkey vrf.skey \
                  kes.vkey kes.skey bls.vkey bls.skey \
                  payment.vkey payment.skey stake.vkey stake.skey
  mkdir -p "$KEYS_DIR"
  cd "$KEYS_DIR"

  echo "generating credentials…"
  # Cold (operator) key and its op-cert issue counter — the pool's identity.
  "$CLI" dijkstra node key-gen \
    --cold-verification-key-file cold.vkey \
    --cold-signing-key-file cold.skey \
    --operational-certificate-issue-counter-file cold.counter
  # VRF — leader election.
  "$CLI" dijkstra node key-gen-VRF --verification-key-file vrf.vkey --signing-key-file vrf.skey
  # KES — block signing, rotated every maxKESEvolutions periods.
  "$CLI" dijkstra node key-gen-KES --verification-key-file kes.vkey --signing-key-file kes.skey
  # BLS — Leios vote signing. Dijkstra-era only; registered via the pool cert.
  "$CLI" dijkstra node key-gen-BLS --verification-key-file bls.vkey --signing-key-file bls.skey
  # Payment and stake keys for the registration transaction and the pledge.
  "$CLI" address key-gen --verification-key-file payment.vkey --signing-key-file payment.skey
  "$CLI" dijkstra stake-address key-gen --verification-key-file stake.vkey --signing-key-file stake.skey

  "$CLI" address build --payment-verification-key-file payment.vkey \
    --stake-verification-key-file stake.vkey "${NET[@]}" --out-file payment.addr
  "$CLI" dijkstra stake-address build --stake-verification-key-file stake.vkey \
    "${NET[@]}" --out-file stake.addr

  # Functional, not hygienic: the node refuses to start if the VRF signing key
  # grants group or other access. The rest ride along with the same mode.
  chmod 600 ./*.skey
  chmod 644 ./*.vkey ./*.addr
  echo "done."
}

# --- step: op-cert ------------------------------------------------------------
# The slot the chain is in, from the node when it is running and from the clock
# otherwise. The clock is authoritative-equivalent here: musashi has one era at
# one second per slot from genesis (byron startTime == shelley systemStart), so
# slot = floor((now - systemStart) / slotLength). Verified against a live tip:
# 2026-09-21T16:28:28Z gives 1268908, which is what the network reported.
current_slot() {
  if have_node; then
    local tip slot
    tip="$(mktemp)"
    CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra query tip "${NET[@]}" > "$tip"
    slot="$(json_field "$tip" slot)"
    rm -f "$tip"
    case "$slot" in ''|*[!0-9]*) ;; *) echo "$slot"; return ;; esac
    echo "warning: could not read the tip slot from the node; falling back to the clock" >&2
  fi
  local start now
  start="$(date -u -d "$SYSTEM_START" +%s 2>/dev/null)" || {
    echo "error: could not parse systemStart '$SYSTEM_START' (GNU date required)" >&2; exit 1; }
  now="$(date -u +%s)"
  echo $(( (now - start) / SLOT_LENGTH ))
}

issue_opcert() {
  [ -r "$KEYS_DIR/kes.vkey" ] || { echo "error: no kes.vkey in $KEYS_DIR — run the 'keys' step first" >&2; exit 1; }
  local slot period source
  if have_node; then source="node"; else source="clock (no socket at $SOCKET)"; fi
  slot="$(current_slot)"
  period=$(( slot / KES_PERIOD_SLOTS ))
  echo "slot $slot from $source  =>  KES period $period (valid for $MAX_KES periods)"
  # Reissuing is legitimate — it is the KES-rotation step — so this one file is
  # allowed to be replaced, and the counter file advances with it.
  "$CLI" dijkstra node issue-op-cert \
    --kes-verification-key-file "$KEYS_DIR/kes.vkey" \
    --cold-signing-key-file "$KEYS_DIR/cold.skey" \
    --operational-certificate-issue-counter-file "$KEYS_DIR/cold.counter" \
    --kes-period "$period" \
    --out-file "$KEYS_DIR/opcert.cert"
  echo "$period" > "$KEYS_DIR/opcert.kesperiod"
  chmod 600 "$KEYS_DIR/opcert.cert"
  echo "wrote $KEYS_DIR/opcert.cert"
}

case "$STEP" in
  keys)   gen_keys; summary ;;
  opcert) issue_opcert; summary ;;
  show)   summary ;;
  all)   gen_keys; issue_opcert; summary ;;
  *) echo "usage: $0 [all|keys|opcert|show]" >&2; exit 2 ;;
esac
