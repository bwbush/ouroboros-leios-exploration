# Running a musashi Leios node — cheatsheet

**Provenance:** ⏳🤖 LLM-generated, pending human review · **Layer:** deployed network (musashi) + implementation (`cardano-node@leios-prototype`) · **Verified:** 2026-09-30

> [!IMPORTANT]
> **This deployment is retired and intentionally stopped.** Pool **ΘΕΛΩ** (`THELO`, `pool13pssq9ar0n7t7jt3y7cmusl06ufhd02j7wacwuanmnursyyr7qu`) retired in epoch 84, beginning 2026-09-28 00:00 UTC. The public chain index reports zero stake and zero delegators from epoch 85. The files remain for analysis and possible later reactivation; do not start the producer pod without first following the re-registration and activation procedure in [block-producer.md](./block-producer.md#retire-the-pool).
>
> Container names follow the pod: `musashi-relay-node` under the relay spec, `musashi-bp-node` under the producer's. Current generic-node examples use the relay; producer-specific examples are historical or conditional on reactivation.
>
> The historical producer was active from epoch 64 until retirement epoch 84. It forged 57 lifetime Ranking Blocks according to the public chain index.

> [!NOTE]
> **What has actually been exercised**, as of 2026-09-30: `pin-config.sh`, the relay and producer pods, both key scripts, pool registration, delegation, block production, Leios voting, retirement-transaction construction and submission, and orderly shutdown. The version-skew stall in Troubleshooting is a real incident, not a hypothetical. Still unexercised: KES rotation, reactivation after retirement, re-pinning after a network respin, and the `aarch64-linux` image. Facts about the image, config, and command-line interface (CLI) flags come from published metadata, live network configuration, pinned source, or the dated [observations log](./observations.md).

## TL;DR

```shell
cd musashi
# No pod is intentionally running while the pool is retired.
./pin-config.sh                          # fetch the live network config before any future run
podman kube play musashi-relay.yaml      # optional non-producing observer only
podman logs -f musashi-relay-node        # watch it sync
podman kube down musashi-relay.yaml      # stop and remove
```

## What this gives you

The relay spec gives a **non-block-producing** node on `musashi` (the public Leios prototype testnet, network magic **164**), following the chain from the bootstrap relay `leios-node.play.dev.cardano.org:3001` and fanning out to ledger peers once past slot 151,200 (`useLedgerAfterSlot` in `topology.json`).

| Where | What |
|---|---|
| `./config/` | The pinned network configuration, mounted read-only at `/app/config`. Gitignored — it rolls. |
| `/data/musashi/` on the host | Chain database (`db/`), Leios SQLite stores (`leios.db*`), `node.socket`, and `node.log`; mounted at `/data` in the container. This explicit host path is outside the repository. |
| `:3010` | Node-to-node, published on all interfaces. **The only port that needs to be public.** Inbound isn't needed to sync, but it is what makes this a relay. |
| `127.0.0.1:12798` | Prometheus metrics, bound to loopback in the pod spec because the endpoint is unauthenticated (see the rebind note under [Step 1](#step-1--pin-the-live-network-configuration)). |

The image is `ghcr.io/input-output-hk/ouroboros-leios/cardano-node-testnet`, currently tag **`prototype-2026w38a`**, digest-pinned in both YAML files to multi-architecture manifest `sha256:e9e501692d08f88ba372557a59d0c8189cb29f0416fea4e987dff046cad16227`. Its `CMD` is `/app/run-node.sh`, which copies `/app/config` into `/data` and runs `cardano-node run` there.

> [!IMPORTANT]
> **Match the image's week to the network, not to `main`.** `MinNodeVersion` is a floor, not a semantic compatibility guarantee: a mismatched weekly image can start, sync for days, and then reject a block the network accepted because prototype ledger rules move without a hard fork. This happened when a w38 node joined the then-w36 chain. The chain kept its 2026-09-07 genesis, but by 2026-09-30 its published configuration named **w38a**; both YAML files and the development shell now match that value. Recheck before every future start.

## Prerequisites

- **podman** (validated against the field support and semantics of 5.4.1). Rootless is fine when your user can write `/data/musashi`: the container runs as root, which maps to your user ID, so files there come out owned by you.
- Outbound TCP to `leios-node.play.dev.cardano.org:3001` (resolves to 8 IPv4 and 8 IPv6 addresses; verified reachable 2026-09-21).
- `curl`, and `jq` or `python3`, for `pin-config.sh`.
- Disk: **~25 GB on an SSD**, per upstream's own system requirements, which also ask for 2 cores and 4 GB RAM (the node uses ~2–2.5 GB). The chain instance is young — it began 2026-09-07 — but the network is respun every couple of weeks, so plan for the resync rather than for steady growth.

## Step 1 — pin the live network configuration

```shell
./pin-config.sh
```

**This step is not optional, and it is the one thing that is easy to get wrong.** The published image bakes in `ouroboros-leios`' `testnet/config` snapshot, which is pinned to a **different chain instance** than the one now running: baked `systemStart` is 2026-08-07, the live network's is 2026-09-07 (genesis hashes and `MinNodeVersion` differ accordingly). A node started on the baked config computes slot times from the wrong epoch and will not follow the live chain. Mounting a freshly pinned `./config` over `/app/config` is what fixes that.

The script fetches the eight published files, validates them as JSON (so an HTML 404 page can't masquerade as a config), records their pre-patch SHA-256 sums in `config/PINNED.txt`, and prints the parameters in force:

```
  systemStart      2026-09-07T00:00:00Z   (chain instance)
  networkMagic     164
  slotLength       1 s, epoch 21600 slots, f = 0.05
  MinNodeVersion   11.1.0.164-prototype-2026w38a  (pin the image to THIS week)
  Leios periods    L_hdr 1000 ms, L_vote 4000 ms, L_diff 7000 ms
  committee/quorum N_c = 900, tau = 0.75
  cert gap         ceil((3*L_hdr + L_vote + L_diff)/slot) = 14 slots
```

One local patch is applied by default: the published `config.json` binds the Prometheus backend to `127.0.0.1`, which inside a container means "unreachable from the host" and would leave the `:12798` port mapping pointing at nothing. The script rebinds it to `0.0.0.0` **after** hashing, so `PINNED.txt` still records the upstream bytes. `EXPOSE_METRICS=0 ./pin-config.sh` keeps the published value.

## Step 2 — start the pod

```shell
podman kube play musashi-relay.yaml          # add --replace to recreate a non-producing observer
```

Run it **from this directory**: the YAML resolves the relative `./config` host volume against the current directory. Node data uses the explicit host path `/data/musashi`.

[`musashi-bp.yaml`](./musashi-bp.yaml) additionally resolves `./keys` and loads production credentials. It is retained for a deliberate future reactivation, after pool re-registration, delegation, snapshot activation, and key checks. Do not run both specifications simultaneously: they share the data directory and host ports.

## Step 3 — confirm it is syncing

```shell
podman logs -f musashi-relay-node              # or: tail -f /data/musashi/node.log
podman exec musashi-relay-node cardano-cli query tip --testnet-magic 164
curl -s localhost:12798/metrics | grep -i leios
```

`cardano-cli` is in the image and `CARDANO_NODE_SOCKET_PATH` is already set inside the container, so the `query tip` line works as written. The host's own `cardano-cli` can use `/data/musashi/node.socket` too, if you have one built from the same `leios-prototype` branch.

## Step 4 — watch Leios specifically

The pinned `config.json` already sets `Consensus.LeiosKernel`, `Consensus.LeiosPeer`, `LeiosFetch.Remote` and `LeiosNotify.Remote` to `Debug` with no rate limit (the vote send/receive tracers are silenced). Greppable trace kinds:

| `"kind"` | Meaning |
|---|---|
| `LeiosBlockPointMissing` | **Expected, not a fault.** Emitted unconditionally for every novel endorser block (EB) body, one line before an idempotent insert — an acquisition counter with a warning's severity. Its count should match `LeiosBlockAcquired`. |
| `LeiosBlockAcquired` / `LeiosBlockTxsAcquired` | An EB body / its transaction closure arrived from a peer. |
| `LeiosBlockForged` / `LeiosBlockCertified` | EB production and certification — emitted by producers, so you see the effects here, not the events. |
| `CertRBStaged` / `CertRBReleased` | A certificate-carrying ranking block (CertRB) parked because its EB closure wasn't local yet, and released when it arrived. |

**To collect transaction-flow data** (push, pull, mempool, cache) you will need a config change first — the shipped config silences the whole tx-submission path. Namespace map, patch, and analysis recipes: [Collecting transaction-flow data](../arc-leios-ha/background/pre-scoping/leios-tx-flow-instrumentation.md).

**What else you can point at this node** — the `cardano-cli dijkstra` surface (including Boneh–Lynn–Shacham (BLS) key generation), the SQLite store you can query for EB overlap, `tx-firehose` and `mempool-monitor`, the local devnets, and where the observability gaps are: see [Tooling for a running Leios node](../arc-leios-ha/background/pre-scoping/leios-node-tooling.md).

What the numbers mean — the certification gap, quorum, EB capacity limits, and which of them are actually enforced — is in [the protocol-parameter note](../arc-leios-ha/background/pre-scoping/leios-node-protocol-parameters.md) and [the timing-inequalities timeline](../arc-leios-ha/background/pre-scoping/leios-timing-inequalities.svg).

## Building the CLI yourself

**The repository's dev shell now provides it.** `nix develop` at the repo root puts `cardano-cli`, `cardano-node`, `tx-firehose`, and `mempool-monitor` on `PATH`, from the pinned `prototype-2026w38a` release tarball ([`nix/cardano-node-leios.nix`](../nix/cardano-node-leios.nix)); `nix build .#cardano-cli` gets just the CLI. Bump the week there when the network rolls.

Two alternatives: the image's `cardano-cli` is statically linked, so `podman cp musashi-bp-node:/usr/local/bin/cardano-cli .` is the quick way to get one; or build from upstream's flake, at the release tag whose `flake.lock` pins the same `cardano-node` rev the image reports:

```shell
nix build github:input-output-hk/ouroboros-leios/prototype-2026w38a#cardano-cli-static
./result/bin/cardano-cli --version     # verify the rev against the release in force
```

`cardano-cli-static` is **x86_64-linux only**; on aarch64 Linux or Apple silicon build `#cardano-node-release`, a tarball with `cardano-node`, `cardano-cli`, `tx-firehose`, and `mempool-monitor`. Either needs the IOG binary cache — `https://cache.iog.io`, key `hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=` — which the flake declares in its own `nixConfig` but Nix honors only for a **trusted** user; otherwise pass `--extra-substituters` / `--extra-trusted-public-keys` yourself, or it will start building GHC. The flake also needs `allow-import-from-derivation`.

## Day-to-day

| Task | Command |
|---|---|
| Stop, keep the data | `podman pod stop musashi-relay` |
| Start again | `podman pod start musashi-relay` |
| Stop and remove the pod | `podman kube down musashi-relay.yaml` |
| Recreate after editing the YAML | `podman kube play --replace musashi-relay.yaml` |
| Shell in | `podman exec -it musashi-relay-node bash` |
| Reset the chain state | Stop the relay, verify `/data/musashi` is the intended chain directory, then remove it before replaying the new chain. |

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Node exits complaining about the node version | The image is older than the live config's `MinNodeVersion` (`11.1.0.164-prototype-2026w38a` when checked 2026-09-30). Move to the week currently named there — tag and digest together. An arbitrarily newer build is not safer: see the churn row below. |
| Syncs nothing, or peers disconnect immediately | Almost certainly the stale baked config — check `config/PINNED.txt` exists and its `systemStart` matches the live network. Re-run `./pin-config.sh`, then `podman kube down` and `play` again. |
| Config edits have no effect | The startup command re-copies `/app/config` over `/data` on **every** start. Edit `./config/`, not the copied files under `/data/musashi`. |
| `curl localhost:12798/metrics` refused | The Prometheus rebind didn't happen (`EXPOSE_METRICS=0`, or a hand-edited config). Re-pin, then restart. |
| podman rejects a relative `hostPath` | Run from this directory. The relative paths are `./config` in both specifications and `./keys` in the producer specification; `/data/musashi` is already absolute. |
| Permission denied on a host volume (SELinux hosts) | Podman gives `hostPath` volumes a shared label, but pre-existing bind mounts may need relabeling: `chcon -t container_file_t -R config keys /data/musashi`. |
| The node stops advancing and churns peers | Version skew. Look for `"ns":"ChainSync.Client.Exception"` with `InvalidBlock` at a fixed slot, repeating once per peer, plus `BlockchainTime.CurrentSlotUnknown`: your node rejects a block the network accepted, drops that peer, reconnects, and repeats. Compare your tip with the network's (`cardano-cli ping -h leios-node.play.dev.cardano.org -p 3001 -m 164 -t -c 1 -j`); if the network is far ahead of the rejected slot, your node is the outlier. Fix: pin the image to the week the live config's `MinNodeVersion` names and restart. |
| Port 3010 or 12798 already in use | Change `hostPort` in the YAML; if you change the node's port, change the `PORT` env var to match. |

## Re-pinning when the testnet rolls

```shell
./pin-config.sh
podman kube down musashi-relay.yaml
# If systemStart changed, remove the dead chain state now: rm -rf /data/musashi
podman kube play musashi-relay.yaml
```

Config is read only at start, so a re-pin needs a restart. **If `systemStart` changed, the chain is a new instance and the old database is worthless** — remove `/data/musashi` after stopping the pod and before restarting. Diff `config/PINNED.txt` against the previous pin to see what moved; the hashes there are of the published bytes, so they compare directly with the ones recorded in [the parameter note](../arc-leios-ha/background/pre-scoping/leios-node-protocol-parameters.md#sources).

A respin is more than a re-pin for a *producer*: the registration, stake, and KES clock all reset while the keys survive. The runbook is [block-producer.md § 7](./block-producer.md#7-when-the-network-is-respun).

`./config` is gitignored on purpose, while `/data/musashi` lives outside the repository. Committing a snapshot of a rolling network config is exactly the trap upstream fell into — their committed snapshot is six weeks and one chain instance behind the network it claims to join.

## Deliberately not here

- **The X-ray stack** (Prometheus + Loki + Grafana + Alloy) that upstream's `testnet/run.sh` brings up under process-compose. The image is node-only by design; the `:12798` scrape target is there when you want to point something at it.
- **Block production** in the relay pod. That is [`musashi-bp.yaml`](./musashi-bp.yaml); see below.

## Running as a stake pool operator (SPO)

**Full procedure: [block-producer.md](./block-producer.md)** — keys, certificates, deposits, the pod swap, the two 93-day rotations, and what a single-node producer costs you. In outline, four things change, and only the first is Leios-specific:

1. **A Boneh–Lynn–Shacham (BLS) key.** `cardano-node` takes `--shelley-bls-key FILEPATH`, "Path to the BLS (Leios) signing key" ([`Parsers.hs:420`](https://github.com/IntersectMBO/cardano-node/blob/7e33674108ed17eeeda3a25e98b66a610cbd99ff/cardano-node/src/Cardano/Node/Parsers.hs#L420)), alongside the usual `--shelley-operational-certificate`, `--shelley-kes-key`, and `--shelley-vrf-key`.
2. **Registration.** The BLS public key and its proof of possession travel on the **pool registration certificate**, not a separate transaction: `sppBlsKey :: StrictMaybe BlsKey` on `StakePoolParams`, where `BlsKey = { blsPubKey, blsPossessionProof }` over BLS12-381 min-sig ([`StakePool.hs:464`](https://github.com/IntersectMBO/cardano-ledger/blob/1587f21a7d1306dc590c2749a5c66232ef66aad0/libs/cardano-ledger-core/src/Cardano/Ledger/State/StakePool.hs#L464)). The ledger records the epoch of registration (`BlsKeyState`), and a key is honored only while `epoch < registeredIn + maxKeyAge` — **374 epochs** at musashi's KES settings, about 93 days at six-hour epochs.
3. **A committee seat, which stake alone doesn't guarantee.** Seating is the top `N_c = 900` pools by stake; a seated pool with no registered BLS key is *keyless* — it occupies a seat and cannot vote, and any certificate bit set on it invalidates the certificate. Details in [the parameter note § 3](../arc-leios-ha/background/pre-scoping/leios-node-protocol-parameters.md).
4. **A different container command.** `/app/run-node.sh` takes no key flags, so a producer must override `command:` and mount a `./keys` volume — [`musashi-bp.yaml`](./musashi-bp.yaml) is that pod, ready to play.

Musashi stake is self-service: after a pool registration is on chain, submit its bech32 pool identifier through the faucet's **delegate** widget. This deployment completed that sequence in epoch 62, became active in epoch 64, and retired in epoch 84. A future reactivation needs a new registration and delegation followed by the normal activation delay.

## Sources

- Upstream's user-facing testnet documentation, which is the canonical operator path and worth reading alongside this: [install and run a node](https://leios.cardano-scaling.org/docs/testnet/getting-started/), [register a stake pool](https://leios.cardano-scaling.org/docs/testnet/register-stake-pool/), [SPO Rewards Program](https://leios.cardano-scaling.org/docs/testnet/rewards-program/), the [faucet](https://faucet.leios.play.dev.cardano.org/basic-faucet), and the [Musashi Dōjō Discord](https://discord.gg/AyUXD9VHn). Their Docker section calls the config mount "optional — drop it to fall back to the in-image snapshot"; **do not**, for the reason in Step 1.

- [MusashiNet prototype — Cardano Operations Book](https://book.play.dev.cardano.org/adv-musashi.html), and the configuration it publishes at [`environments-pre/leios`](https://book.play.dev.cardano.org/environments-pre/leios/config.json). Rechecked 2026-09-30: `systemStart` and genesis files remain unchanged, while `config.json` advanced to w38a and SHA-256 `3966e3d8d224fcf29ddc60ebd3fc4472b57bf010e16f44933651a7c60b54e126`.
- [`ouroboros-leios/testnet/README.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/testnet/README.md) and [`Dockerfile`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/testnet/Dockerfile) @ `9fa5a95` (2026-09-21) — upstream's own relay setup, which this folder follows for the image and diverges from on config pinning.
- Current release evidence checked 2026-09-30: the published configuration names `11.1.0.164-prototype-2026w38a`; the GHCR registry reports multi-architecture manifest digest `sha256:e9e501692d08f88ba372557a59d0c8189cb29f0416fea4e987dff046cad16227`; the release tag pins cardano-node revision `8c44d14542f41e96b657d013c6e183bcee9dfd85`. The historical producer capture used w36 at digest `sha256:0df972de2193f9299af4df409fde2b7ea56188ddfe2c3b77aa661e23b226a566`, revision `afa091b4`.
- CLI flags: [`cardano-node@leios-prototype` `Parsers.hs`](https://github.com/IntersectMBO/cardano-node/blob/7e33674108ed17eeeda3a25e98b66a610cbd99ff/cardano-node/src/Cardano/Node/Parsers.hs#L375-L424) @ `7e33674`. Ledger types: [`cardano-ledger` `StakePool.hs`](https://github.com/IntersectMBO/cardano-ledger/blob/1587f21a7d1306dc590c2749a5c66232ef66aad0/libs/cardano-ledger-core/src/Cardano/Ledger/State/StakePool.hs#L460-L536) @ `1587f21`.
- `podman kube play` field support and volume semantics: the podman 5.4.1 manual page.
