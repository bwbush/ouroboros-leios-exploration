# Tooling for a running Leios node

**Provenance:** ⏳🤖 LLM-generated, pending human review · **Layer:** implementation and release artifacts · **Verified:** 2026-09-21

> [!NOTE]
> **How this was verified.** The relay image's two binaries were pulled out of
> the published layers and **run directly** — every command list, flag, and
> error message below is their own output at the exact version you are running,
> not a reading of source or documentation. Two commands were also run against
> the live testnet (`ping`) and against our pinned config
> (`debug check-node-configuration`). Everything not executed is marked.
>
> Companion documents: [`musashi/cheatsheet.md`](../musashi/cheatsheet.md) to
> get the node up, [the protocol-parameter note](./leios-node-protocol-parameters.md)
> for what the numbers mean, [the simulation/model catalog](./leios-simulation-model-catalog.md)
> for the simulator side of the tool landscape.

## 1. What is actually in the image

Both weekly images were opened; both ship the same two versions from different
revs:

| Image tag | `cardano-node` | `cardano-cli` | Git rev | Built |
|---|---|---|---|---|
| **`prototype-2026w36`** — what musashi runs | `11.1.0.164` | `11.2.2.0` | `afa091b4` | 2026-09-07 |
| `prototype-2026w38` — branch head | `11.1.0.164` | `11.2.2.0` | `648fc48b` | 2026-09-20 |

**The version strings are identical and the revs are not**, which is the whole
trap: `11.1.0.164` tells you nothing about which week's ledger rules a binary
carries. w38 is the head of `cardano-node`'s `leios-prototype` branch and is
five days ahead of the `7e33674` pin our source documents cite; w36 is the
build the running chain was deployed from, and is what
[`musashi/musashi-relay.yaml`](../musashi/musashi-relay.yaml) now pins after a
w38 node stalled on a phase-2 validation disagreement (§ 2.7).

Everything below was checked on **both** binaries. The `dijkstra node`,
`dijkstra query`, and `dijkstra stake-pool` help output is byte-identical
between them; the one difference found is in § 2.3.

Being static, they are also useful *outside* the container: copy them out
(`podman cp musashi-relay-node:/usr/local/bin/cardano-cli .`) and they run on
any x86-64 Linux host.

To build the same CLI rather than copy it, `ouroboros-leios` exposes it as a
flake package — build from the **release tag**, whose `flake.lock` pins
`cardano-node-leios` to the same rev that week's image reports:

```shell
nix build github:input-output-hk/ouroboros-leios/prototype-2026w36#cardano-cli-static
./result/bin/cardano-cli --version     # 11.2.2.0 … git rev afa091b4af27
```

Build the **week you are running** — swap the tag for `prototype-2026w38` (rev
`648fc48b`) or whichever week the live config's `MinNodeVersion` names.

`cardano-cli-static` is defined for **x86_64-linux only**
([`nix/release.nix`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/nix/release.nix#L37));
on aarch64 Linux or Apple silicon build `#cardano-node-release` instead, a
tarball carrying `cardano-node`, `cardano-cli`, `tx-firehose`, and
`mempool-monitor`. Either needs the IOG binary cache to be in effect —
`https://cache.iog.io` with key
`hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=`, declared in the
flake's own `nixConfig` but honored only for a **trusted** Nix user — or it
will try to build GHC from source. The flake also needs
`allow-import-from-derivation`.

## 2. `cardano-cli`: the Leios-relevant surface

**Era structure first, because it is a trap.** `cardano-cli latest` is
**Conway**, not Dijkstra. Everything Leios lives under the explicit
`cardano-cli dijkstra ...` group, and the Conway forms of the same commands
silently lack the Leios options — `conway stake-pool registration-certificate`
has no BLS flag at all.

### 2.1 BLS (Leios voting) keys — `dijkstra node`

```
key-gen-BLS    Create a key pair for a node BLS operational key
key-hash-BLS   Print hash of a node's operational BLS key.
```

`cardano-cli dijkstra node key-gen-BLS --verification-key-file bls.vkey
--signing-key-file bls.skey` (text-envelope by default, `--key-output-bech32`
available). These two are additions to the standard `key-gen` / `key-gen-KES` /
`key-gen-VRF` / `issue-op-cert` set; the era-independent `cardano-cli node`
group does **not** have them.

The node side matches: `cardano-node run` accepts `--shelley-bls-key FILEPATH`
alongside `--shelley-kes-key`, `--shelley-vrf-key`,
`--shelley-operational-certificate`, and also
`--shelley-kes-agent-socket` and `--start-as-non-producing-node`.

### 2.2 Pool registration now *requires* a BLS key

In `dijkstra stake-pool registration-certificate`, `--bls-signing-key-file
FILEPATH` appears **unbracketed** in the usage — it is mandatory, unlike the
ledger's own `StrictMaybe BlsKey`, which permits a pool with no key (a *keyless*
seat). Note it takes the **signing** key, not the verification key: the
certificate carries a proof of possession, which only the secret key can
produce. Operationally that means the BLS secret is needed in two places — on
whatever machine builds the registration certificate, and on the block producer
that votes.

### 2.3 All nine Leios protocol parameters are proposable — on w38

`dijkstra governance action create-protocol-parameters-update` covers the
complete Leios set — **in the w38 build only**. The w36 CLI that matches the
running network has neither the flags nor, presumably, a ledger that would
accept them; its help output carries only the generic
`--max-ref-script-size-per-block` / `--max-ref-script-size-per-tx`. Whether a
proposal built by a w38 CLI is accepted by a w36 network is **untested**, and
unlikely. On w38:

```
--leios-announcement-period-length MILLISECONDS
--leios-vote-period-length MILLISECONDS
--leios-diffusion-period-length MILLISECONDS
--leios-committee-size WORD
--leios-quorum-stake-threshold RATIONAL
--max-endorser-block-references-size WORD
--max-endorser-block-txs-size WORD
--max-endorser-block-execution-units
--max-ref-script-size-per-endorser-block WORD
```

Two consequences. First, these are the same nine parameters
[the parameter note](./leios-node-protocol-parameters.md) derives from the
ledger, so the CLI surface and the ledger's `PParams` agree — there is no
parameter reachable only by editing genesis. Second, changing any of them on a
network is a **governance action needing SPO approval**: upstream's
[`propose-pparam-update.sh`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/demo/dozen-devnet/propose-pparam-update.sh)
records that every Leios parameter is declared `PPGroups 'NetworkGroup
'SecurityGroup`, so it needs `poolVotingThresholds.ppSecurityGroup` (0.51) on
top of the DRep thresholds — "DReps alone leave it sitting in the queue until
it expires."

### 2.4 Queries — and the gap

`dijkstra query` has 29 subcommands and **not one of them is Leios-specific**:

```
committee-state constitution drep-stake-distribution drep-state era-history
future-pparams gov-state kes-period-info leadership-schedule
ledger-peer-snapshot ledger-state pool-params pool-state proposals
protocol-parameters protocol-state ratify-state ref-script-size slot-number
spo-stake-distribution stake-address-info stake-distribution
stake-pool-default-vote stake-pools stake-snapshot tip treasury tx-mempool utxo
```

`committee-state` is the *constitutional* committee, not the Leios voting
committee. There is no query for committee seating, EB state, votes, or
certificates, and a source scan for a `GetLeios…`-shaped local-state query at
consensus `b56977b` finds none — so this is a missing surface, not a missing
CLI wrapper. Leios state is observable only through traces, Prometheus, and the
node's own SQLite store (§ 3).

Two that do carry Leios information indirectly:

- `dijkstra query pool-state` / `stake-snapshot` — the ledger's
  `StakePoolState` carries `spsBlsKey`, so a registered BLS key should be
  visible here. **Unverified** — worth running against your relay and
  recording.
- `dijkstra query tx-mempool info` — capacity and sizes, the same
  `MsgGetSizes` the mempool observer uses. Also `next-tx` and `tx-exists`.

### 2.5 `ping` — handshake and tip without a chain

Works against a host or a socket, and needs no synced node. Against the
musashi bootstrap relay today:

```
$ cardano-cli ping -h leios-node.play.dev.cardano.org -p 3001 -m 164 -Q -c 1
3.131.54.190:3001,   network rtt: 0.031s     handshake rtt: 0.030s
3.131.54.190:3001,   NodeToNodeV_14 … NodeToNodeV_15 … NodeToNodeV_16
  NodeToNodeVersionData {networkMagic = NetworkMagic 164,
    diffusionMode = InitiatorAndResponderDiffusionMode,
    peerSharing = PeerSharingEnabled, query = False,
    perasSupport = PerasUnsupported}
```

So the testnet negotiates N2N **V_14–V_16**, and the version data carries a
*Peras* flag but nothing about Leios — the Leios mini-protocols are gated by
the version number itself, not by a capability flag ❓ (inferred from the
absence, not read from the negotiation code). `-t/--tip`, `-j/--json` and
`-Q/--query-versions` are the useful modes; `-u/--unixsock` points it at your
own node's socket.

One wart: with no IPv6 route it tries all AAAA addresses first and prints eight
`Network unreachable` warnings before succeeding over IPv4. Cosmetic, but it
looks like a failure when it is not.

### 2.6 `debug check-node-configuration` — and what it cannot tell you

```
$ cardano-cli debug check-node-configuration --node-configuration-file config.json
Checking byron genesis file: ./byron-genesis.json
Successfully checked node configuration file: config.json
```

Tested against a deliberately corrupted copy, it does catch a bad hash:

```
Error: Wrong genesis hash for ./shelley-genesis.json in config.json: when
computing the hash, got: 1944510a…, but the node configuration files states
that this hash is expected: 000000…
```

**It checks internal consistency only.** The stale baked config that
[`musashi/cheatsheet.md`](../musashi/cheatsheet.md) warns about is perfectly
self-consistent, so this command passes it. The wrong-network check remains
what `pin-config.sh` prints: `systemStart` and `MinNodeVersion`.

`debug log-epoch-state` (streams epoch state as line-delimited JSON to a file,
runs until killed) and `debug transaction` complete the group.

### 2.7 Detecting version skew, with the tools above

Worked example, 2026-09-21: a relay on the **w38** image synced for days and
then stopped at slot 854,400, logging `ChainSync.Client.Exception` with
`InvalidBlock` **34 times in 54 seconds** — always the same block
(`19067ce95067…`), the same transaction (`ca42eb12…`), the same PlutusV4 script
(`603320d0…`), and `ValidationTagMismatch Phase2Valid (FailedUnexpectedly …)`:
the producer marked the transaction phase-2 valid, our node's evaluation said
the script failed. Each rejection dropped that peer
(`Net.Mux.Remote.ExceptionExit` → `DemoteAsynchronous` → `PeerCold`), the
governor promoted another, and the cycle repeated. A single
`BlockchainTime.CurrentSlotUnknown` marks the chain falling behind its own era
horizon. No component was broken; the node was simply alone in its verdict.

The three commands that settle it:

```shell
# 1. Is the network past the block we reject?  (all five relays agreed: yes, by ~4.8 days)
cardano-cli ping -h leios-node.play.dev.cardano.org -p 3001 -m 164 -t -c 1 -j

# 2. What does the network say it wants?
jq -r .MinNodeVersion config/config.json          # 11.1.0.164-prototype-2026w36

# 3. What moved between that week and the one we run?
git -C ouroboros-leios show prototype-2026w36:flake.lock | jq -r '.nodes["cardano-node-leios"].locked.rev'
git -C ouroboros-leios show prototype-2026w38:flake.lock | jq -r '.nodes["cardano-node-leios"].locked.rev'
curl -s https://raw.githubusercontent.com/IntersectMBO/cardano-node/<rev>/cabal.project   # diff the two
```

That diff is where the cause showed: between w36 (`afa091b4`) and w38
(`648fc48b`) the node's `cabal.project` moved **cardano-ledger** from
`1587f21a` to `daa38fec`, along with consensus, api, and cli. A prototype
branch changes ledger rules without a hard fork, so a *newer* node can reject
a chain the network built. **`MinNodeVersion` is a floor and `--version` is
not a discriminator** — both builds report `11.1.0.164`. Match the image week
to the network, and read the rev.

## 3. Observing Leios on a node you are running

### 3.1 Traces and metrics

Covered in [the cheatsheet](../musashi/cheatsheet.md): the pinned config sets
the four Leios tracers to `Debug` with no rate limit, and Prometheus is on
`:12798` once rebound off loopback. The trace namespaces are the primary
Leios observation surface, given § 2.4.

### 3.2 The LeiosDb is a SQLite file you can query

This is the most under-advertised tool on the node. The Leios store is plain
SQLite in **WAL mode**, so a reader can query it while the node runs (open it
read-only, or copy it first, and expect the volatile partition to be swept
underneath you). Schema, read from
[`LeiosDemoDb/SQLite.hs:1552`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosDemoDb/SQLite.hs#L1552):

```sql
ebs   (ebSlot, ebHashBytes, ebBytesSize, missingTxCount, status)   -- PK (ebSlot, ebHashBytes)
ebTxs (ebHashBytes, txOffset, txHashBytes, txBytesSize)            -- PK (ebHashBytes, txOffset)
txs   (txHashBytes)                 ebsMissingTxs (…)   gcTxCandidates (txHashBytes)
```

`status`: 0 volatile, 1 certified/pinned awaiting copy, 2 copied to the
immutable partition, 3 marked for GC. `missingTxCount`: NULL = body not
downloaded, > 0 = txs still missing, 0 = just completed, < 0 = completed and
notified.

Which means **EB overlap — the kleioscan "tx duplication" metric — is a local
SQL query**, on your own relay, with no instrumentation work:

```sql
-- how many EBs each transaction appears in
SELECT n_ebs, COUNT(*) AS txs FROM (
  SELECT txHashBytes, COUNT(DISTINCT ebHashBytes) AS n_ebs FROM ebTxs GROUP BY txHashBytes
) GROUP BY n_ebs ORDER BY n_ebs;

-- EB lifecycle census, and bodies still incomplete
SELECT status, COUNT(*), SUM(ebBytesSize) FROM ebs GROUP BY status;
SELECT COUNT(*) FROM ebs WHERE missingTxCount > 0;
```

Caveats worth stating in any result: this is **one node's view**, the volatile
partition is garbage-collected (so history is truncated, not complete), and
`ebs` holds EBs whose **body this node actually fetched** — not EBs it was
merely told about. `leiosDbInsertEbPoint` has exactly one production call site,
on body acquisition (the same line that emits the misleadingly-named
`BlockPointMissing` warning), so the announcement path contributes nothing to
this table. The sample is therefore diffusion- *and* fetch-dependent. Note also what is **absent**: there are no vote or certificate tables.
Vote state lives only in memory (`LeiosVoteState`, with a standing GC FIXME),
so votes and quorum formation are trace-only.

The file name depends on the config: the live musashi `config.json` says
`LeiosDbConfig {"Backend": "SQLite", "Filepath": "leios.db"}` (single file),
while the newer consensus code and upstream's committed snapshot use separate
`VolatileFilepath` / `ImmutableFilepath`. Check `ls data/` on your node.

## 4. Load generation and mempool observation

Two tools ship in the release tarball next to the node and CLI, both built from
the same branch, both Leios-motivated, and both directly aimed at **mempool
fragmentation** — the subject of [ARC-operating-model #83](https://github.com/input-output-hk/ARC-operating-model/issues/83).

**`tx-firehose`** ([README](https://github.com/IntersectMBO/cardano-node/blob/648fc48b045148a3b2acc5f3b04b039d50375bfc/bench/tx-firehose/README.md))
— a push-based load generator driving **one** node over the N2C socket: it
queries the UTxO at an address derived from `--signing-key-file`, then submits
self-payments in a tight loop via `LocalTxSubmission`, recycling outputs on
every accept. Contrast `tx-generator`, which reacts to N2N pulls. Shape is
controlled by `--inputs-per-tx` / `--outputs-per-tx` (default 1-in/1-out), rate
by `--tps`.

Its distinguishing feature for fragmentation work is `--color`: a three-byte RGB
tag in **metadata label 1022**, so every transaction is attributable to the
generator that made it, in the mempool and in the logs. `--color auto` derives
a hue from the signing key; upstream's own advice is to assign explicit colors
for a run whose point is telling generators apart. Cost to know: metadata adds
roughly 45 bytes (~+20% on a minimal 228-byte tx), so colored runs are **not
byte-comparable** with uncolored baselines. Output is one JSON line per event
on stderr in the node's trace schema, under `TxFirehose.*` namespaces.

**`mempool-monitor`** ([README](https://github.com/IntersectMBO/cardano-node/blob/648fc48b045148a3b2acc5f3b04b039d50375bfc/bench/mempool-monitor/README.md))
— watches **one** node's mempool over `LocalTxMonitor` and reports which colors
it holds, with depth, byte capacity, per-color shares, and `--tsv` output for
later analysis. "One instance per node is the point. Mempool fragmentation is a
statement about how pools *differ*, so an aggregate view hides exactly the thing
under test."

Three caveats upstream states, all of which matter for how we would use it:

1. **The observer is not free** — `MsgNextTx` is one round trip per transaction
   and returns the whole transaction, so a 27,000-tx mempool means 27,000 round
   trips and ~17 MB per snapshot (hence the generous default `--interval 10`).
   Treat "monitor attached" as a condition to measure, held constant across arms.
2. **The capacity bar is bytes, not fullness** — `MsgGetSizes` exposes only the
   byte projection of a multi-dimensional capacity, and "the mempool's own
   measure additionally carries a validation-time dimension that neither
   `GetSizes` nor `GetMeasures` exposes. On the Leios prototype that time budget
   is what binds first" — so a mempool that has stopped accepting can show the
   bar at a fraction of full. This is a sharper statement of the same
   dimensionality problem recorded in
   [the metrics mapping](./leios-mempool-metrics-mapping.md).
3. **`drained` is a check, not decoration** — it must agree with the `txs`
   figure from `MsgGetSizes` for the same snapshot.

## 5. Local networks — the place to rehearse block production

`ouroboros-leios/demo/` carries three ready-made scenarios, all using the same
patched nodes and x-ray observability:

- **`proto-devnet`** — a Leios-enabled devnet from prototype nodes. Shares
  network magic **164** with musashi.
- **`dozen-devnet`** — twelve nodes as **three block producers × three private
  relays**, the nine relays fully meshed, for throughput experiments at a
  realistic peer degree. Its rationale is worth reading: per-peer tx-submission
  credit windows make upstream peer count a first-order term, which three fully
  connected nodes cannot show. Ships `mempool-panes.sh` (mempool-monitor per
  node) and `propose-pparam-update.sh` (the full propose → DRep vote → SPO vote
  → epoch-boundary cycle).
- **`burst`** — a burst scenario reproducing Leios interference with Praos.

For the SPO plan this is the rehearsal ground: a local devnet gives block
production, BLS key registration, and Leios parameter changes **without needing
musashi stake**, and `dozen-devnet` already holds the pool cold keys that make
a parameter change ratifiable.

**X-ray** (`demo/extras/x-ray`, `nix run …#x-ray`) is the Grafana + Prometheus +
Loki + Alloy stack the demos and upstream's `testnet/run.sh` use. Our pod
deliberately omits it and exposes `:12798` instead; point x-ray at that port if
you want the dashboards.

## 6. Everything else, by where it sits

| Tool | Where | What it is for |
|---|---|---|
| `cardano-tracer` | `cardano-node` repo | Receiver for the node's `Forwarder` trace backend, which the pinned config enables. The route to structured trace capture without scraping stdout. |
| `locli`, `tx-generator`, `cardano-topology`, `cardano-profile`, `cardano-timeseries-io` | `cardano-node/bench` | The benchmarking cluster toolchain. Heavier than a single relay needs, but `locli` is the established trace-analysis path. |
| `db-analyser`, `db-synthesizer`, `db-truncater`, `db-immutaliser`, `immdb-server`, `snapshot-converter` | `ouroboros-consensus` | Offline ChainDB tools: replay and time a chain, synthesize one, truncate to a point, serve an immutable DB to another node. `db-analyser` is how you re-validate a captured musashi chain offline. |
| `leios-schedule-gen` | `ouroboros-consensus` | Takes `<db.db> <manifest.json> <schedule.json>` and generates a synthetic LeiosDb plus fetch schedule — a fixture generator for the fetch logic, not a node-side tool (read from its argument handling only). |
| `trace-translator` | `ouroboros-leios/scripts` | Converts node logs into the Leios **trace-verifier** format; accepts both envelope-wrapped node logs and bare traces. **Recognizes Praos events plus Linear Leios EB events only; everything else is ignored** — so votes and certificates do not survive the translation today. |
| `leios-trace-verifier`, `leios-trace-hs` | `ouroboros-leios` | The Agda-backed conformance checker the translator feeds, and its Haskell trace library. The one path from a live node's log to a formal conformance statement. |
| `sim-rs`, `net-rs`, `simulation`, `delta_q`, `topology-checker`, `topology-viewer`, `ui` | `ouroboros-leios` | Simulators, network models, ΔQ, topology tools, and the visualizer — see [the catalog](./leios-simulation-model-catalog.md), which covers these in depth. |
| `crypto-benchmarks.rs` | `ouroboros-leios` | Vote/certificate signing and verification benchmarks, with its own demo. |
| `antithesis` | `ouroboros-leios` | Deterministic fault-injection scenario images (built on the same base image as our relay). |
| `cardano-db-sync` | branch **`leios-w36`** (updated 2026-09-17; also `leios-cert-signers`, `leios-w34-doomsday-mode`) | SQL access to the chain, including Leios structures. The route to chain-level questions our single relay cannot answer. Note the weekly-branch convention: pick the branch matching the network's week. |
| [kleioscan](https://kleioscan.com/#/musashi/leios) | external | The hosted musashi explorer, including the mempool-fragmentation panel whose metric definitions are mapped in [the metrics note](./leios-mempool-metrics-mapping.md). |
| `leios-peernet`, `leios-adversarial-tools` (Piranha) | `input-output-hk`, **private** | Network emulation and adversarial tooling; access not yet obtained. |

## 7. Gaps

Stated plainly, because they bound what any experiment on a single relay can claim:

1. **No local-state query for Leios.** No committee seating, EB, vote, or
   certificate query exists at either the CLI or (as far as a source scan
   shows) the protocol level. Everything Leios is traces, metrics, or the
   SQLite store.
2. **Votes and certificates are the least observable part of the system** —
   in-memory only on the node, absent from the LeiosDb, and dropped by the
   trace translator. Any vote-level study starts by adding observability.
3. **`check-node-configuration` cannot detect the wrong network**, only an
   inconsistent one.
4. **Mempool capacity is reported in one dimension** while the binding
   constraint on the prototype is a validation-time dimension no local query
   exposes.
5. **Nothing in a binary tells you which network it belongs to.** Both weekly
   builds report `11.1.0.164`; `MinNodeVersion` is a floor; and a phase-2
   disagreement surfaces only as a stalled chain days into a sync (§ 2.7).
   On a prototype branch whose ledger moves weekly without a hard fork, the
   image week is a load-bearing parameter of any experiment.
6. **The Leios parameter-update flags exist only on the newer build**, so
   parameter-variation experiments on a live testnet wait on the network
   rolling to that week (a local devnet does not — § 5).

## 8. Try these against your relay

```shell
# what the node thinks it is, and where it is
podman exec musashi-relay-node cardano-cli query tip --testnet-magic 164
podman exec musashi-relay-node cardano-cli dijkstra query protocol-parameters --testnet-magic 164 \
  | jq '{leiosAnnouncementPeriodLength, leiosVotePeriodLength, leiosDiffusionPeriodLength,
         leiosCommitteeSize, leiosQuorumStakeThreshold}'

# mempool, from the node's own mouth
podman exec musashi-relay-node cardano-cli dijkstra query tx-mempool info --testnet-magic 164

# is a registered BLS key visible in pool state?  (unverified — worth recording)
podman exec musashi-relay-node cardano-cli dijkstra query pool-state --all-stake-pools --testnet-magic 164 | head -40

# handshake and tip without touching the chain DB
podman exec musashi-relay-node cardano-cli ping -u /data/node.socket -m 164 -c 1 -t

# EB overlap on this node
sqlite3 -readonly data/leios.db 'SELECT n,COUNT(*) FROM (SELECT COUNT(DISTINCT ebHashBytes) n FROM ebTxs GROUP BY txHashBytes) GROUP BY n ORDER BY n;'
```

## Sources

- The images' own binaries, extracted from `ghcr.io/input-output-hk/ouroboros-leios/cardano-node-testnet` and executed on 2026-09-21. `prototype-2026w38` (digest `sha256:f515269771b9…`, built 2026-09-20): both binaries at [`648fc48b`](https://github.com/IntersectMBO/cardano-node/commit/648fc48b045148a3b2acc5f3b04b039d50375bfc), head of `leios-prototype`. `prototype-2026w36` (digest `sha256:0df972de2193…`, built 2026-09-07, the day the chain started): both at [`afa091b4`](https://github.com/IntersectMBO/cardano-node/commit/afa091b4af2795d1d9c46e59145ed16127760f7b). Component revs from each release tag's `flake.lock` and the node's `cabal.project` at each rev.
- The stall analysed in § 2.7: `musashi/musashi-relay-node.log`, 1,000 lines covering 2026-09-21T16:25:29Z–16:26:26Z, and a `cardano-cli ping --tip` against all five bootstrap relays at 16:31Z (network tip slot 1,268,908, block 57,111).
- [`tx-firehose/README.md`](https://github.com/IntersectMBO/cardano-node/blob/648fc48b045148a3b2acc5f3b04b039d50375bfc/bench/tx-firehose/README.md) and [`mempool-monitor/README.md`](https://github.com/IntersectMBO/cardano-node/blob/648fc48b045148a3b2acc5f3b04b039d50375bfc/bench/mempool-monitor/README.md), `cardano-node@leios-prototype`.
- [`ouroboros-leios` @ `9fa5a95`](https://github.com/input-output-hk/ouroboros-leios/tree/9fa5a956db7a7860065b68e221c6f7ce647242d5) (2026-09-21, release 2026w38): [`nix/release.nix`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/nix/release.nix), [`demo/README.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/demo/README.md), [`demo/dozen-devnet/README.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/demo/dozen-devnet/README.md), [`scripts/trace-translator/README.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/scripts/trace-translator/README.md).
- LeiosDb schema and WAL mode: [`LeiosDemoDb/SQLite.hs`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosDemoDb/SQLite.hs#L1552) @ `b56977b`; consensus executables from `ouroboros-consensus.cabal` at the same pin.
- Ledger types behind the BLS flags: [`StakePool.hs`](https://github.com/IntersectMBO/cardano-ledger/blob/1587f21a7d1306dc590c2749a5c66232ef66aad0/libs/cardano-ledger-core/src/Cardano/Ledger/State/StakePool.hs#L460-L536) @ `1587f21`.
- `cardano-db-sync` branch listing via the GitHub API, 2026-09-21.
