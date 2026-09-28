#!/usr/bin/env bash
#
# Retire this Musashi stake pool. The build step creates and signs the exact
# transaction; only the explicit submit step broadcasts that prepared file.
#
# Usage:
#   ./deregister-pool.sh cert                   # certificate only
#   ./deregister-pool.sh build                  # certificate + signed tx
#   ./deregister-pool.sh submit                 # submit the previously built tx
#   ./deregister-pool.sh status                 # show tip and pool state
#
# Env:
#   RETIRE_EPOCH   effective retirement epoch; default current epoch + 2
#   CARDANO_CLI, KEYS_DIR, CONFIG_DIR, DATA_DIR, SOCKET
#
# Pool retirement does not deregister the owner's stake credential. At the
# retirement boundary the pool deposit is returned to the pool reward account,
# not to the payment address used for this transaction.

set -euo pipefail
umask 077

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${KEYS_DIR:-$HERE/keys}"
CONFIG_DIR="${CONFIG_DIR:-$HERE/config}"
DATA_DIR="${DATA_DIR:-/data/musashi}"
SOCKET="${SOCKET:-$DATA_DIR/node.socket}"
WORK_ROOT="${WORK_ROOT:-$KEYS_DIR/retirement}"
STEP="${1:-cert}"

SHELLEY="$CONFIG_DIR/shelley-genesis.json"
[ -r "$SHELLEY" ] || { echo "error: $SHELLEY not found — run ./pin-config.sh" >&2; exit 1; }

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
[ -n "$CLI" ] || { echo "error: no cardano-cli found (see make-spo-keys.sh for options)" >&2; exit 1; }

json_field() {
  if command -v jq >/dev/null 2>&1; then jq -r --arg k "$2" '.[$k]' "$1"
  else python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; fi
}
json_pparam() {
  if command -v jq >/dev/null 2>&1; then jq -r --arg k "$2" '.protocolParams[$k]' "$1"
  else python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["protocolParams"][sys.argv[2]])' "$1" "$2"; fi
}

MAGIC="$(json_field "$SHELLEY" networkMagic)"
SYSTEM_START="$(json_field "$SHELLEY" systemStart)"
SLOT_LENGTH="$(json_field "$SHELLEY" slotLength)"
EPOCH_LENGTH="$(json_field "$SHELLEY" epochLength)"
EMAX="$(json_pparam "$SHELLEY" eMax)"
POOL_DEPOSIT="$(json_pparam "$SHELLEY" poolDeposit)"
NET=(--testnet-magic "$MAGIC")

for f in cold.vkey cold.skey payment.skey payment.addr stake.addr; do
  [ -r "$KEYS_DIR/$f" ] || { echo "error: $KEYS_DIR/$f missing" >&2; exit 1; }
done

clock_epoch() {
  local start now
  start="$(date -u -d "$SYSTEM_START" +%s 2>/dev/null)" || {
    echo "error: could not parse systemStart '$SYSTEM_START' (GNU date required)" >&2; exit 1; }
  now="$(date -u +%s)"
  echo $(( (now - start) / (SLOT_LENGTH * EPOCH_LENGTH) ))
}

query_tip() {
  local out="$1"
  [ -S "$SOCKET" ] || { echo "error: no node socket at $SOCKET" >&2; exit 1; }
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra query tip "${NET[@]}" > "$out"
}

node_epoch() {
  local tip
  tip="$(mktemp)"
  query_tip "$tip"
  json_field "$tip" epoch
  rm -f "$tip"
}

require_synced_node() {
  local tip progress
  tip="$(mktemp)"
  query_tip "$tip"
  progress="$(json_field "$tip" syncProgress)"
  if ! awk -v p="$progress" 'BEGIN { exit !(p + 0 >= 99.9) }'; then
    echo "error: node is only $progress% synchronized; refusing to build or submit" >&2
    rm -f "$tip"
    exit 1
  fi
  rm -f "$tip"
}

epoch_start() {
  python3 - "$SYSTEM_START" "$SLOT_LENGTH" "$EPOCH_LENGTH" "$1" <<'PY'
from datetime import datetime, timedelta
import sys
start = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
seconds = int(sys.argv[2]) * int(sys.argv[3]) * int(sys.argv[4])
print((start + timedelta(seconds=seconds)).strftime("%Y-%m-%d %H:%M:%S UTC"))
PY
}

pool_id() {
  "$CLI" dijkstra stake-pool id --output-hex \
    --cold-verification-key-file "$KEYS_DIR/cold.vkey"
}

select_target_epoch() {
  local current target tip progress
  if [ -S "$SOCKET" ]; then
    tip="$(mktemp)"
    query_tip "$tip"
    progress="$(json_field "$tip" syncProgress)"
    if awk -v p="$progress" 'BEGIN { exit !(p + 0 >= 99.9) }'; then
      current="$(json_field "$tip" epoch)"
    else
      echo "warning: node is only $progress% synchronized; deriving the certificate epoch from the genesis clock" >&2
      current="$(clock_epoch)"
    fi
    rm -f "$tip"
  else
    current="$(clock_epoch)"
  fi
  target="${RETIRE_EPOCH:-$((current + 2))}"
  case "$target" in ''|*[!0-9]*) echo "error: RETIRE_EPOCH must be a nonnegative integer" >&2; exit 1 ;; esac
  if [ "$target" -le "$current" ]; then
    echo "error: retirement epoch $target must be later than current epoch $current" >&2; exit 1
  fi
  if [ "$target" -gt $((current + EMAX)) ]; then
    echo "error: retirement epoch $target exceeds current epoch + eMax ($current + $EMAX)" >&2; exit 1
  fi
  CURRENT_EPOCH="$current"
  RETIRE_EPOCH_SELECTED="$target"
  WORK="$WORK_ROOT/epoch-$target"
  CERT="$WORK/pool-retirement.cert"
}

show_plan() {
  cat <<EOF
cardano-cli:       $CLI
network:           magic $MAGIC
pool id:           $(pool_id)
current epoch:     $CURRENT_EPOCH
retirement epoch:  $RETIRE_EPOCH_SELECTED
effective at:      $(epoch_start "$RETIRE_EPOCH_SELECTED")
deposit return:    $POOL_DEPOSIT lovelace to $(cat "$KEYS_DIR/stake.addr") rewards
working directory: $WORK
EOF
}

make_cert() {
  mkdir -p "$WORK"
  "$CLI" dijkstra stake-pool deregistration-certificate \
    --cold-verification-key-file "$KEYS_DIR/cold.vkey" \
    --epoch "$RETIRE_EPOCH_SELECTED" \
    --out-file "$CERT"
  echo "certificate:       $CERT"
}

pick_utxo() {
  local u
  u="$(mktemp)"
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra query utxo \
    --address "$(cat "$KEYS_DIR/payment.addr")" "${NET[@]}" --output-json > "$u"
  if command -v jq >/dev/null 2>&1; then
    jq -r 'to_entries
           | map({k:.key, v:(.value.value.lovelace // .value.value // 0)})
           | sort_by(.v) | reverse | .[0] | "\(.k) \(.v)"' "$u"
  else
    python3 - "$u" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
def lov(e):
    v=e.get("value")
    if isinstance(v,dict): v=v.get("lovelace", v)
    return v if isinstance(v,int) else 0
best=max(d.items(), key=lambda kv: lov(kv[1]), default=None)
print(f"{best[0]} {lov(best[1])}" if best else "")
PY
  fi
  rm -f "$u"
}

build_tx() {
  local selected txin amount txid
  require_synced_node
  selected="$(pick_utxo)"
  txin="${selected%% *}"
  amount="${selected##* }"
  if [ -z "$selected" ] || [ "$txin" = "null" ]; then
    echo "error: no unspent transaction output at $(cat "$KEYS_DIR/payment.addr")" >&2
    exit 1
  fi
  echo "input:             $txin ($amount lovelace)"
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra transaction build \
    --tx-in "$txin" \
    --change-address "$(cat "$KEYS_DIR/payment.addr")" \
    --certificate-file "$CERT" \
    --witness-override 2 \
    "${NET[@]}" --out-file "$WORK/tx.raw"
  "$CLI" dijkstra transaction sign --tx-body-file "$WORK/tx.raw" \
    --signing-key-file "$KEYS_DIR/payment.skey" \
    --signing-key-file "$KEYS_DIR/cold.skey" \
    "${NET[@]}" --out-file "$WORK/tx.signed"
  txid="$("$CLI" dijkstra transaction txid --tx-file "$WORK/tx.signed" --output-text)"
  printf '%s\n' "$RETIRE_EPOCH_SELECTED" > "$WORK_ROOT/prepared-epoch"
  {
    printf 'pool_id=%s\n' "$(pool_id)"
    printf 'retirement_epoch=%s\n' "$RETIRE_EPOCH_SELECTED"
    printf 'effective_at=%s\n' "$(epoch_start "$RETIRE_EPOCH_SELECTED")"
    printf 'transaction_id=%s\n' "$txid"
    printf 'transaction_input=%s\n' "$txin"
    printf 'transaction_input_lovelace=%s\n' "$amount"
    printf 'transaction_input_source=live node query\n'
    printf 'built_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$WORK/manifest.txt"
  echo "signed transaction: $WORK/tx.signed"
  echo "transaction id:     $txid"
  cat <<EOF

Nothing has been submitted. Review $WORK/manifest.txt, then broadcast this
exact prepared transaction with:

  $0 submit
EOF
}

submit_tx() {
  local prepared current txin expected actual utxo
  [ -r "$WORK_ROOT/prepared-epoch" ] || { echo "error: no prepared transaction — run '$0 build' first" >&2; exit 1; }
  prepared="$(cat "$WORK_ROOT/prepared-epoch")"
  WORK="$WORK_ROOT/epoch-$prepared"
  [ -r "$WORK/tx.signed" ] || { echo "error: $WORK/tx.signed is missing" >&2; exit 1; }
  [ -r "$WORK/manifest.txt" ] || { echo "error: $WORK/manifest.txt is missing" >&2; exit 1; }
  require_synced_node
  current="$(node_epoch)"
  if [ "$prepared" -le "$current" ]; then
    echo "error: prepared retirement epoch $prepared is no longer in the future (current $current); rebuild" >&2
    exit 1
  fi
  txin="$(awk -F= '$1 == "transaction_input" {print $2}' "$WORK/manifest.txt")"
  expected="$(awk -F= '$1 == "transaction_input_lovelace" {print $2}' "$WORK/manifest.txt")"
  [ -n "$txin" ] || { echo "error: transaction_input is missing from $WORK/manifest.txt" >&2; exit 1; }
  utxo="$(mktemp)"
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra query utxo \
    --tx-in "$txin" "${NET[@]}" --output-json > "$utxo"
  if command -v jq >/dev/null 2>&1; then
    actual="$(jq -r --arg i "$txin" '.[$i].value.lovelace // empty' "$utxo")"
  else
    actual="$(python3 - "$utxo" "$txin" <<'PY'
import json,sys
entry=json.load(open(sys.argv[1])).get(sys.argv[2], {})
print(entry.get("value", {}).get("lovelace", ""))
PY
)"
  fi
  rm -f "$utxo"
  [ -n "$actual" ] || { echo "error: prepared input $txin is no longer unspent; rebuild" >&2; exit 1; }
  if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
    echo "error: prepared input amount is $actual lovelace, not the recorded $expected; rebuild" >&2
    exit 1
  fi
  echo "submitting retirement transaction $("$CLI" dijkstra transaction txid --tx-file "$WORK/tx.signed" --output-text)"
  echo "retirement takes effect at epoch $prepared ($(epoch_start "$prepared"))"
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra transaction submit \
    --tx-file "$WORK/tx.signed" "${NET[@]}"
  echo "submitted; query pool-state after the transaction is included, and again at the retirement boundary"
}

status() {
  require_synced_node
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra query tip "${NET[@]}"
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra query pool-state \
    --stake-pool-id "$(pool_id)" "${NET[@]}"
}

case "$STEP" in
  cert)
    select_target_epoch
    show_plan
    make_cert
    echo "certificate created; nothing has been submitted"
    ;;
  build)
    select_target_epoch
    show_plan
    make_cert
    build_tx
    ;;
  submit) submit_tx ;;
  status) status ;;
  *) echo "usage: $0 [cert|build|submit|status]" >&2; exit 2 ;;
esac
