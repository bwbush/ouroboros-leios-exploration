# Turning the relay into a single-node block producer

**Provenance:** ⏳🤖 LLM-generated, pending human review · **Layer:** deployed network (musashi) + implementation · **Verified:** 2026-09-21

Deliberately **one node that both relays and produces** — no relay/producer
split. That is not how a mainnet pool is run, and § 6 says what you are giving
up; on a testnet whose point is observation it is a reasonable trade.

> [!IMPORTANT]
> **Read upstream's guide alongside this one.** The Leios project publishes a
> full SPO path — [install and run a node](https://leios.cardano-scaling.org/docs/testnet/getting-started/),
> [register a stake pool](https://leios.cardano-scaling.org/docs/testnet/register-stake-pool/),
> and the [SPO Rewards Program](https://leios.cardano-scaling.org/docs/testnet/rewards-program/).
> That is the canonical procedure and it is self-service; this document adds the
> single-node shape, the pod spec, and the numbers read from the network's own
> genesis. Questions go to the **[Musashi Dōjō Discord](https://discord.gg/AyUXD9VHn)**.
>
> **Funding is a faucet, not a request.** The
> [faucet](https://faucet.leios.play.dev.cardano.org/basic-faucet) sends a fixed
> **10,000 test ada** automatically — more than enough for the **500 ₳ pool
> deposit**, the **2 ₳ stake-key deposit**, a pledge, and fees — and its
> **delegate** widget will delegate **~1,000,000 test ada** to your pool id,
> which is what gives it stake worth being scheduled on. Deposit and cost
> figures below come from the genesis `protocolParams`; confirm the current
> values with `cardano-cli dijkstra query protocol-parameters`, since they are
> governable.
>
> **The SPO Rewards Program does not apply to this pool.** It exists — an
> application form, an Application Code carried in the registration
> transaction's metadata, rewards paid to a mainnet address — but it is aimed at
> external operators, and an IOG-run pool claiming it would not be appropriate.
> So no metadata is needed in the registration transaction, and the scripts here
> do not add any. Worth knowing for a different reason: the program's stated
> rationale is that the chain records outcomes while *timing* lives in the nodes,
> which is the same case [the instrumentation note](../artifacts/leios-tx-flow-instrumentation.md)
> makes for collecting logs.

Everything here uses the **w36** CLI from the image you are running
(`podman cp musashi-relay-node:/usr/local/bin/cardano-cli .`), whose
`dijkstra` command group carries the Leios additions.

```shell
export CARDANO_NODE_SOCKET_PATH=$PWD/data/node.socket
export CARDANO_NODE_NETWORK_ID=164     # or pass --testnet-magic 164
```

## 0. Two host prerequisites

- **A public IP and an open port**, so peers can reach you — and, in the
  Rewards Program, so the operators' `cardano-ping` probe can. Your single node
  *is* the relay you register, so this is not optional here.
- **An accurate clock.** A producer that drifts forges into the wrong slot.
  `sudo apt install -y chrony && sudo systemctl enable --now chrony`, or your
  platform's NTP equivalent.

## Scripts

Two scripts do the mechanical parts. Both find `cardano-cli` in
`$CARDANO_CLI`, then `./build` (searched recursively, for a local build), then
`PATH`; both read the network magic and KES period length from the pinned
`config/`, so nothing is hard-coded.

```shell
./make-spo-keys.sh                 # all five key pairs + addresses + op-cert
RELAY_HOST=my.host ./register-pool.sh certs    # the three certificates, offline
RELAY_HOST=my.host ./register-pool.sh submit   # build, sign, and submit
```

[`make-spo-keys.sh`](./make-spo-keys.sh) is idempotent in the only way that
matters: it **refuses to overwrite existing credentials**, because a regenerated
cold key is a different pool. Steps are separable — `keys`, `opcert` (also the
KES-rotation step), `show`. It issues the op-cert only if the node socket is
present, and tells you to come back for it otherwise.

[`register-pool.sh`](./register-pool.sh) builds all three certificates, picks
the largest UTxO at the payment address, builds and signs the transaction, and
**submits only when you say `submit`**. It requires `RELAY_HOST` or
`RELAY_IPV4` rather than defaulting them, refuses a `POOL_COST` below the
network's `minPoolCost`, and refuses to proceed when the chosen UTxO cannot
cover the deposits.

The sections below explain what those scripts do, for when you want to do it by
hand or check their work.

## 1. Keys

Five key pairs, one of which is new in Leios. They all live in `keys/` next to
the pod, gitignored.

> [!NOTE]
> **Key handling here is deliberately unceremonious.** These credentials exist
> for one ephemeral testnet, are never reused on mainnet, preprod, or preview,
> and are regenerated whenever the network is respun — so there is no cold-key
> ceremony, no air-gapped machine, and no backup discipline in this procedure.
> Two mechanical precautions survive anyway, neither about secrecy: the node
> **refuses to start** if the VRF signing key is group- or world-readable, and
> the script refuses to overwrite an existing key set because a new cold key
> means re-registering the pool and re-requesting the faucet delegation. Do not
> copy this section's habits to a pool that matters.

```shell
mkdir -p keys && cd keys

# Cold (operator) key + its op-cert issue counter — the pool's identity
cardano-cli dijkstra node key-gen \
  --cold-verification-key-file cold.vkey \
  --cold-signing-key-file cold.skey \
  --operational-certificate-issue-counter-file cold.counter

# VRF — leader election
cardano-cli dijkstra node key-gen-VRF --verification-key-file vrf.vkey --signing-key-file vrf.skey

# KES — block signing, rotated periodically (§ 5)
cardano-cli dijkstra node key-gen-KES --verification-key-file kes.vkey --signing-key-file kes.skey

# BLS — Leios vote signing.  This one does not exist outside the Dijkstra era.
cardano-cli dijkstra node key-gen-BLS --verification-key-file bls.vkey --signing-key-file bls.skey
```

The operational certificate binds the current KES key to the cold key for a
window of KES periods. Compute the period from the tip:

```shell
cardano-cli dijkstra query tip --testnet-magic 164        # take .slot
# musashi: slotsPerKESPeriod = 129600  =>  period = slot / 129600
cardano-cli dijkstra node issue-op-cert \
  --kes-verification-key-file kes.vkey \
  --cold-signing-key-file cold.skey \
  --operational-certificate-issue-counter-file cold.counter \
  --kes-period <slot / 129600> \
  --out-file opcert.cert
```

You also need an ordinary payment key to pay for the registration, and a stake
key to delegate to the pool:

```shell
cardano-cli address key-gen --verification-key-file pay.vkey --signing-key-file pay.skey
cardano-cli dijkstra stake-address key-gen --verification-key-file stake.vkey --signing-key-file stake.skey
cardano-cli address build --payment-verification-key-file pay.vkey \
  --stake-verification-key-file stake.vkey --testnet-magic 164 --out-file pay.addr
```

Fund `pay.addr` from the [faucet](https://faucet.leios.play.dev.cardano.org/basic-faucet), then check it arrived: `cardano-cli dijkstra query utxo
--address $(cat pay.addr) --testnet-magic 164`.

### 1.1 Can the funding go to an address you already use?

Yes — a Cardano address encodes only *testnet vs mainnet*, not which testnet.
Verified by building one key's address at four magics:

```
magic 1    addr_test1qru6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…
magic 2    addr_test1qru6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…
magic 164  addr_test1qru6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…
mainnet    addr1q8u6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…      <- only this differs
```

Identical across every testnet magic, stake addresses too. So an address you
use on preprod or preview *is* a valid musashi address, character for
character. Three consequences:

- **Funds are chain-local; the address is not.** Money sent to it on musashi
  exists only on musashi — your preprod wallet will never show it, and
  `query utxo` needs a musashi node socket. The flip side is the footgun: a
  wrong-network send cannot bounce, because the address is valid everywhere.
  Name the network explicitly when you ask for funds.
- **Stake registration is chain-local too.** A stake key already registered
  elsewhere is unregistered here and still owes musashi's 2 ₳ `keyDeposit`.
- **What actually matters is holding the signing key in CLI form.** A wallet
  address gives you no `.skey`. If the key came from a mnemonic:
  `cardano-cli key derive-from-mnemonic --payment-key-with-number 0
  --account-number 0 --mnemonic-from-interactive-prompt --signing-key-file
  pay.skey` yields an *extended* key; flatten its verification key with
  `cardano-cli key non-extended-key` if a command refuses the extended form.

The tidy arrangement is to receive at the address you already use and then send
onward to dedicated pool keys, so the cold, reward, and owner keys are this
pool's and nothing else's. Reuse is not a replay risk — a signed transaction
names inputs that exist on one chain only — but it does mean one compromise
reaches both chains, and it entangles the pool's reward and owner accounts with
whatever else that key does.

## 2. Certificates

### 2.1 The pool registration certificate — where the BLS key is registered

There is no separate "register my Leios key" transaction: the BLS public key
and its proof of possession ride on the pool certificate, and the CLI makes it
**mandatory** (`--bls-signing-key-file` is unbracketed in the usage — see
[the tooling note § 2.2](../artifacts/leios-node-tooling.md)). Note it takes
the **signing** key, because only the secret can produce the possession proof.

```shell
cardano-cli dijkstra stake-pool registration-certificate \
  --cold-verification-key-file cold.vkey \
  --vrf-verification-key-file vrf.vkey \
  --bls-signing-key-file bls.skey \
  --pool-pledge 0 \
  --pool-cost 170000000 \
  --pool-margin 0 \
  --pool-reward-account-verification-key-file stake.vkey \
  --pool-owner-stake-verification-key-file stake.vkey \
  --single-host-pool-relay <your.host.or.dns> --pool-relay-port 3010 \
  --testnet-magic 164 \
  --out-file pool-registration.cert
```

Real musashi constraints: `--pool-cost` must be **≥ 170000000** (minPoolCost =
170 ₳), the deposit charged by the transaction is **500 ₳** (poolDeposit), and
`--pool-pledge 0` is allowed — an unmet pledge costs rewards, not the ability
to forge. The relay group is *optional* in the usage, but declare yourself:
it is how other nodes learn to dial you, and EB diffusion is the thing you are
here to observe. Use `--pool-relay-ipv4`/`--pool-relay-port` if you have no DNS
name.

### 2.2 Stake registration and delegation

Committee seating is **top `leiosCommitteeSize` pools by stake** (musashi:
900), so a pool with zero active stake is seated nowhere and votes never. Give
it stake:

```shell
cardano-cli dijkstra stake-address registration-certificate \
  --stake-verification-key-file stake.vkey --key-reg-deposit-amt 2000000 \
  --out-file stake-registration.cert
cardano-cli dijkstra stake-address stake-delegation-certificate \
  --stake-verification-key-file stake.vkey --cold-verification-key-file cold.vkey \
  --out-file delegation.cert
```

(`registration-and-delegation-certificate` does both in one, if you prefer.)

Self-delegation of a 10,000-ada faucet payment is *far* too little stake to be
scheduled. After registration, give the faucet's **delegate** widget your
bech32 pool id and it delegates ~1,000,000 test ada:

```shell
cardano-cli dijkstra stake-pool id --output-bech32 --cold-verification-key-file keys/cold.vkey
```

### 2.3 Submit

```shell
cardano-cli dijkstra transaction build \
  --tx-in <TxHash#TxIx> --change-address $(cat pay.addr) \
  --certificate-file stake-registration.cert \
  --certificate-file pool-registration.cert \
  --certificate-file delegation.cert \
  --witness-override 3 --testnet-magic 164 --out-file tx.raw
cardano-cli dijkstra transaction sign --tx-body-file tx.raw \
  --signing-key-file pay.skey --signing-key-file stake.skey --signing-key-file cold.skey \
  --testnet-magic 164 --out-file tx.signed
cardano-cli dijkstra transaction submit --tx-file tx.signed --testnet-magic 164
```

Three witnesses: the payment key pays, the stake key authorizes its own
registration and delegation, the cold key authorizes the pool registration.

## 3. The pod

`/app/run-node.sh` takes no key flags, so a producer must replace the command.
[`musashi-bp.yaml`](./musashi-bp.yaml) is the relay spec plus a `keys` volume
and an explicit `cardano-node run`. Switch over:

```shell
podman kube down musashi-relay.yaml
podman kube play musashi-bp.yaml          # same ports, same ./config and ./data
```

It keeps the chain database, so there is no resync. The two specs pin the same
image digest — **bump both together** (see the cheatsheet's version-skew
warning).

One permission requirement is functional, not hygienic: `cardano-node` checks
the **VRF** signing key at startup and refuses to run if it grants any group or
other permission
([`checkVRFFilePermissions`](https://github.com/IntersectMBO/cardano-node/blob/afa091b4af2795d1d9c46e59145ed16127760f7b/cardano-node/src/Cardano/Node/Run.hs#L871)).
`make-spo-keys.sh` already sets `600` on every signing key, so this is only a
thing to remember if you move files around by hand.

## 4. Confirm it took

```shell
# the pool is on chain
cardano-cli dijkstra query pool-state --stake-pool-id $(cardano-cli dijkstra stake-pool id \
  --cold-verification-key-file keys/cold.vkey) --testnet-magic 164
# does it show a registered BLS key?  (unverified — report what you see)
```

```shell
# the op-cert and KES window are sane
cardano-cli dijkstra query kes-period-info --op-cert-file keys/opcert.cert --testnet-magic 164
# are we scheduled to forge?  (needs the VRF signing key)
cardano-cli dijkstra query leadership-schedule --genesis config/shelley-genesis.json \
  --stake-pool-id <pool-id> --vrf-signing-key-file keys/vrf.skey --current --testnet-magic 164
```

In the log, the producer-only traces appear: `Forge.Loop.*`
(`StartLeadershipCheck` → `NodeIsLeader`/`NodeNotLeader` → `AdoptedBlock`), and
on the Leios side `Consensus.LeiosKernel.BlockForged`, `BlockAnnounced`,
`Voted` / `NotVoted`, `VoteScheduled`, `BlockCertified`. `NotVoted` is the one
to watch: it is how you learn you hold a seat but are failing a vote condition.

**Timing.** Stake registered in epoch *N* is active in *N+2*; musashi epochs
are 21,600 slots at 1 s, so **6 hours each** — expect eligibility 12–18 hours
after submission, and committee seating on the same snapshot boundary, since
[the committee is taken from the stake distribution](../artifacts/leios-node-protocol-parameters.md)
carrying whichever BLS keys are registered.

## 5. Two rotations, both about 93 days

- **KES**: `maxKESEvolutions = 62` × `slotsPerKESPeriod = 129600` s ⇒ ~93 days
  from the `--kes-period` you issued at. Then generate a new KES key, issue a
  new op-cert with the incremented counter, and restart. `query kes-period-info`
  tells you where you are.
- **The BLS key**: honored only while `epoch < registeredIn + maxKeyAge`, and
  `maxKeyAge` on musashi is **374 epochs** ≈ 93.5 days at 6-hour epochs. It
  expires by the same clock, but renewing it means **re-registering the pool**
  with a new BLS key, not reissuing a certificate. A seated pool whose key has
  aged out is *keyless*: it occupies a committee seat, cannot vote, and any
  certificate bit set on it invalidates that certificate.

## 6. What a single node costs you

Honest list, since you asked for this shape deliberately:

- **The producer is publicly dialable**, and the registration certificate
  advertises it. Nothing absorbs a flood aimed at your block production.
- **No hot-swap.** A relay pair lets you restart one node while the other keeps
  the pool connected; here every restart — config change, image bump, KES
  rotation — is downtime for forging.
- **Observation perturbs production.** The trace levels in
  [the instrumentation note](../artifacts/leios-tx-flow-instrumentation.md) are
  cheap on a relay; on a producer, heavy tracing competes with the forge loop,
  and `TxSubmission.Remote.*` is the loudest family on the node.
- **Peer topology is doing double duty.** The pinned `topology.json` bootstraps
  from `leios-node.play.dev.cardano.org` and fans out via ledger peers, which is
  right for a relay. A producer normally has `localRoots` pointing at its own
  relays and nothing else.
- **One vantage point.** Anything about *differences* between nodes — mempool
  fragmentation, in particular — needs more than one node, which is what the
  local `dozen-devnet` is for.

None of these are reasons not to do it here; they are the reasons the standard
shape exists.

## Sources

- CLI shapes read from the **w36** `cardano-cli 11.2.2.0` (rev `afa091b4`) extracted from the running image, 2026-09-21: `dijkstra node key-gen{,-KES,-VRF,-BLS}`, `dijkstra node issue-op-cert`, `dijkstra stake-pool registration-certificate`, `dijkstra stake-address *`, `dijkstra transaction build/sign/submit`.
- Deposits, costs, and KES parameters from musashi's [`shelley-genesis.json`](https://book.play.dev.cardano.org/environments-pre/leios/shelley-genesis.json) (pinned 2026-09-21): `poolDeposit` 500000000, `keyDeposit` 2000000, `minPoolCost` 170000000, `slotsPerKESPeriod` 129600, `maxKESEvolutions` 62, `epochLength` 21600, `slotLength` 1, `activeSlotsCoeff` 0.05.
- Leios committee seating, `maxKeyAge`, and the keyless-seat rule: [the protocol-parameter note](../artifacts/leios-node-protocol-parameters.md) §§ 3–4, from cardano-ledger `1587f21` (the w36 pin).
- Upstream's own testnet documentation, `ouroboros-leios` @ `9fa5a95`: [`site/docs/testnet/getting-started.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/site/docs/testnet/getting-started.md), [`register-stake-pool.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/site/docs/testnet/register-stake-pool.md), [`rewards-program.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/site/docs/testnet/rewards-program.md) (rewards page last updated 2026-08-10) — source of the faucet amounts (10,000 ada payment, ~1,000,000 ada delegation), the Application-Code-in-metadata mechanism, the two-epoch snapshot wait, the `cardano-ping` relay probe, and the host prerequisites in § 0. All four links verified reachable 2026-09-21.
