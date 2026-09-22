#!/usr/bin/env bash
#
# Register the pool created by ./make-spo-keys.sh: builds the three
# certificates, assembles and signs one transaction, and submits it only when
# asked. Registers the BLS (Leios) voting key as a side effect, because that key
# rides on the pool certificate.
#
# Usage:
#   RELAY_HOST=my.host.example ./register-pool.sh certs     # certificates only (offline)
#   RELAY_HOST=my.host.example ./register-pool.sh build     # + build and sign the tx (needs the node)
#   RELAY_HOST=my.host.example ./register-pool.sh submit    # + submit it
#
# Env:
#   RELAY_HOST / RELAY_IPV4   how peers reach this node — one is required
#   RELAY_PORT                default 3010
#   PLEDGE                    lovelace, default 0
#   POOL_COST                 lovelace, default = genesis minPoolCost
#   MARGIN                    default 0
#   CARDANO_CLI, KEYS_DIR, CONFIG_DIR, SOCKET   as in make-spo-keys.sh
#
# What it costs, from the pinned genesis: a 500 ada pool deposit and a 2 ada
# stake-key deposit, plus fees and whatever pledge you set. Governance can move
# those; check with `cardano-cli dijkstra query protocol-parameters`.

set -euo pipefail
umask 077

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${KEYS_DIR:-$HERE/keys}"
CONFIG_DIR="${CONFIG_DIR:-$HERE/config}"
SOCKET="${SOCKET:-$HERE/data/node.socket}"
WORK="${WORK:-$KEYS_DIR/registration}"
STEP="${1:-certs}"

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
NET=(--testnet-magic "$MAGIC")
MIN_POOL_COST="$(json_pparam "$SHELLEY" minPoolCost)"
POOL_DEPOSIT="$(json_pparam "$SHELLEY" poolDeposit)"
KEY_DEPOSIT="$(json_pparam "$SHELLEY" keyDeposit)"

PLEDGE="${PLEDGE:-0}"
POOL_COST="${POOL_COST:-$MIN_POOL_COST}"
MARGIN="${MARGIN:-0}"
RELAY_PORT="${RELAY_PORT:-3010}"

if [ "$POOL_COST" -lt "$MIN_POOL_COST" ]; then
  echo "error: POOL_COST $POOL_COST is below the network's minPoolCost $MIN_POOL_COST" >&2; exit 1
fi

# A pool with no advertised relay is unreachable, and on a single-node setup
# this node *is* the relay — so make the operator state it rather than default it.
RELAY_ARGS=()
if [ -n "${RELAY_HOST:-}" ]; then
  RELAY_ARGS=(--single-host-pool-relay "$RELAY_HOST" --pool-relay-port "$RELAY_PORT")
elif [ -n "${RELAY_IPV4:-}" ]; then
  RELAY_ARGS=(--pool-relay-ipv4 "$RELAY_IPV4" --pool-relay-port "$RELAY_PORT")
else
  echo "error: set RELAY_HOST=<dns name> or RELAY_IPV4=<address> so peers can reach this node" >&2
  exit 1
fi

for f in cold.vkey cold.skey vrf.vkey bls.skey payment.vkey payment.skey payment.addr stake.vkey stake.skey; do
  [ -r "$KEYS_DIR/$f" ] || { echo "error: $KEYS_DIR/$f missing — run ./make-spo-keys.sh first" >&2; exit 1; }
done
mkdir -p "$WORK"

echo "cardano-cli:   $CLI"
echo "network:       magic $MAGIC"
echo "pledge:        $PLEDGE lovelace"
echo "cost:          $POOL_COST lovelace (network minimum $MIN_POOL_COST)"
echo "margin:        $MARGIN"
echo "relay:         ${RELAY_ARGS[*]}"
echo "deposits due:  $POOL_DEPOSIT (pool) + $KEY_DEPOSIT (stake key) lovelace, plus fees"
echo

make_certs() {
  echo "building certificates…"
  # The BLS *signing* key: the certificate carries a proof of possession, which
  # only the secret can produce. This is what registers the Leios voting key.
  "$CLI" dijkstra stake-pool registration-certificate \
    --cold-verification-key-file "$KEYS_DIR/cold.vkey" \
    --vrf-verification-key-file "$KEYS_DIR/vrf.vkey" \
    --bls-signing-key-file "$KEYS_DIR/bls.skey" \
    --pool-pledge "$PLEDGE" \
    --pool-cost "$POOL_COST" \
    --pool-margin "$MARGIN" \
    --pool-reward-account-verification-key-file "$KEYS_DIR/stake.vkey" \
    --pool-owner-stake-verification-key-file "$KEYS_DIR/stake.vkey" \
    "${RELAY_ARGS[@]}" "${NET[@]}" \
    --out-file "$WORK/pool-registration.cert"

  "$CLI" dijkstra stake-address registration-certificate \
    --stake-verification-key-file "$KEYS_DIR/stake.vkey" \
    --key-reg-deposit-amt "$KEY_DEPOSIT" \
    --out-file "$WORK/stake-registration.cert"

  "$CLI" dijkstra stake-address stake-delegation-certificate \
    --stake-verification-key-file "$KEYS_DIR/stake.vkey" \
    --cold-verification-key-file "$KEYS_DIR/cold.vkey" \
    --out-file "$WORK/delegation.cert"

  for c in "$WORK"/*.cert; do printf '  %s\n' "$c"; done
}

pick_utxo() {
  local u; u="$(mktemp)"
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
  [ -S "$SOCKET" ] || { echo "error: no node socket at $SOCKET" >&2; exit 1; }
  local sel txin amount
  sel="$(pick_utxo)"
  txin="${sel%% *}"; amount="${sel##* }"
  if [ -z "$txin" ] || [ "$txin" = "null" ]; then
    cat >&2 <<EOF
error: no UTxO at $(cat "$KEYS_DIR/payment.addr").
Fund it first: https://faucet.leios.play.dev.cardano.org/basic-faucet
EOF
    exit 1
  fi
  echo "input:         $txin ($amount lovelace)"
  local need=$(( POOL_DEPOSIT + KEY_DEPOSIT + PLEDGE ))
  if [ "$amount" -lt "$need" ]; then
    echo "error: that UTxO holds $amount lovelace; the deposits alone need $need plus fees" >&2
    exit 1
  fi
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra transaction build \
    --tx-in "$txin" \
    --change-address "$(cat "$KEYS_DIR/payment.addr")" \
    --certificate-file "$WORK/stake-registration.cert" \
    --certificate-file "$WORK/pool-registration.cert" \
    --certificate-file "$WORK/delegation.cert" \
    --witness-override 3 \
    "${NET[@]}" --out-file "$WORK/tx.raw"
  "$CLI" dijkstra transaction sign --tx-body-file "$WORK/tx.raw" \
    --signing-key-file "$KEYS_DIR/payment.skey" \
    --signing-key-file "$KEYS_DIR/stake.skey" \
    --signing-key-file "$KEYS_DIR/cold.skey" \
    "${NET[@]}" --out-file "$WORK/tx.signed"
  echo "signed:        $WORK/tx.signed"
}

submit_tx() {
  [ -r "$WORK/tx.signed" ] || { echo "error: no signed tx — run the 'build' step" >&2; exit 1; }
  CARDANO_NODE_SOCKET_PATH="$SOCKET" "$CLI" dijkstra transaction submit \
    --tx-file "$WORK/tx.signed" "${NET[@]}"
  local pid
  pid="$("$CLI" dijkstra stake-pool id --output-bech32 --cold-verification-key-file "$KEYS_DIR/cold.vkey")"
  cat <<EOF

submitted.

Pool id: $pid

Next:
  1. Delegate stake to that pool id with the faucet's *delegate* widget:
     https://faucet.leios.play.dev.cardano.org/basic-faucet
  2. Wait ~2 epochs (6 h each here) for the stake snapshot — that is when the
     pool becomes schedulable AND when Leios committee seating takes effect.
  3. Switch the pod to the producer:
       podman kube down musashi-relay.yaml && podman kube play musashi-bp.yaml
  4. Verify:
       cardano-cli dijkstra query pool-state --stake-pool-id <hex id> --testnet-magic $MAGIC
       cardano-cli dijkstra query kes-period-info --op-cert-file keys/opcert.cert --testnet-magic $MAGIC
EOF
}

case "$STEP" in
  certs)  make_certs ;;
  build)  make_certs; build_tx ;;
  submit) make_certs; build_tx; submit_tx ;;
  *) echo "usage: $0 [certs|build|submit]" >&2; exit 2 ;;
esac
