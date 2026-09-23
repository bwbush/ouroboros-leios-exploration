# Turning the relay into a single-node block producer

**Provenance:** ⏳🤖 LLM-generated, pending human review · **Layer:** deployed network (musashi) + implementation · **Verified:** 2026-09-22

Deliberately **one node that both relays and produces** — no relay/producer split. That is not how a mainnet pool is run, and § 8 says what you are giving up; on a testnet whose point is observation it is a reasonable trade.

> [!IMPORTANT]
> **Read upstream's guide alongside this one.** The Leios project publishes a full stake pool operator (SPO) path — [install and run a node](https://leios.cardano-scaling.org/docs/testnet/getting-started/), [register a stake pool](https://leios.cardano-scaling.org/docs/testnet/register-stake-pool/), and the [SPO Rewards Program](https://leios.cardano-scaling.org/docs/testnet/rewards-program/). That is the canonical procedure and it is self-service; this document adds the single-node shape, the pod spec, and the numbers read from the network's own genesis. Questions go to the **[Musashi Dōjō Discord](https://discord.gg/AyUXD9VHn)**.
>
> **Funding is a faucet, not a request.** The [faucet](https://faucet.leios.play.dev.cardano.org/basic-faucet) sends a fixed **10,000 test ada** automatically — more than enough for the **500 ₳ pool deposit**, the **2 ₳ stake-key deposit**, a pledge, and fees — and its **delegate** widget will delegate **~1,000,000 test ada** to your pool id, which is what gives it stake worth being scheduled on. Deposit and cost figures below come from the genesis `protocolParams`; confirm the current values with `cardano-cli dijkstra query protocol-parameters`, since they are governable.
>
> **The SPO Rewards Program does not apply to this pool.** It exists — an application form, an Application Code carried in the registration transaction's metadata, rewards paid to a mainnet address — but it is aimed at external operators, and an IOG-run pool claiming it would not be appropriate. So no metadata is needed in the registration transaction, and the scripts here do not add any. Worth knowing for a different reason: the program's stated rationale is that the chain records outcomes while *timing* lives in the nodes, which is the same case [the instrumentation note](../artifacts/leios-tx-flow-instrumentation.md) makes for collecting logs.

Everything here uses the **w36** command-line interface (CLI) whose `dijkstra` command group carries the Leios additions. `nix develop` at the repository root provides it (plus `cardano-node`, `tx-firehose`, and `mempool-monitor`) from [`nix/cardano-node-leios.nix`](../nix/cardano-node-leios.nix); `podman cp musashi-bp-node:/usr/local/bin/cardano-cli .` is the fallback.

```shell
export CARDANO_NODE_SOCKET_PATH=/data/musashi/node.socket
export CARDANO_NODE_NETWORK_ID=164     # or pass --testnet-magic 164
```

The checked-in pod specifications mount the host directory `/data/musashi` at `/data` in the container. The scripts therefore use `/data/musashi/node.socket` on the host by default; set `DATA_DIR` or `SOCKET` only when deploying with a different host data directory.

## 0. This deployment

| | |
|---|---|
| **Public address** | `thelio.functionally.dev` → **161.97.228.154** (A record only, no AAAA; PTR `161-097-228-154.v4.mynextlight.net`, verified 2026-09-22) |
| **Inbound port** | TCP **3010**, forwarded on a pfSense wide area network (WAN) rule to the block producer on the local area network (LAN) |
| **Relay record** | register `--single-host-pool-relay thelio.functionally.dev --pool-relay-port 3010` — the Domain Name System (DNS) name, not the address, so a WAN-address change needs no re-registration |
| **Pool name / ticker** | **ΘΕΛΩ** / `THELO` — θέλω, "I wish / I will", after the host. The ticker is the Latin transliteration at exactly the 5-character limit, which sidesteps the `[A-Z0-9]` registry convention (§ 3.3) |
| **Metadata** | [`pool-metadata.json`](./pool-metadata.json), 191 bytes, hash `cb61d75ac00a5c372481fdb5117c03c12b08c1054b306bb20f03cc3498134677`, published on IPFS and served at `https://functionally.mypinata.cloud/ipfs/QmcyS1urh1df3Qw8nHY2wAX1e2V75s8ePdTFCUiGY9RyiM` (87 bytes, within the 128-byte limit). Verified 2026-09-22: the CLI fetches that URL, validates the schema, and reports "Hashes match!" |

> [!NOTE]
> **Settled 2026-09-22 from the pfSense rule** ("musashi at darter", WAN address TCP 3010 → 192.168.1.12:3010): the producer runs on **darter** at 192.168.1.12, and `thelio.functionally.dev` is the *WAN's* name, not the host's. The relay record therefore names the public name correctly, and `darter.functionally.dev` not resolving is expected.

> [!NOTE]
> **Registered on chain 2026-09-22, epoch 62.** `query pool-state` confirms pool `88610017a37cfcbf497127b1be43efd71376bd52f3bb8773b3dcf838` (`pool13pssq9ar0n7t7jt3y7cmusl06ufhd02j7wacwuanmnursyyr7qu`) with the relay `thelio.functionally.dev:3010`, the metadata hash and Pinata URL, cost 170000000, margin 0, pledge 0, deposit 500000000, one delegator (its own stake key), and **`spsBlsKey` present** — a 96-byte Boneh–Lynn–Shacham (BLS) `blsPubKey` and 48-byte `blsPossessionProof`, `bksRegisteredIn: 62`, so the Leios voting key is honored until epoch **436** (2026-12-25). The op-cert covers Key Evolving Signature (KES) periods **10–71** and expires at the start of period **72**, 2026-12-24 — the two ≈93-day clocks of § 6, landing within a day of each other as expected.

> [!NOTE]
> **Current activation state, 2026-09-22:** the faucet delegation was submitted in epoch 62 and the block-producing pod is deployed. Its delegated stake becomes active at the start of epoch **64**, 2026-09-23 00:00 UTC. Epoch 64 makes the pool eligible for Praos leadership and seats it in the Leios committee if it remains among the top 900 pools; it does not guarantee selection to produce a block.

## 1. Two host prerequisites

- **A public IP and exactly one open inbound port: TCP 3010**, so peers can reach you. Your single node *is* the relay you register, so this is not optional here, and the port must match the `--pool-relay-port` in the registration certificate. Nothing else needs to be reachable: the node socket is a Unix socket, and the Prometheus endpoint is bound to `127.0.0.1` in the pod specs on purpose — it is unauthenticated, so scrape it from the host or tunnel to it rather than opening 12798.
- **Behind Network Address Translation (NAT), three things have to agree**: the forward (WAN TCP 3010 → the host), the host's own firewall, and the relay record in the registration certificate, which must name the address the *outside* sees. Use a DNS name with `--single-host-pool-relay` if the WAN address is dynamic. Test from outside the network — many routers fail to hairpin a connection from the LAN to their own WAN address, so an inside test can fail while the forward is fine:  `cardano-cli ping -h <public name> -p 3010 -m 164 -c 1`. On pfSense, the per-rule **NAT reflection: Pure NAT** setting is only half of hairpinning; the companion global switch — **System → Advanced → Firewall & NAT → "Enable automatic outbound NAT for reflection"** — is what source-NATs the reflected traffic so replies return through the firewall instead of going straight back. Reaching your *own* host through the WAN address is reflection's hardest case, and a **DNS host override** mapping the public name to the LAN address avoids the mechanism entirely — worth doing regardless, since it also stops the node from dialing its own advertised address when ledger peers hand back its relay record.
- **Rootless podman rewrites inbound source addresses.** With the default `rootlesskit` port handler every inbound peer appears to come from one container-side address (typically `10.0.2.100`) in the connection-manager traces. Peering still works; it is the logs that mislead. Rootful bridge networking preserves the real source. Check with `podman info --format '{{.Host.Security.Rootless}}'`.
- **An accurate clock.** A producer that drifts forges into the wrong slot. `sudo apt install -y chrony && sudo systemctl enable --now chrony`, or your platform's Network Time Protocol (NTP) equivalent.

## Scripts

Two scripts do the mechanical parts. Both find `cardano-cli` in `$CARDANO_CLI`, then `./build` (searched recursively, for a local build), then `PATH` — so inside `nix develop` they need no configuration at all, the dev shell having provided the pinned binaries. Both read the network magic and Key Evolving Signature (KES) period length from the pinned `config/`, so nothing is hard-coded.

```shell
./make-spo-keys.sh                 # all five key pairs + addresses + op-cert
RELAY_HOST=my.host ./register-pool.sh certs    # the three certificates, offline
RELAY_HOST=my.host ./register-pool.sh submit   # build, sign, and submit
```

[`make-spo-keys.sh`](./make-spo-keys.sh) is idempotent in the only way that matters: it **refuses to overwrite existing credentials**, because a regenerated cold key is a different pool. Steps are separable: `keys` creates the initial credentials, `opcert` reissues a certificate against the existing KES key after a testnet respin, `rotate-kes` generates a fresh KES key and certificate while archiving the old set, and `show` reports the current material. Certificate issuance works with or without a running node (see § 2), so it can be completed before the producer's first start.

[`register-pool.sh`](./register-pool.sh) builds all three certificates, picks the largest unspent transaction output (UTxO) at the payment address, builds and signs the transaction, and **submits only when you say `submit`**. It requires `RELAY_HOST` or `RELAY_IPV4` rather than defaulting them, refuses a `POOL_COST` below the network's `minPoolCost`, and refuses to proceed when the chosen UTxO cannot cover the deposits.

The sections below explain what those scripts do, for when you want to do it by hand or check their work.

## 2. Keys

Five key pairs, one of which is new in Leios. They all live in `keys/` next to the pod, gitignored.

> [!NOTE]
> **Key handling here is deliberately unceremonious.** These credentials exist for one ephemeral testnet and are never reused on mainnet, preprod, or preview. They survive a respin of the same testnet deployment — so there is no cold-key ceremony, no air-gapped machine, and no backup discipline in this procedure. Two mechanical precautions survive anyway, neither about secrecy: the node **refuses to start** if the verifiable random function (VRF) signing key is group- or world-readable, and the script refuses to overwrite an existing key set because a new cold key means re-registering the pool and re-requesting the faucet delegation. Do not copy this section's habits to a pool that matters.
>
> The encrypted `keys.tar.asc` archive is an intentional, testnet-only tracked exception to the `keys/` ignore rule. Its decryption key and every plaintext credential must remain outside this repository. Do not reuse any credential from the archive on another network.

```shell
mkdir -p keys && cd keys

# Cold (operator) key + its op-cert issue counter — the pool's identity
cardano-cli dijkstra node key-gen \
  --cold-verification-key-file cold.vkey \
  --cold-signing-key-file cold.skey \
  --operational-certificate-issue-counter-file cold.counter

# Verifiable random function (VRF) — leader election
cardano-cli dijkstra node key-gen-VRF --verification-key-file vrf.vkey --signing-key-file vrf.skey

# Key Evolving Signature (KES) — block signing, rotated periodically (§ 6)
cardano-cli dijkstra node key-gen-KES --verification-key-file kes.vkey --signing-key-file kes.skey

# Boneh–Lynn–Shacham (BLS) — Leios vote signing. This one does not exist outside the Dijkstra era.
cardano-cli dijkstra node key-gen-BLS --verification-key-file bls.vkey --signing-key-file bls.skey
```

The operational certificate binds the current KES key to the cold key for a window of KES periods, and the period is the current slot divided by `slotsPerKESPeriod` (129,600 here). `make-spo-keys.sh opcert` derives it from the node when one is reachable and **from the wall clock otherwise** — which matters more than it sounds, because the producer will not start without the certificate, so a node-only path is a deadlock the first time. The clock is exact here: musashi runs one era at one second per slot from genesis (byron `startTime` equals shelley `systemStart`), so `slot = (now − systemStart) / slotLength`; checked against a live tip, 2026-09-21T16:28:28Z gives slot 1268908, which is what the network reported. By hand:

```shell
cardano-cli dijkstra query tip --testnet-magic 164        # take .slot, if a node is up
# or, with no node:  slot = $(( $(date -u +%s) - $(date -u -d 2026-09-07T00:00:00Z +%s) ))
# musashi: slotsPerKESPeriod = 129600  =>  period = slot / 129600
cardano-cli dijkstra node issue-op-cert \
  --kes-verification-key-file kes.vkey \
  --cold-signing-key-file cold.skey \
  --operational-certificate-issue-counter-file cold.counter \
  --kes-period <slot / 129600> \
  --out-file opcert.cert
```

You also need an ordinary payment key to pay for the registration, and a stake key to delegate to the pool:

```shell
cardano-cli address key-gen --verification-key-file pay.vkey --signing-key-file pay.skey
cardano-cli dijkstra stake-address key-gen --verification-key-file stake.vkey --signing-key-file stake.skey
cardano-cli address build --payment-verification-key-file pay.vkey \
  --stake-verification-key-file stake.vkey --testnet-magic 164 --out-file pay.addr
```

Fund `pay.addr` from the [faucet](https://faucet.leios.play.dev.cardano.org/basic-faucet), then check it arrived: `cardano-cli dijkstra query utxo --address $(cat pay.addr) --testnet-magic 164`.

### 2.1 Can the funding go to an address you already use?

Yes — a Cardano address encodes only *testnet vs mainnet*, not which testnet. Verified by building one key's address at four magics:

```
magic 1    addr_test1qru6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…
magic 2    addr_test1qru6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…
magic 164  addr_test1qru6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…
mainnet    addr1q8u6dedvxf9nnp60za49rhf5e28rg8tst77rkwt8gudpdqyvw8jhg…      <- only this differs
```

Identical across every testnet magic, stake addresses too. So an address you use on preprod or preview *is* a valid musashi address, character for character. Three consequences:

- **Funds are chain-local; the address is not.** Money sent to it on musashi exists only on musashi — your preprod wallet will never show it, and `query utxo` needs a musashi node socket. The flip side is the footgun: a wrong-network send cannot bounce, because the address is valid everywhere. Name the network explicitly when you ask for funds.
- **Stake registration is chain-local too.** A stake key already registered elsewhere is unregistered here and still owes musashi's 2 ₳ `keyDeposit`.
- **What actually matters is holding the signing key in CLI form.** A wallet address gives you no `.skey`. If the key came from a mnemonic: `cardano-cli key derive-from-mnemonic --payment-key-with-number 0 --account-number 0 --mnemonic-from-interactive-prompt --signing-key-file pay.skey` yields an *extended* key; flatten its verification key with `cardano-cli key non-extended-key` if a command refuses the extended form.

The tidy arrangement is to receive at the address you already use and then send onward to dedicated pool keys, so the cold, reward, and owner keys are this pool's and nothing else's. Reuse is not a replay risk — a signed transaction names inputs that exist on one chain only — but it does mean one compromise reaches both chains, and it entangles the pool's reward and owner accounts with whatever else that key does.

## 3. Certificates

### 3.1 The pool registration certificate — where the BLS key is registered

There is no separate "register my Leios key" transaction: the BLS public key and its proof of possession ride on the pool certificate, and the CLI makes it **mandatory** (`--bls-signing-key-file` is unbracketed in the usage — see [the tooling note § 2.2](../artifacts/leios-node-tooling.md)). Note it takes the **signing** key, because only the secret can produce the possession proof.

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

Real musashi constraints: `--pool-cost` must be **≥ 170000000** (minPoolCost = 170 ₳), the deposit charged by the transaction is **500 ₳** (poolDeposit), and `--pool-pledge 0` is allowed — an unmet pledge costs rewards, not the ability to forge. The relay group is *optional* in the usage, but declare yourself: it is how other nodes learn to dial you, and EB diffusion is the thing you are here to observe. Use `--pool-relay-ipv4`/`--pool-relay-port` if you have no DNS name.

### 3.2 Stake registration and delegation

Committee seating is **top `leiosCommitteeSize` pools by stake** (musashi: 900), so a pool with zero active stake is seated nowhere and votes never.

**Stake is delegated, not sent.** Nothing is ever transferred *to* a pool: the ada stays in its own address, and a delegation certificate points that address's stake credential at the pool. A pool's active stake is the sum of the balances of every address whose stake credential delegates to it, recomputed at each epoch snapshot. So there is no pool address to fund, and adding your own stake is just a matter of holding more ada at an address whose stake key is already delegated. Give it stake:

```shell
cardano-cli dijkstra stake-address registration-certificate \
  --stake-verification-key-file stake.vkey --key-reg-deposit-amt 2000000 \
  --out-file stake-registration.cert
cardano-cli dijkstra stake-address stake-delegation-certificate \
  --stake-verification-key-file stake.vkey --cold-verification-key-file cold.vkey \
  --out-file delegation.cert
```

(`registration-and-delegation-certificate` does both in one, if you prefer.)

Self-delegation of a 10,000-ada faucet payment is *far* too little stake to be scheduled, so the real stake comes from the faucet's **delegate** widget — but **only after the pool is on chain**. Conway's DELEG rule checks the delegatee exists (`checkStakeDelegateeRegistered`: `targetPool \`Map.member\` pools ?! DelegateeStakePoolNotRegisteredDELEG`, [`Deleg.hs:218-222`](https://github.com/IntersectMBO/cardano-ledger/blob/1587f21a7d1306dc590c2749a5c66232ef66aad0/eras/conway/impl/src/Cardano/Ledger/Conway/Rules/Deleg.hs#L218-L222)), so a delegation naming an unregistered pool fails phase-1 validation. The pool id is just a key hash and exists the moment the cold key does, so a faucet form will accept the string happily; it is the transaction that cannot succeed.

Our own delegation certificate rides in the *same* transaction as the pool registration, which works because certificates are applied in order and `register-pool.sh` puts the pool certificate before the delegation. A separate, later transaction — the faucet's — has no such option.

Once `query pool-state` shows the pool, give the widget the bech32 pool id and it delegates ~1,000,000 test ada. **Its transaction will look unrelated to your pool**, and that is expected: delegation is a *certificate* in the transaction body, not a payment, so an explorer's inputs-and-outputs view shows only the faucet paying its own fee — in our case 10 → 9.8 ada at one of its enterprise addresses (header byte `0x60`, no stake part at all, so that output stakes nothing anywhere). Confirm it three ways instead:

- **Raw CBOR**: search the transaction for your pool's *hex* id. A `stake_delegation` certificate is `(2, stake_credential, pool_keyhash)`, so your hash appearing there is the delegation.
- **`query pool-state`**: `spsDelegators` gains a second entry — the faucet's stake credential. This reflects current delegations, not the snapshot, so it updates immediately.
- **`query stake-snapshot --stake-pool-id <hex>`**: `mark` jumps to the delegated amount, and walks to `set` then `go` over the next two epochs.

The size is a tell too: 367 bytes against ~228 for a minimal one-in-one-out, the difference being a delegation certificate plus the stake key's witness.

```shell
cardano-cli dijkstra stake-pool id --output-bech32 --cold-verification-key-file keys/cold.vkey
```

### 3.3 Pool metadata, and what Unicode survives

The name is **not on chain**: the certificate carries only `--metadata-url` and `--metadata-hash`, and everything readable lives in the JSON you publish at that URL. Unicode is fine there. Measured against the w36 CLI's validator, 2026-09-22 (`cardano-cli dijkstra stake-pool metadata-hash`), not quoted from a schema:

| Field | Limit | Notes |
|---|---|---|
| `name` | ≤ 50 **characters** | Counted in characters, not bytes: 50 Greek capitals (100 bytes) pass, 51 fail. `ΛΕΙΟΣ` verified. |
| `ticker` | 3–5 **characters** | The CLI accepts `ΛΕΙΟΣ`, but the off-chain metadata-registry convention is `[A-Z0-9]{3,5}` — keep the ticker Latin so explorers render it as intended. |
| `description` | ≤ 255 characters | 256 rejected. |
| `homepage` | no length check | The validator does not bound it; only the file cap below does. |
| whole file | **≤ 512 bytes** | The one byte-denominated limit, and where Greek costs double: two bytes per character. |
| `--metadata-url` | ≤ **128 bytes** | `Url`'s decoder allows 128 from protocol version 9 onward and 64 before; musashi runs version 12, so 128 — a 67-character URL was accepted. |

Greek in the name works — this deployment uses `ΘΕΛΩ` — and the length limit is what shaped the ticker: **`THELIO` is six characters and is rejected** ("must have at least 3 and at most 5 characters, but it has 6"), so the pool runs `THELO`, five Latin characters, which also keeps every explorer happy. `ΘΕΛΙΟ`, the transliteration, is exactly five and also validates, as does a truncated Latin `THELI`. After any edit to [`pool-metadata.json`](./pool-metadata.json), re-hash:

```shell
cardano-cli dijkstra stake-pool metadata-hash --pool-metadata-file pool-metadata.json
```

Then publish the file and pass both to the registration:

```shell
METADATA_URL=https://thelio.functionally.dev/pool-metadata.json ./register-pool.sh submit
```

#### Publishing it without a web server

The chain stores an opaque URL, so the scheme is yours to choose, and `cardano-cli` can hash from `file`, `http`, `https`, and **`ipfs`** (measured 2026-09-22 on the w36 CLI). IPFS works, with one wrinkle and one caveat.

The wrinkle: the `ipfs://` scheme needs a gateway to resolve, which the CLI takes from an environment variable, not a flag —

```shell
$ cardano-cli dijkstra stake-pool metadata-hash --pool-metadata-url ipfs://<cid>
Error: IPFS scheme requires IPFS_GATEWAY_URI environment variable to be set.
$ IPFS_GATEWAY_URI=https://dweb.link cardano-cli dijkstra stake-pool metadata-hash --pool-metadata-url ipfs://<cid>
```

— and it requests `<gateway>/ipfs/<cid>`. Note that `https://ipfs.io` now answers that path with **HTTP 429** and a notice that it is "switching to a service worker gateway only", so pick a gateway that still serves paths (`dweb.link`) or a pinning service's own.

The caveat is the one that matters: *we* can resolve `ipfs://`, but the consumers of pool metadata — explorers, SMASH-style aggregators — generally fetch `http(s)`. Registering a bare `ipfs://` URL means the pool's name may simply never be displayed anywhere. So put the file on IPFS and register an **https gateway URL** for it: no web server, and any consumer can fetch it.

All of these fit the 128-byte URL limit (measured, with a 59-character CIDv1):

| Form | Bytes |
|---|---|
| `ipfs://<cid>` | 66 |
| `https://<cid>.ipfs.dweb.link` (subdomain) | 82 |
| `https://dweb.link/ipfs/<cid>` (path) | 82 |
| `https://gateway.pinata.cloud/ipfs/<cid>` | 93 |
| `https://gist.githubusercontent.com/<user>/<id>/raw/pool-metadata.json` | 97 |

A gist raw URL **with** the commit-sha path segment is 138 bytes and does *not* fit — use the shorter form that tracks the latest revision, and remember it then follows edits, so re-hash if you change the file.

Two things to get right whichever transport you pick. **Pin the content**, on your own node or a pinning service; an unpinned CID stops resolving once caches evict it, and the chain will point at nothing. And verify after publishing — the on-chain hash is blake2b-256 of the file's bytes, independent of the CID, so the check works over any scheme:

```shell
cardano-cli dijkstra stake-pool metadata-hash \
  --pool-metadata-url https://<cid>.ipfs.dweb.link \
  --expected-hash cb61d75ac00a5c372481fdb5117c03c12b08c1054b306bb20f03cc3498134677
```

Changing the name later is an ordinary re-registration: publish new JSON, submit an updated certificate with the new hash. The deposit is not charged twice.

### 3.4 Submit

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

Three witnesses: the payment key pays, the stake key authorizes its own registration and delegation, the cold key authorizes the pool registration.

## 4. The pod

`/app/run-node.sh` takes no key flags, so a producer must replace the command. [`musashi-bp.yaml`](./musashi-bp.yaml) is the relay spec plus a `keys` volume and an explicit `cardano-node run`. Switch over:

```shell
podman kube down musashi-relay.yaml
podman kube play musashi-bp.yaml          # same ports, ./config, and /data/musashi
```

It keeps the chain database, so there is no resync. The two specs pin the same image digest — **bump both together** (see the cheatsheet's version-skew warning).

One permission requirement is functional, not hygienic: `cardano-node` checks the **VRF** signing key at startup and refuses to run if it grants any group or other permission ([`checkVRFFilePermissions`](https://github.com/IntersectMBO/cardano-node/blob/afa091b4af2795d1d9c46e59145ed16127760f7b/cardano-node/src/Cardano/Node/Run.hs#L871)). `make-spo-keys.sh` already sets `600` on every signing key, so this is only a thing to remember if you move files around by hand.

## 5. Confirm it took

```shell
# the pool is on chain
cardano-cli dijkstra query pool-state --stake-pool-id $(cardano-cli dijkstra stake-pool id \
  --cold-verification-key-file keys/cold.vkey) --testnet-magic 164
# confirmed here: spsBlsKey contains the registered BLS key and possession proof
```

```shell
# the op-cert and KES window are sane
cardano-cli dijkstra query kes-period-info --op-cert-file keys/opcert.cert --testnet-magic 164
# are we scheduled to forge?  (needs the VRF signing key)
cardano-cli dijkstra query leadership-schedule --genesis config/shelley-genesis.json \
  --stake-pool-id <pool-id> --vrf-signing-key-file keys/vrf.skey --current --testnet-magic 164
```

In the log, the producer-only traces appear: `Forge.Loop.*` (`StartLeadershipCheck` → `NodeIsLeader`/`NodeNotLeader` → `AdoptedBlock`), and on the Leios side `Consensus.LeiosKernel.BlockForged`, `BlockAnnounced`, `Voted` / `NotVoted`, `VoteScheduled`, `BlockCertified`. `NotVoted` is the one to watch: it is how you learn you hold a seat but are failing a vote condition.

Operational findings and trace analyses are recorded append-only in the [Musashi observations and analyses log](./observations.md). Put conclusions there with the capture hash, node version, evidence, and telemetry limitations rather than leaving them only in terminal output or conversation history.

**No restart is needed when the stake goes live.** The credentials were read at startup; what changes at the snapshot is the *ledger's* view, which the node learns by applying blocks. Forging is a per-slot leadership check against that state, and the Leios seat is looked up per vote attempt — `(getLeiosCommittee ls >>= getLeiosSeatId vk) ?>= NotOnCommittee` ([`LeiosVoting.hs:341`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosVoting.hs#L341)), with `vk` derived from the loaded signing key — so nothing is cached across the boundary. Until you are seated, expect `NotVoted` with reason **`NotOnCommittee`**; afterwards it simply starts voting. A restart is only needed when the *node's own* inputs change: new keys or op-cert, or an edited `config.json`.

**Timing.** Stake delegated in epoch *N* is active at the start of *N+2*; musashi epochs are 21,600 slots at 1 s, so **6 hours each**. A submission at an arbitrary point in epoch *N* therefore waits 6–12 hours, and committee seating occurs on the same snapshot boundary, since [the committee is taken from the stake distribution](../artifacts/leios-node-protocol-parameters.md) carrying whichever BLS keys are registered.

## 6. Two rotations, both about 93 days

- **KES**: `maxKESEvolutions = 62` × `slotsPerKESPeriod = 129600` s ⇒ ~93 days from the `--kes-period` you issued at. Run `./make-spo-keys.sh rotate-kes` to generate a new KES key, issue a new operational certificate with the incremented counter, archive the old set, and then restart the producer. `query kes-period-info` tells you where you are. Do not use the `opcert` step as a key rotation: it deliberately reuses the existing KES key for a respun chain.
- **The BLS key**: honored only while `epoch < registeredIn + maxKeyAge`, and `maxKeyAge` on musashi is **374 epochs** ≈ 93.5 days at 6-hour epochs. It expires by the same clock, but renewing it means **re-registering the pool** with a new BLS key, not reissuing a certificate. A seated pool whose key has aged out is *keyless*: it occupies a committee seat, cannot vote, and any certificate bit set on it invalidates that certificate.

## 7. When the network is respun

Upstream respins musashi "every couple of weeks", and a respin is a new chain instance: the pool registration, the stake, the delegation, and the KES clock all go with it. The keys do not.

**What survives** — and therefore what you must *not* regenerate:

- Every key pair in `keys/`. They are keys, not chain state. `make-spo-keys.sh` refuses to overwrite them, which is exactly right here.
- **The pool id**, since it is the cold key's hash: `pool13pssq9…` stays yours, so the faucet's delegate widget takes the same string as before.
- The published metadata — `pool-metadata.json`, its IPFS CID, and the hash in the certificate are all chain-independent.
- Both addresses (`payment.addr`, `stake.addr`): testnet addresses encode no chain identity, so they are valid on the new instance, just empty.
- The pod specs, the scripts, the NAT forward, the DNS record.

**What has to be redone, in this order** — the order matters at step 3:

```shell
cd musashi
./pin-config.sh                         # 1. new genesis, new systemStart, new MinNodeVersion
podman kube down musashi-bp.yaml        # 2. stop the node before touching its database
rm -rf /data/musashi                    # 3. remove the old chain DB and LeiosDb from the explicit pod hostPath
#    4. bump BOTH pod specs to the image week the new network declares
#       (grep MinNodeVersion config/config.json; tag AND digest, in
#       musashi-relay.yaml and musashi-bp.yaml)
./make-spo-keys.sh opcert               # 5. KES periods restart from the new genesis
podman kube play musashi-bp.yaml        # 6. and let it sync
```

Step 5 is the one that is easy to miss and impossible to skip: the KES period is derived from the chain's own `systemStart`, so a respun network starts at period 0 while your existing certificate says period 10 — a certificate from the *future*, which the node will refuse. Re-issue it **after** re-pinning, so the script reads the new genesis. The cold counter advances (1 → 2 here), which is harmless: a fresh chain has no recorded counter to conflict with.

Then repeat the registration cycle, exactly as the first time:

```shell
#    fund payment.addr at the faucet, then
RELAY_HOST=thelio.functionally.dev METADATA_URL=https://functionally.mypinata.cloud/ipfs/QmcyS1urh1df3Qw8nHY2wAX1e2V75s8ePdTFCUiGY9RyiM   ./register-pool.sh submit
#    then the faucet's delegate widget with the same pool id, then wait ~2 epochs
```

The 500 ₳ deposit and the 2 ₳ stake-key deposit are charged again — new chain, new deposits — and `bksRegisteredIn` resets to the new epoch, which restarts the BLS key's 374-epoch clock along with the KES one.

Finally, update [§ 0](#0-this-deployment) with the new epoch and dates, and check whether the respin moved any Leios parameter: `pin-config.sh` prints the periods, committee size, quorum, and derived certification gap on every run, so a diff of that output against this document is the cheapest parameter check there is.

## 8. Block-production statistics

[`analyze-block-production.py`](./analyze-block-production.py) counts `TraceForgedBlock` events by epoch and compares the complete-epoch counts with the Praos expectation. Always give it an explicit inclusive epoch range: this prevents the current partial epoch from being mistaken for a low-production complete epoch. Include every rotated log covering that range; the script deduplicates repeated forged-block records by slot and block hash and checks that the logs contain one `TraceStartLeadershipCheck` for every slot in each requested epoch. A warning may mean missing logs, node downtime, or dropped trace messages; distinguish those cases before interpreting a low block count as leader-election evidence.

The expected rate is not simply active stake share times the number of active slots. For stake fraction $\sigma$, active-slot coefficient $f$, and epoch length $L$, it is $L[1-(1-f)^\sigma]$. The script derives this from the pinned Shelley genesis when given the pool and total active stake:

```shell
python ./analyze-block-production.py \
  --log musashi-bp.log.gz --first-epoch 64 --last-epoch 65 \
  --stake 1009497788035 --total-active-stake 367948233779128
```

Stake and total active stake are snapshot-dependent. Re-query and record both rather than reusing the example numbers after an epoch or network respin. If the expected rate is already known, pass `--expected-rate 3.0395` instead. For a durable record independent of node-log retention, provide a CSV with `epoch,blocks` columns and the rate on the command line, or an `expected_rate` third column when the expectation varies by epoch:

```shell
python ./analyze-block-production.py --counts block-counts.csv --expected-rate 3.0395
```

The exact slot-level count model is binomial, but at approximately three successes in 21,600 trials per epoch its Poisson approximation is effectively indistinguishable for this diagnostic. The script reports three related quantities. The exact Poisson interval and exact two-sided test assess whether the aggregate production *rate* agrees with the stated expectation. A parametric-bootstrap Pearson discrepancy compares the full sequence with the fixed expected rates. A second Monte Carlo Pearson test conditions on the observed total, so it detects unusual epoch-to-epoch clustering without treating a high or low total as dispersion. This simulation-based treatment remains valid with sparse cells, unlike the usual asymptotic chi-squared histogram test. It does not repair a small sample: until tens of complete epochs have accumulated, the interval will be wide and the tests primarily descriptive.

## 9. What a single node costs you

Honest list, since you asked for this shape deliberately:

- **The producer is publicly dialable**, and the registration certificate advertises it. Nothing absorbs a flood aimed at your block production.
- **No hot-swap.** A relay pair lets you restart one node while the other keeps the pool connected; here every restart — config change, image bump, KES rotation — is downtime for forging.
- **Observation perturbs production.** The trace levels in [the instrumentation note](../artifacts/leios-tx-flow-instrumentation.md) are cheap on a relay; on a producer, heavy tracing competes with the forge loop, and `TxSubmission.Remote.*` is the loudest family on the node.
- **Peer topology is doing double duty.** The pinned `topology.json` bootstraps from `leios-node.play.dev.cardano.org` and fans out via ledger peers, which is right for a relay. A producer normally has `localRoots` pointing at its own relays and nothing else.
- **One vantage point.** Anything about *differences* between nodes — mempool fragmentation, in particular — needs more than one node, which is what the local `dozen-devnet` is for.

None of these are reasons not to do it here; they are the reasons the standard shape exists.

## Sources

- CLI shapes read from the **w36** `cardano-cli 11.2.2.0` (rev `afa091b4`) extracted from the running image, 2026-09-21: `dijkstra node key-gen{,-KES,-VRF,-BLS}`, `dijkstra node issue-op-cert`, `dijkstra stake-pool registration-certificate`, `dijkstra stake-address *`, `dijkstra transaction build/sign/submit`.
- Deposits, costs, and KES parameters from musashi's [`shelley-genesis.json`](https://book.play.dev.cardano.org/environments-pre/leios/shelley-genesis.json) (pinned 2026-09-21): `poolDeposit` 500000000, `keyDeposit` 2000000, `minPoolCost` 170000000, `slotsPerKESPeriod` 129600, `maxKESEvolutions` 62, `epochLength` 21600, `slotLength` 1, `activeSlotsCoeff` 0.05.
- Leios committee seating, `maxKeyAge`, and the keyless-seat rule: [the protocol-parameter note](../artifacts/leios-node-protocol-parameters.md) §§ 3–4, from cardano-ledger `1587f21` (the w36 pin).
- Upstream's own testnet documentation, `ouroboros-leios` @ `9fa5a95`: [`site/docs/testnet/getting-started.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/site/docs/testnet/getting-started.md), [`register-stake-pool.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/site/docs/testnet/register-stake-pool.md), [`rewards-program.md`](https://github.com/input-output-hk/ouroboros-leios/blob/9fa5a956db7a7860065b68e221c6f7ce647242d5/site/docs/testnet/rewards-program.md) (rewards page last updated 2026-08-10) — source of the faucet amounts (10,000 ada payment, ~1,000,000 ada delegation), the Application-Code-in-metadata mechanism, the two-epoch snapshot wait, the `cardano-ping` relay probe, and the host prerequisites in § 0. All four links verified reachable 2026-09-21.
