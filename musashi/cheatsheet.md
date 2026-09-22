# Running a musashi Leios node — cheatsheet

**Provenance:** ⏳🤖 LLM-generated, pending human review · **Layer:** deployed network (musashi) + implementation (`cardano-node@leios-prototype`) · **Verified:** 2026-09-21

> [!WARNING]
> **What is and isn't tested.** Every fact below — image digest, entrypoint,
> ports, config contents, CLI flags — was read from the published image
> metadata, the live network config, or pinned source, and `./pin-config.sh`
> was run end to end. The pod itself was **not** started here: this sandbox
> forbids the nested user namespace podman needs. Expect to debug the first
> `podman kube play`, and record what it took in [the journal](../journal/phase-0.md).

## TL;DR

```shell
cd musashi
./pin-config.sh                       # fetch the live network config
podman kube play musashi-relay.yaml   # start the relay
podman logs -f musashi-relay-node     # watch it sync
podman kube down musashi-relay.yaml   # stop and remove
```

## What this gives you

A single **non-block-producing relay** on `musashi` (the public Leios
prototype testnet, network magic **164**), following the chain from the
bootstrap relay `leios-node.play.dev.cardano.org:3001` and fanning out to
ledger peers once past slot 151,200 (`useLedgerAfterSlot` in `topology.json`).

| Where | What |
|---|---|
| `./config/` | The pinned network configuration, mounted read-only at `/app/config`. Gitignored — it rolls. |
| `./data/` | Chain DB (`db/`), Leios SQLite stores (`leios.db*`), `node.socket`, `node.log`. Gitignored. |
| `localhost:3010` | Node-to-node. Inbound isn't needed to sync, but it's what makes this a relay. |
| `localhost:12798` | Prometheus metrics (see the rebind note under [Step 1](#step-1--pin-the-live-network-configuration)). |

The image is `ghcr.io/input-output-hk/ouroboros-leios/cardano-node-testnet`,
tag **`prototype-2026w36`**, digest-pinned in the YAML (multi-arch
amd64/arm64, ~80 MiB compressed). Its `CMD` is `/app/run-node.sh`, which
copies `/app/config` into `/data` and runs `cardano-node run` there.

> [!IMPORTANT]
> **Match the image's week to the network, not to `main`.** `MinNodeVersion`
> is a floor, not a match: a newer weekly image passes it, starts, syncs for
> days — and then rejects a block the network accepted, because the prototype's
> ledger rules move between weeklies without a hard fork. The chain running
> since 2026-09-07 was deployed from **w36** (node rev `afa091b4`), and w38
> carries a newer `cardano-ledger`. Pin the week the live config names.

## Prerequisites

- **podman** (validated against the field support and semantics of 5.4.1).
  Rootless is fine: the container runs as root, which maps to your uid, so
  files under `./data/` come out owned by you.
- Outbound TCP to `leios-node.play.dev.cardano.org:3001` (resolves to 8 IPv4
  and 8 IPv6 addresses; verified reachable 2026-09-21).
- `curl`, and `jq` or `python3`, for `pin-config.sh`.
- Disk: **~25 GB on an SSD**, per upstream's own system requirements, which
  also ask for 2 cores and 4 GB RAM (the node uses ~2–2.5 GB). The chain
  instance is young — it began 2026-09-07 — but the network is respun every
  couple of weeks, so plan for the resync rather than for steady growth.

## Step 1 — pin the live network configuration

```shell
./pin-config.sh
```

**This step is not optional, and it is the one thing that is easy to get
wrong.** The published image bakes in `ouroboros-leios`' `testnet/config`
snapshot, which is pinned to a **different chain instance** than the one now
running: baked `systemStart` is 2026-08-07, the live network's is 2026-09-07
(genesis hashes and `MinNodeVersion` differ accordingly). A node started on
the baked config computes slot times from the wrong epoch and will not follow
the live chain. Mounting a freshly pinned `./config` over `/app/config` is
what fixes that.

The script fetches the eight published files, validates them as JSON (so an
HTML 404 page can't masquerade as a config), records their pre-patch SHA-256
sums in `config/PINNED.txt`, and prints the parameters in force:

```
  systemStart      2026-09-07T00:00:00Z   (chain instance)
  networkMagic     164
  slotLength       1 s, epoch 21600 slots, f = 0.05
  MinNodeVersion   11.1.0.164-prototype-2026w36   (pin the image to THIS week)
  Leios periods    L_hdr 1000 ms, L_vote 4000 ms, L_diff 7000 ms
  committee/quorum N_c = 900, tau = 0.75
  cert gap         ceil((3*L_hdr + L_vote + L_diff)/slot) = 14 slots
```

One local patch is applied by default: the published `config.json` binds the
Prometheus backend to `127.0.0.1`, which inside a container means
"unreachable from the host" and would leave the `:12798` port mapping
pointing at nothing. The script rebinds it to `0.0.0.0` **after** hashing, so
`PINNED.txt` still records the upstream bytes. `EXPOSE_METRICS=0
./pin-config.sh` keeps the published value.

## Step 2 — start the pod

```shell
podman kube play musashi-relay.yaml          # add --replace to recreate
```

Run it **from this directory**: the YAML uses relative `hostPath` volumes
(`./config`, `./data`), which podman resolves against your current directory.

## Step 3 — confirm it is syncing

```shell
podman logs -f musashi-relay-node            # or: tail -f data/node.log
podman exec musashi-relay-node cardano-cli query tip --testnet-magic 164
curl -s localhost:12798/metrics | grep -i leios
```

`cardano-cli` is in the image and `CARDANO_NODE_SOCKET_PATH` is already set
inside the container, so the `query tip` line works as written. The host's
own `cardano-cli` can use `./data/node.socket` too, if you have one built
from the same `leios-prototype` branch.

## Step 4 — watch Leios specifically

The pinned `config.json` already sets `Consensus.LeiosKernel`,
`Consensus.LeiosPeer`, `LeiosFetch.Remote` and `LeiosNotify.Remote` to
`Debug` with no rate limit (the vote send/receive tracers are silenced).
Greppable trace kinds:

| `"kind"` | Meaning |
|---|---|
| `LeiosBlockPointMissing` | **Expected, not a fault.** Emitted unconditionally for every novel EB body, one line before an idempotent insert — an acquisition counter with a warning's severity. Its count should match `LeiosBlockAcquired`. |
| `LeiosBlockAcquired` / `LeiosBlockTxsAcquired` | An EB body / its transaction closure arrived from a peer. |
| `LeiosBlockForged` / `LeiosBlockCertified` | EB production and certification — emitted by producers, so you see the effects here, not the events. |
| `CertRBStaged` / `CertRBReleased` | A CertRB parked because its EB closure wasn't local yet, and released when it arrived. |

**To collect transaction-flow data** (push, pull, mempool, cache) you will need a
config change first — the shipped config silences the whole tx-submission path.
Namespace map, patch, and analysis recipes:
[Collecting transaction-flow data](../artifacts/leios-tx-flow-instrumentation.md).

**What else you can point at this node** — the `cardano-cli dijkstra` surface (including
BLS key generation), the SQLite store you can query for EB overlap, `tx-firehose` and
`mempool-monitor`, the local devnets, and where the observability gaps are: see
[Tooling for a running Leios node](../artifacts/leios-node-tooling.md).

What the numbers mean — the certification gap, quorum, EB capacity limits,
and which of them are actually enforced — is in
[the protocol-parameter note](../artifacts/leios-node-protocol-parameters.md)
and [the timing-inequalities timeline](../artifacts/leios-timing-inequalities.svg).

## Building the CLI yourself

**The repository's dev shell now provides it.** `nix develop` at the repo root
puts `cardano-cli`, `cardano-node`, `tx-firehose`, and `mempool-monitor` on
`PATH`, from the pinned `prototype-2026w36` release tarball
([`nix/cardano-node-leios.nix`](../nix/cardano-node-leios.nix)); `nix build
.#cardano-cli` gets just the CLI. Bump the week there when the network rolls.

Two alternatives: the image's `cardano-cli` is statically linked, so `podman cp
musashi-relay-node:/usr/local/bin/cardano-cli .` is the quick way to get one;
or build from upstream's flake, at the release tag whose `flake.lock` pins the
same `cardano-node` rev the image reports:

```shell
nix build github:input-output-hk/ouroboros-leios/prototype-2026w36#cardano-cli-static
./result/bin/cardano-cli --version
```

`cardano-cli-static` is **x86_64-linux only**; on aarch64 Linux or Apple
silicon build `#cardano-node-release`, a tarball with `cardano-node`,
`cardano-cli`, `tx-firehose`, and `mempool-monitor`. Either needs the IOG
binary cache — `https://cache.iog.io`, key
`hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=` — which the flake
declares in its own `nixConfig` but Nix honors only for a **trusted** user;
otherwise pass `--extra-substituters` / `--extra-trusted-public-keys` yourself,
or it will start building GHC. The flake also needs
`allow-import-from-derivation`.

## Day-to-day

| Task | Command |
|---|---|
| Stop, keep the data | `podman pod stop musashi-relay` |
| Start again | `podman pod start musashi-relay` |
| Stop and remove the pod | `podman kube down musashi-relay.yaml` |
| Recreate after editing the YAML | `podman kube play --replace musashi-relay.yaml` |
| Shell in | `podman exec -it musashi-relay-node bash` |
| Reset the chain state | `podman kube down musashi-relay.yaml && rm -rf data` |

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Node exits complaining about the node version | The image is older than the live config's `MinNodeVersion` (currently `11.1.0.164-prototype-2026w36`). Move to that week's image — tag *and* digest together. Newer is not safer: see the churn row below. |
| Syncs nothing, or peers disconnect immediately | Almost certainly the stale baked config — check `config/PINNED.txt` exists and its `systemStart` matches the live network. Re-run `./pin-config.sh`, then `podman kube down` and `play` again. |
| Config edits have no effect | `/app/run-node.sh` re-copies `/app/config` over `/data` on **every** start. Edit `./config/`, never `./data/`. |
| `curl localhost:12798/metrics` refused | The Prometheus rebind didn't happen (`EXPOSE_METRICS=0`, or a hand-edited config). Re-pin, then restart. |
| podman rejects the relative `hostPath` | Run from this directory. If your podman still objects: `sed "s\|\./\|$PWD/\|" musashi-relay.yaml \| podman kube play -` |
| Permission denied on `./config` or `./data` (SELinux hosts) | Podman gives `hostPath` volumes a shared label, but pre-existing bind mounts aren't relabeled: `chcon -t container_file_t -R config data`. |
| The node stops advancing and churns peers | Version skew. Look for `"ns":"ChainSync.Client.Exception"` with `InvalidBlock` at a fixed slot, repeating once per peer, plus `BlockchainTime.CurrentSlotUnknown`: your node rejects a block the network accepted, drops that peer, reconnects, and repeats. Compare your tip with the network's (`cardano-cli ping -h leios-node.play.dev.cardano.org -p 3001 -m 164 -t -c 1 -j`); if the network is far ahead of the rejected slot, your node is the outlier. Fix: pin the image to the week the live config's `MinNodeVersion` names and restart. |
| Port 3010 or 12798 already in use | Change `hostPort` in the YAML; if you change the node's port, change the `PORT` env var to match. |

## Re-pinning when the testnet rolls

```shell
./pin-config.sh
podman kube down musashi-relay.yaml
podman kube play musashi-relay.yaml
```

Config is read only at start, so a re-pin needs a restart. **If `systemStart`
changed, the chain is a new instance and the old database is worthless** —
`rm -rf data` before restarting. Diff `config/PINNED.txt` against the previous
pin to see what moved; the hashes there are of the published bytes, so they
compare directly with the ones recorded in
[the parameter note](../artifacts/leios-node-protocol-parameters.md#sources).

`./config` and `./data` are gitignored on purpose. Committing a snapshot of a
rolling network config is exactly the trap upstream fell into — their
committed snapshot is six weeks and one chain instance behind the network it
claims to join.

## Deliberately not here

- **The X-ray stack** (Prometheus + Loki + Grafana + Alloy) that upstream's
  `testnet/run.sh` brings up under process-compose. The image is node-only by
  design; the `:12798` scrape target is there when you want to point
  something at it.
- **Block production** in the relay pod. That is [`musashi-bp.yaml`](./musashi-bp.yaml); see below.

## Running as an SPO

**Full procedure: [block-producer.md](./block-producer.md)** — keys, certificates,
deposits, the pod swap, the two 93-day rotations, and what a single-node
producer costs you. In outline, four things change, and only the first is
Leios-specific:

1. **A BLS key.** `cardano-node` takes `--shelley-bls-key FILEPATH`, "Path to
   the BLS (Leios) signing key" ([`Parsers.hs:420`](https://github.com/IntersectMBO/cardano-node/blob/7e33674108ed17eeeda3a25e98b66a610cbd99ff/cardano-node/src/Cardano/Node/Parsers.hs#L420)),
   alongside the usual `--shelley-operational-certificate`,
   `--shelley-kes-key`, and `--shelley-vrf-key`.
2. **Registration.** The BLS public key and its proof of possession travel on
   the **pool registration certificate**, not a separate transaction:
   `sppBlsKey :: StrictMaybe BlsKey` on `StakePoolParams`, where
   `BlsKey = { blsPubKey, blsPossessionProof }` over BLS12-381 min-sig
   ([`StakePool.hs:464`](https://github.com/IntersectMBO/cardano-ledger/blob/1587f21a7d1306dc590c2749a5c66232ef66aad0/libs/cardano-ledger-core/src/Cardano/Ledger/State/StakePool.hs#L464)).
   The ledger records the epoch of registration (`BlsKeyState`), and a key is
   honored only while `epoch < registeredIn + maxKeyAge` — **374 epochs** at
   musashi's KES settings, about 93 days at six-hour epochs.
3. **A committee seat, which stake alone doesn't guarantee.** Seating is the
   top `N_c = 900` pools by stake; a seated pool with no registered BLS key is
   *keyless* — it occupies a seat and cannot vote, and any certificate bit set
   on it invalidates the certificate. Details in
   [the parameter note § 3](../artifacts/leios-node-protocol-parameters.md).
4. **A different container command.** `/app/run-node.sh` takes no key flags,
   so a producer must override `command:` and mount a `./keys` volume —
   [`musashi-bp.yaml`](./musashi-bp.yaml) is that pod, ready to play.

Not established here: **how to obtain musashi stake** — whether there's a
faucet, a delegation from the operators, or a request process. Ask the
playground/testnet operators; the operations-book page below is the entry
point.

## Sources

- Upstream's user-facing testnet documentation, which is the canonical operator path and worth reading alongside this: [install and run a node](https://leios.cardano-scaling.org/docs/testnet/getting-started/), [register a stake pool](https://leios.cardano-scaling.org/docs/testnet/register-stake-pool/), [SPO Rewards Program](https://leios.cardano-scaling.org/docs/testnet/rewards-program/), the [faucet](https://faucet.leios.play.dev.cardano.org/basic-faucet), and the [Musashi Dōjō Discord](https://discord.gg/AyUXD9VHn). Their Docker section calls the config mount "optional — drop it to fall back to the in-image snapshot"; **do not**, for the reason in Step 1.

- [MusashiNet prototype — Cardano Operations Book](https://book.play.dev.cardano.org/adv-musashi.html), and the configuration it publishes at [`environments-pre/leios`](https://book.play.dev.cardano.org/environments-pre/leios/config.json) (fetched 2026-09-21; `config.json` SHA-256 `a5caf918…`, unchanged since our 2026-09-17 read).
- [`ouroboros-leios/testnet/README.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/testnet/README.md) and [`Dockerfile`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/testnet/Dockerfile) @ `9fa5a95` (2026-09-21) — upstream's own relay setup, which this folder follows for the image and diverges from on config pinning.
- Image metadata read from the GHCR registry API, 2026-09-21. In use: tag `prototype-2026w36`, digest `sha256:0df972de2193f9299af4df409fde2b7ea56188ddfe2c3b77aa661e23b226a566`, created 2026-09-07T10:45:59Z, node rev `afa091b4` (verified by extracting and running the binary). Also available: `prototype-2026w38`, digest `sha256:f515269771b923e2fc66c04c77df6e0b6779e1ccf8b1a5285c23d837c2ea7384`, created 2026-09-20T22:45:23Z, node rev `648fc48b` — newer than the running network, see the version-skew row in Troubleshooting.
- CLI flags: [`cardano-node@leios-prototype` `Parsers.hs`](https://github.com/IntersectMBO/cardano-node/blob/7e33674108ed17eeeda3a25e98b66a610cbd99ff/cardano-node/src/Cardano/Node/Parsers.hs#L375-L424) @ `7e33674`. Ledger types: [`cardano-ledger` `StakePool.hs`](https://github.com/IntersectMBO/cardano-ledger/blob/1587f21a7d1306dc590c2749a5c66232ef66aad0/libs/cardano-ledger-core/src/Cardano/Ledger/State/StakePool.hs#L460-L536) @ `1587f21`.
- `podman kube play` field support and volume semantics: the podman 5.4.1 manual page.
