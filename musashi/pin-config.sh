#!/usr/bin/env bash
#
# Pin the live musashi network configuration (the Leios prototype testnet)
# into ./config, which both pod specs mount read-only at /app/config.
#
# WHY THIS EXISTS: the published relay image bakes in ouroboros-leios'
# testnet/config snapshot, which is pinned to an older chain instance
# (systemStart 2026-08-07) than the network now running (2026-09-07).
# Mounting a freshly pinned config over /app/config is what makes the
# container follow the live chain. Re-run this whenever the testnet rolls.
#
# Usage:
#   ./pin-config.sh                     # default: book.play.dev.cardano.org
#   ./pin-config.sh https://other/env   # a staging site or playground branch
#
# Env:
#   EXPOSE_METRICS=0   keep the published 127.0.0.1 Prometheus bind address
#                      (default 1: rebind to 0.0.0.0 so the host can scrape
#                      the container's :12798)

set -euo pipefail

BASE="${1:-https://book.play.dev.cardano.org/environments-pre/leios}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HERE/config"
EXPOSE_METRICS="${EXPOSE_METRICS:-1}"

FILES=(
  alonzo-genesis.json
  byron-genesis.json
  config.json
  conway-genesis.json
  dijkstra-genesis.json
  peer-snapshot.json
  shelley-genesis.json
  topology.json
)

json_ok() {
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$1" >/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$1" >/dev/null
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Pinning from $BASE"
for f in "${FILES[@]}"; do
  printf '  %-24s' "$f"
  # -f so an HTML 404 page is an error, not a "config file".
  curl -sSfo "$tmp/$f" "$BASE/$f"
  json_ok "$tmp/$f"
  printf 'ok (%s bytes)\n' "$(wc -c < "$tmp/$f")"
done

# Hashes are of the files exactly as published, before the metrics patch
# below, so they can be compared with upstream and with earlier pins.
{
  echo "# Pinned $(date -u +%Y-%m-%dT%H:%M:%SZ) from $BASE"
  echo "# sha256 of the published files, before any local patch"
  echo "# EXPOSE_METRICS=$EXPOSE_METRICS (1 = config.json rebound to 0.0.0.0 after hashing)"
  for f in "${FILES[@]}"; do
    echo "$(sha256 "$tmp/$f")  $f"
  done
} > "$tmp/PINNED.txt"

if [ "$EXPOSE_METRICS" != "0" ]; then
  # The published config binds PrometheusSimple to 127.0.0.1, which inside a
  # container means "unreachable from the host" — the hostPort mapping in
  # the pod specs would forward to nothing. Rebind to 0.0.0.0; the port
  # is still only exposed as far as the pod's port mapping allows.
  sed -i.bak 's/PrometheusSimple suffix 127\.0\.0\.1 /PrometheusSimple suffix 0.0.0.0 /' "$tmp/config.json"
  rm -f "$tmp/config.json.bak"
  grep -q 'PrometheusSimple suffix 0\.0\.0\.0' "$tmp/config.json" \
    || echo "  warning: could not rebind the Prometheus backend — check config.json by hand" >&2
fi

mkdir -p "$DEST"
cp -f "$tmp"/*.json "$tmp/PINNED.txt" "$DEST/"

echo
echo "Pinned into $DEST"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$DEST" <<'PY'
import json, math, sys, pathlib
d = pathlib.Path(sys.argv[1])
cfg = json.loads((d / "config.json").read_text())
sh = json.loads((d / "shelley-genesis.json").read_text())
dj = json.loads((d / "dijkstra-genesis.json").read_text())
print(f"  systemStart      {sh['systemStart']}   (chain instance)")
print(f"  networkMagic     {sh['networkMagic']}")
print(f"  slotLength       {sh['slotLength']} s, epoch {sh['epochLength']} slots, f = {sh['activeSlotsCoeff']}")
print(f"  MinNodeVersion   {cfg.get('MinNodeVersion')}   (the image must be at least this)")
hdr, vote, diff = (dj.get(k) for k in
                   ("leiosAnnouncementPeriodLength", "leiosVotePeriodLength", "leiosDiffusionPeriodLength"))
if None not in (hdr, vote, diff):
    gap = math.ceil((3 * hdr + vote + diff) / (sh["slotLength"] * 1000))
    print(f"  Leios periods    L_hdr {hdr} ms, L_vote {vote} ms, L_diff {diff} ms")
    print(f"  committee/quorum N_c = {dj.get('leiosCommitteeSize')}, tau = {dj.get('leiosQuorumStakeThreshold')}")
    print(f"  cert gap         ceil((3*L_hdr + L_vote + L_diff)/slot) = {gap} slots")
else:
    print("  note: no leios* parameters in dijkstra-genesis.json — pre-Leios or older snapshot")
PY
fi
