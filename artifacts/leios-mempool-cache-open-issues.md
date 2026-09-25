# Open mempool and cache issues and hypotheses (from #team-leios)

**Provenance:** ⏳🤖 LLM-generated, pending human review. Compiled 2026-09-24 from the private `#team-leios` Slack channel (`C074AHSKJF7`), cross-referenced against GitHub issue/PR state. Slack is operator and engineer testimony — primary evidence of what the team is observing and hypothesizing, not a specification of deployed behavior. Where a claim is settled in source or a merged PR, that is noted. Times are the channel's Mountain Daylight Time (MDT = UTC−6) unless a message states UTC.

**Scope.** "Mempool (including caches)" is read broadly: the transaction mempool, the `LeiosTxCache` (validation-evidence index), the `LeiosDb` (SQLite EB/closure store), the on-disk ledger backend that the mempool sizes against, and the fragmentation question that motivates the whole area. This is a snapshot of *open* threads and unresolved hypotheses; closed/shipped items appear only as context.

**Abbreviations.** EB endorser block, RB ranking block, tx transaction, GC garbage collection, LSM log-structured merge (the disk-backed ledger backend), IOPS input/output operations per second, TPS transactions per second, PR pull request, `k` the security parameter (108 on musashi), pparams protocol parameters, CIP Cardano Improvement Proposal. Defined again at first substantive use.

---

## 1. The headline open issue: a relay stops fetching missing EB txs and parks its chain forever

**Status: OPEN.** [`ouroboros-leios#1111`](https://github.com/input-output-hk/ouroboros-leios/issues/1111), filed 2026-09-23 by Krzysztof Paprocki; no assignee, one comment. This is the most consequential unresolved mempool/cache defect in the channel and the same class of bug as our own [parked-block observation](../musashi/observations.md).

**What happened (operator post-mortem, `w36`, honest `cardano-node` BP+relay).** PIR0 (18.8% of stake) produced no public blocks for 8 hours on 2026-09-21 (00:12Z–08:16Z); network block rate fell 22% and **Leios certification stopped network-wide** until PIR0 rejoined; ~290–299 of its blocks were orphaned. Block 54884 announced EB `2af41ec6` (994 txs); the relay stored the EB body but obtained only 603 tx bodies and, while running, **never requested the other 391**. A node parks any block certifying an EB whose closure is incomplete, so the relay's chain froze at 54884 while it stayed connected to the whole testnet; its BP followed and kept forging a private fork 299 blocks deep — past `k = 108`, so it could not roll back after a restart recovered the relay in seconds. ([post-mortem](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789981924774939), 2026-09-21.)

**Diagnosed mechanism (AI-assisted, operator-relayed — flagged as such):** "The relay's Leios fetch logic creates fetch jobs only for txs absent from **both** its tx-cache and its mempool, and copies mempool-resident txs into the DB in a separate later step. For EB `2af41ec6` that copy never landed for 391 txs, so the kernel believed the closure was complete and discarded every peer offer, while chain selection, which trusts the DB, parked block 54885 forever." The reporter suspects a **regression** — "the fetch logic must reconcile against the DB's missing set, as the July code did and w36 no longer does" — and asks "Looks like some regression (removed recon)?" ([message](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789986652061649), 2026-09-21). Root cause is not confirmed: journald truncated the relay log at the critical moment.

**Nagel's framing — this is cache staleness:** "that is cache staleness in a nutshell. If the tx cache gets updated, but the database write fails we should fail loud and restart the node + reconcile cache consistent with the db. Please keep an eye out whether this happens again with `w38`. The writes are done differently (asynchronous) now, but a failure should still bubble up correctly." ([message](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789998809866239), 2026-09-21.)

**Open questions carried forward:**
- Is the missing DB-reconciliation step a genuine regression from the July fetch logic, or a new design that assumed the mempool→DB copy is infallible?
- Does `w38`'s asynchronous write path (see §3) actually surface a failed copy loudly, or does it reproduce the silent-incomplete-closure state?
- The tx-cache/mempool/DB three-store consistency model is the underlying hazard: the fetch logic trusts (cache ∪ mempool), chain selection trusts the DB, and the copy that keeps them agreeing can silently drop txs. **This directly matches our own finding** that the fetch job set is `missedBoth = neither cache nor mempool`, so a mempool-resident-but-not-copied tx is invisible to fetch.

---

## 2. The cache-staleness root cause: tx-cache and LeiosDb write ordering

**Status: partially addressed in `w38`, watch item open.** A design thread ([2026-09-17](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789679255929899)) exposes the ordering hazard behind §1:

- The node inserts txs into the `LeiosDb` and the `LeiosTxCacheIndex`; Nagel flipped bodies so the **cache is written first for reactivity**, which "could lead to cache staleness if the write fails (but just because a write returns it's not yet durable either)."
- **The `LeiosTxCacheIndex` is always completely empty when the node initializes** — Nagel: "seeding the cache from the LeiosDb should be doable, right?" No confirmation it was done. This is a cold-start inefficiency (every restart re-fetches/re-validates) and interacts with our own `tooLate` findings, since a freshly restarted voter has no reusable validation evidence.

**Open:** whether write-durability (not just write-return) is required before the cache claims a tx is present; whether cache seeding from LeiosDb on startup was implemented; whether the async writes in `w38` (PR [consensus#2298](https://github.com/IntersectMBO/ouroboros-consensus/pull/2298), merged 2026-09-20, "single sqlite write connection") close or merely relocate the staleness window.

---

## 3. The `maxTxSize` validation-cache consensus-safety finding

**Status: OPEN design problem, no shipped fix.** Independent of the Anastasia audit, Philip DiSarro posted `LEI-CACHE-PARAM-CONTEXT-001` ("Critical consensus-safety issue") on [2026-09-02](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1788378480774549):

**Claim.** The validation cache keys a tx by **hash only**, storing no record of the protocol parameters in force when it was validated. If governance lowers `maxTxSize`, an old oversized tx stays "validated"; on re-encounter the fast `reapplyTx` path skips static checks (including size), so honest voters certify a tx the current rules reject, and the CertRB applies it with `ValidateNone` — an unauthorized certified-state acceptance. Needs only one small producer seat (not quorum stake). Only exploitable across a parameter change that turns a previously-valid tx invalid.

**Team response (open, not resolved):** Nagel asked whether the TxCache is "guaranteed to be smaller than an epoch's worth of EBs" so it could be cache-busted by the ledger-state epoch; noted that disallowing the first cert in an epoch is insufficient because txs "may be re-endorsed in the new epoch (under different params)" and the same hazard applies to any static check that changes at a hard fork / protocol-version boundary (per Alexey Kuleshevich). ([message](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1788515552316389), 2026-09-04.) The recommended fix — bind every cache entry to a ledger-context fingerprint (pparam hash, era, tip) — is not reported as implemented.

**Relation to our records.** This is **not** audit **LEI-004**. LEI-004 concerns variable-width, peer-supplied transaction hashes reaching `unsafeIndex` in the optimized cache; it says nothing about the ledger context attached to cached validation. The present issue is instead tracked publicly as [`ouroboros-leios#1084`](https://github.com/input-output-hk/ouroboros-leios/issues/1084), “LeiosTxCache cached validity might go stale.” Both touch the cache, but their mechanisms and consequences are distinct.

---

## 4. The central open hypothesis: how much mempool fragmentation is actually possible?

**Status: OPEN, actively contested — this is the scope-defining question for the whole workstream.** Two camps, unresolved:

**Nagel's position:** the effect of fragmentation is understood (worst case reverts to Praos throughput); the *unknown* is **how much fragmentation can arise in the first place**. "I'm not that much interested in the effects of mempool fragmentation, and more about how much fragmentation can there be" ([2026-09-14](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789401569216729)). He questions the soundness of the 100%-fragmentation assumption: "Would you agree that 100% fragmentation is impossible? (it would mean all bps are essentially eclipsed and only ever forge what they get from a side channel)… I hear constantly that it's not going to work under that assumption. Hence, I'm questioning the soundness of that assumption." ([2026-09-14](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789410009991529)).

**Wójtowicz's position (smol-world sim):** the sim **cannot pin down the "true" fragmentation** expectable on mainnet; it can *assume* a severe level and show the consequence, then tune the system to respond. "I don't think we can use the sim to answer the question of how much fragmentation there can be, instead we can assume it (some severe level) and see what happens, and tune the system to respond to that" ([2026-09-14](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789401806221739)). The sim outputs the **settled equivalent fragmentation and steady-state cert rate / goodput** given egress and tx-cache depth ([message](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789401328264359)). Open sub-question Nagel raised: can smol world's Sybil network sim model fragmentation directly ([2026-09-14](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789400523706679))? He offered to show "what 100% mempool fragmentation leads to on the sim."

**Key clarification captured (settles one sub-point):** "Mempool fragmentation is independent of tx cache size. The cache will also be sized following the expected possible fragmentation" ([Nagel](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789401511768849)); but "the cert rate and goodput **is** affected by the tx-cache" ([Wójtowicz](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789401669724769)). So fragmentation and cache size are independent inputs, jointly determining goodput.

**Proposed test (open):** run it on mainnet — SPOs set higher mempool overrides and exert load from multiple network points, "no leios, just attempted mempool fragmentation" ([Nagel, 2026-09-14](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789414146102539)). Sebastian's original stress-case framing: "unique demand ingested at maximum possible rate directly into each block producer's mempool," swept across mainnet-size / slightly-bigger / much-bigger mempools ([2026-07-23](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1784841828701289)). This is the same experiment Brian ran on mainnet (the `post-cip/mempool-measurements` notebook) and directly feeds candidate workstreams (a)/(d) and the [attack-economics damage function $H_\text{frag}$](../assessments/attack-resource-economics.md).

---

## 5. The bistability / "never heals" hypothesis

**Status: OPEN, unresolved theoretical dispute.** Whether a fragmented Leios system recovers on its own once load or the attacker backs off:

- **"Never heals" concern:** "Linear, without trickery of txcache, the dynamic EB sizing actuator etc will not recover by itself even when the attacker is gone" / "The risk is that if the system falls over due to adversarial action/mempool fragmentation (still to be confirmed), it will stay down unless load is cut hard, i.e. tx arrival rate even below Praos's 12 TPS" (paraphrased from the [stability thread](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1788425043654179), 2026-09-03).
- **Panagiotakos's counter:** "As excess conflicting load is absorbed, and assuming heavy mempool fragmentation does not arise without malicious action, I would expect the system to recover" ([2026-09-03](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1788425548759149)). And: **Praos is also bistable** under a periodic chain-quality attacker, so "fundamentally both systems are bistable" and the real question is "under what conditions or how easy it is to push and keep the system to the low throughput regime?" ([message](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1788425043654179)).
- **Wójtowicz on tipping:** heavy fragmentation "may be needed as the initial impulse, but then if it tips, the bar to keep it down is much lower" ([2026-09-03](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1788425829547779)); the smol-world sim reports the **steady-state** response, which is exactly the object this dispute needs.

**Open:** whether recovery requires the "trickery" (tx-cache reuse + dynamic EB-size actuator) or happens without it; the size of the hysteresis (how far below the tipping load one must cut to recover); and whether the bistability is materially worse than Praos's own.

---

## 6. Panagiotakos's partial-EB mitigation (design proposal, open)

**Status: OPEN proposal, "simple to implement?" unanswered.** To avoid reverting all the way to Praos throughput under fragmentation, a [2026-09-02 design](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1788337059210669) (58 replies): fetch/vote on the **first 2 MB** of an EB when you are missing more than 2 MB, else the whole EB; combine into a **full-block cert** (>75% full votes) or a **partial-block cert** (>75% full+partial votes, only first 2 MB applied). Cost: cert size doubles. Benefit: some EB throughput survives inconsistent mempools instead of collapsing to Praos. Needs a new parameter — "the maximum EB size the network can deliver within L_vote (assuming limited competing EBs, an honest EB producer, 100% fragmentation, an active network attacker)." Nagel asked whether it is simple to implement (engineering answer not captured as resolved).

---

## 7. Ledger backend, GC pauses, and mempool sizing

Several interlocking infra items, mostly progressing but with open edges:

- **GC pauses favor the disk backend (open default decision).** `V2InMemory` shows up to **20 s GC pauses**; `V2LSM` (disk-backed) is far lower ([Knutsson, 2026-08-21](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1787314210959389)). Consensus that LSM should become default *when Leios is enabled* (20 s pauses "quite bad for the forge loop"), but Sagredo flags the SPO forging-performance implications are **not yet understood**, so it is not yet the unconditional default.
- **Mempool revalidation cost is ~0.104 ms/tx, near-perfectly linear in mempool depth** ([Nagel, 2026-08-22](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1787399654458319)) — matching the independent ~145 µs/tx `reapplyTx` measurement. Now moved "off the lock," so resync no longer stalls diffusion or the forge loop. This is the same serial-revalidation cost our `tooLate` analysis attributes late votes to; it is understood and partly mitigated, not eliminated.
- **Mempool now sizes itself from pparams in `w38`** ([Nagel, 2026-09-21](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789983274467669)) via PR [consensus#2280](https://github.com/IntersectMBO/ouroboros-consensus/pull/2280) (`TxEbMeasure` + `MempoolMeasure`, merged 2026-09-19) — so the `MempoolCapacityBytesOverride` in our pinned config can be dropped once we move to `w38`. **Re-pin item** for [`leios-node-mempool-txcache.md`](./leios-node-mempool-txcache.md), which was pending on this PR. Note the PR's own FIXME: the EB tx serialization was wrong when creating an EB.
- **Storage tiering (open operational guidance):** `leios.vol.db` needs fast (NVMe) storage — "If it's too slow, it will impact voting/certification and block diffusion"; `leios.imm.db` should be fine on slow storage (GP3), "not yet tested" ([thread](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1789976904870589), 2026-09-20/21). Lotoski's prior finding: `leios.db` on slow storage caused "noticeable wedges (block stall, metrics serving stall)."
- **Lock-free mempool reads (open PR):** [consensus#2308](https://github.com/IntersectMBO/ouroboros-consensus/pull/2308) replaces `TMVar` with `SVar` for non-blocking reads — proposed for leios-prototype "to see if there's any observable gains" ([Popović, 2026-09-21](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1790002487656019)). **Still OPEN** as of this compile.

**Merged context (not open, for orientation):** [consensus#2261](https://github.com/IntersectMBO/ouroboros-consensus/pull/2261) (immutable/volatile LeiosDB split + GC V2, 2026-09-15), [#2272](https://github.com/IntersectMBO/ouroboros-consensus/pull/2272) ("Abstain rather than die on an unreadable EB closure", 2026-09-17), [#2298](https://github.com/IntersectMBO/ouroboros-consensus/pull/2298) (single SQLite write connection + async writes, 2026-09-20).

---

## 8. Diagnostic gaps that block progress on the above

- **Empty-mempool observability problem (open):** Frisby ran a testnet node whose "Mempool is almost always totally empty… while the tx firehose is on," blocking validation of how well LeiosFetch leverages the mempool as an alt tx source ([2026-08-26](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1787768920526479)). He asked for a shortlist of causes; not resolved in-thread. This is the same "is my node actually seeing load?" problem our own captures hit.
- **Logging drops obscure root cause:** the `#1111` post-mortem could not be closed because journald truncated the relay log ("There were too many logs and some were dropped. I need to reconfigure logging"). A recurring obstacle — trace volume defeats the investigation exactly when it matters.
- **kleioscan fragmentation-metric wording is disputed (open):** Nagel questioned kleioscan's Leios fragmentation panel — "Tx duplication" (should be "overlap": txs are *endorsed* multiple times, not duplicated), "EB skip rate" (expected ≈ 1−0.95¹⁰ ≈ 40% at gap 10; "anything up to that is fine"), "Skipped-EB coverage" ("no idea what this is saying"), "Potential loss" ("we don't lose transactions, do we?") ([2026-08-26](https://input-output-rnd.slack.com/archives/C074AHSKJF7/p1787731043191039)). These definitions gate any use of kleioscan's fragmentation numbers as evidence, and connect to our deferred Kostas Dermentzis metric-definition ask.

---

## 9. Cross-references to this repository

| Slack item | Our record |
|---|---|
| §1 relay stops fetching missing txs → parks chain (`#1111`) | [`observations.md`](../musashi/observations.md) parked-block analysis; our `missedBoth` fetch-set finding in [facts.md](../facts.md) |
| §2 cache/LeiosDB write-order staleness | [`ouroboros-leios#1111`](https://github.com/input-output-hk/ouroboros-leios/issues/1111); [the mempool and LeiosTxCache map](./leios-node-mempool-txcache.md) |
| §3 cached validation outliving its ledger context | [`ouroboros-leios#1084`](https://github.com/input-output-hk/ouroboros-leios/issues/1084); distinct from audit LEI-004 and LEI-008 |
| §4 how-much-fragmentation | [attack-economics $H_\text{frag}$](../assessments/attack-resource-economics.md) §4; candidate workstreams (a)/(d) |
| §5 bistability | attack-economics self-defeat/damage-curve discussion |
| §7 revalidation ~0.104 ms/tx; serial reapply | our `tooLate` diagnosis (serial `applyTx`/`reapplyTx` in the vote window) |
| §7 mempool self-sizing in `w38` (PR #2280) | re-pin item for [`leios-node-mempool-txcache.md`](./leios-node-mempool-txcache.md) |
| §8 kleioscan metric wording | deferred Dermentzis metric-definition ask ([scope to-do](../README.md)) |

## Sources

All primary sources are messages in the private Slack channel `#team-leios` (`C074AHSKJF7`), linked inline above and treated as engineer/operator testimony, not specification. GitHub issue and PR states were checked 2026-09-24:

- [`ouroboros-leios#1111` — Leios relay permanently stalls (version w36)](https://github.com/input-output-hk/ouroboros-leios/issues/1111) — OPEN
- [`ouroboros-leios#1084` — LeiosTxCache cached validity might go stale](https://github.com/input-output-hk/ouroboros-leios/issues/1084) — OPEN
- [`ouroboros-consensus#2280` — Introduce TxEbMeasure and size Mempool accordingly](https://github.com/IntersectMBO/ouroboros-consensus/pull/2280) — MERGED 2026-09-19
- [`ouroboros-consensus#2308` — Lock-free Mempool reads](https://github.com/IntersectMBO/ouroboros-consensus/pull/2308) — OPEN
- [`ouroboros-consensus#2298` — LeiosDb{Reader,Writer} API + single sqlite write connection](https://github.com/IntersectMBO/ouroboros-consensus/pull/2298) — MERGED 2026-09-20
- [`ouroboros-consensus#2261` — Immutable/volatile split of LeiosDB + garbage collection V2](https://github.com/IntersectMBO/ouroboros-consensus/pull/2261) — MERGED 2026-09-15
- [`ouroboros-consensus#2272` — Abstain rather than die on an unreadable EB closure](https://github.com/IntersectMBO/ouroboros-consensus/pull/2272) — MERGED 2026-09-17
