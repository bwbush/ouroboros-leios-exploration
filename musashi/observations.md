# Musashi observations and analyses

**Provenance:** ⏳🤖 LLM-generated, pending human review

This is the append-only operational analysis log for the Musashi node environment. Add new dated entries at the end; do not silently revise an earlier conclusion. Correct or supersede one with a later entry and a cross-reference. Each entry must identify its deployed-network evidence, distinguish observation from interpretation, and state what the available telemetry cannot establish.

## 2026-09-23

### `tooLate` vote diagnosis: closure validation dominates, with acquisition and serial-worker tails

**Layer:** deployed Musashi network observations plus pinned node implementation; the inequalities discussed below are Cardano Improvement Proposal (CIP) design rationale, not measurements or implementation invariants.

**Capture:** [`musashi-bp.log.gz`](./musashi-bp.log.gz), 36,347,675 bytes, SHA-256 `87bffbb5726e70dbf96b91d358951aeb1369175b34231454ab045bf39990a192`, covering 2026-09-22 13:29:59.581 UTC through 2026-09-23 13:30:07.002 UTC. The file is intentionally gitignored. Node image: `prototype-2026w36@sha256:0df972de2193f9299af4df409fde2b7ea56188ddfe2c3b77aa661e23b226a566`; consensus source pin used to interpret the traces: `ouroboros-consensus@b56977b`.

#### Result

📊 **EVIDENCE:** After the pool became committee-eligible at epoch 64, the capture contains 318 acquired Endorser Block (EB) closures. Their terminal local outcomes are 270 votes, 28 `tooLate` results, and 20 `chainTipDoesNotAnnounce` results. The 28 `tooLate` traces split by observable stage:

| Observed mechanism | Count | Trace evidence |
|---|---:|---|
| Closure was first handled after the seven-second deadline | 4 | `BlockTxsAcquired` and `VoteScheduled` both occur after slot onset + 7 s |
| Closure validation completed after the deadline | 22 | Timely acquisition and scheduling, then `EbValidated`, immediately followed by `NotVoted(reason=tooLate)` |
| Voting worker did not handle an already-acquired closure until after the deadline | 1 | Closure at +2.691 s; `VoteScheduled` at +7.202 s; no `EbValidated` |
| Voting worker handled the closure only just before the deadline, then validation crossed it | 1 | Closure at +2.838 s; scheduling at +6.880 s; validation at +7.666 s |

Five additional `tooLate` traces occur before epoch 64 and are excluded. The implementation checks time before committee membership, so those events do not establish that the then-unseated pool lost votes.

#### Timing and transaction-cache evidence

Events were joined by `ebHash`. Wall-clock ages were measured from `systemStart + ebSlot × slotLength`; Musashi has a one-second slot. The approximate local voting-work duration is `EbValidated time − max(slot onset + 3 s, VoteScheduled time)`. That interval includes opening and reading the forker and the cheap chain/seat checks as well as `validateEbClosure`, so it is not a pure CPU measurement of transaction validation.

| Measure | 270 successful validations | 23 post-validation `tooLate` cases |
|---|---:|---:|
| Median closure arrival | 2.160 s | 2.946 s |
| Median approximate voting-work duration | 0.689 s | 4.545 s |
| Median full `applyTx` count | 139 | 2,224 |
| Median cheaper `reapplyTx` count | 1,664 | 531 |
| Median validation completion | 3.767 s | 7.866 s |
| Latest validation completion | 6.959 s | 11.375 s |

The clearest discriminator is the amount of full validation. A representative failure at slot 1,382,800 accepted the announcement at +0.499 s, acquired the body at +1.607 s, acquired and scheduled the closure at about +2.77 s, and completed validation at +9.489 s. Of 2,724 transactions, 2,458 required full application and 266 were reapplied. The work after the +3 s window opening took approximately 6.49 s, exceeding the four seconds remaining before the vote deadline.

Two adjacent-slot pairs expose head-of-line blocking in the single voting loop. Slot 1,391,310 finished validation and emitted `tooLate` at 02:28:38.201733 UTC; the already-acquired slot-1,391,311 closure was scheduled 105 microseconds later, already 0.202 s past its deadline. Slot 1,392,172 similarly occupied the worker through 02:42:59.880013 UTC; slot 1,392,173 was scheduled 33 microseconds later with only 0.120 s left, then its 0.786 s of local work crossed the deadline.

The pinned implementation explains both classifications. `lHdrWait = 3 s` and `lVoteWindow = 4 s` are hard-coded stubs. One deadline check precedes forker creation and closure validation; a second follows `validateEbClosure`. Cache hits use `reapplyTx`, while misses use full `applyTx`. The same source explicitly notes that closure validation is linear, recounts a devnet in which it exhausted the vote window, and records TODOs to validate when the closure arrives or incrementally while it streams ([`LeiosVoting.hs`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosVoting.hs#L140-L400)).

❓🤖 **SCRUTINY:** The evidence strongly supports full validation of cache-cold, near-maximum-transaction closures as the principal mechanism in this capture, with late acquisition and serial voting-loop contention as secondary mechanisms. It does not isolate why an individual `applyTx` was slow or prove that the same proportions persist under another load, node, epoch, or network deployment.

#### What “cache-cold, near-maximum closures in a serial voting loop” means

The node as a whole is multithreaded: networking, chain selection, forging, mempool processing, fetching, and voting run concurrently. The relevant path is nevertheless serial in two narrower senses.

First, `LeiosTxCache` is not a hardware CPU cache and “cold” does not mean that transaction bytes were absent from RAM. It is a trust-bearing index recording whether the node has already *validated* a transaction, either through its mempool or an earlier Leios voting pass. Possessing or fetching a transaction body proves only availability; it does not license a vote asserting that the whole closure is a valid extension of the announcing RB. On a cache hit, the implementation has an `assumeValidated` token and may call `reapplyTx`, skipping static validation while repeating the state-dependent checks. Without that validated tag it must call full `applyTx`; otherwise the node could sign a closure containing an invalid signature, script, value balance, input, or other ledger-rule failure merely because it received the bytes. The distinction and the construction of the trusted token are traced through the [transaction-cache analysis](../artifacts/leios-node-mempool-txcache.md).

Second, applying a closure threads one evolving ledger state through the transactions in closure order. The pinned implementation's `goValidate` recursion applies or reapplies one transaction, obtains the next state, then processes the next transaction. Independent transactions could conceivably be prechecked or speculatively parallelized by a different implementation, but this implementation does not do so, and arbitrary Unspent Transaction Output (UTxO) dependencies prevent simply applying the entire ordered closure concurrently.

“Near maximum” refers to the deployed limit of 2,777 transaction references per EB, derived from Musashi's 100 kB EB-reference parameter; it does not mean a 2,777-byte EB body. Twenty of the 23 post-validation late closures contained exactly 2,777 transactions, and the other three contained 2,724, 2,296, and 1,860. Across those closures, approximately 76.5% of transactions lacked reusable validated evidence and therefore followed the full-application path. Thus a typical late case asks one voting computation to make more than two thousand sequential full ledger transitions.

Finally, `runLeiosVoting` itself is one long-running logical loop. It receives closure-complete notifications, arms their timers, waits for a timer, and calls `goVote` synchronously. While `goVote` validates one closure, that loop cannot arm or service the next closure, although the rest of the node continues running on other threads. This is the head-of-line effect seen in the adjacent-slot examples. All of these events carry node thread id `74`: completing one closure is followed within tens of microseconds by scheduling the closure that had waited behind it.

The nominal four-second budget follows directly from implementation order. A closure available before +3 s is *not* validated early: its timer waits for the equivocation-observation period to finish, then validation begins when the voting window opens at +3 s. The hard deadline is +7 s, leaving at most four seconds. A closure handled after +3 s has less than four seconds. The source itself identifies this avoidable coupling and proposes validating as soon as a full closure arrives, or incrementally as it streams, so that the expensive work is not charged wholly against the voting window.

#### Relation to the protocol inequalities

The directly implicated design inequality in the [protocol-parameter timing diagram](../artifacts/leios-timing-inequalities.svg) is

$$3L_{\mathrm{hdr}} + L_{\mathrm{vote}} > \Delta_{\mathrm{EB}}^{O}.$$

The implemented Musashi vote deadline is $3 + 4 = 7$ seconds from the announcing slot's onset. The relevant optimistic end-to-end path must include receiving enough EB material and completing the processing needed to vote. This node missed that bound on 28 observed paths; in 23, validation completed after the bound. This is evidence that the assumed optimistic bound $\Delta_{\mathrm{EB}}^{O}$ was not met by this deployed node and workload. It does not by itself falsify the abstract inequality: the inequality constrains a parameterization against an assumed network-and-processing bound, whereas this capture measures one implementation at one node.

The 14-slot certification gap is separate:

$$G=\left\lceil\frac{3L_{\mathrm{hdr}}+L_{\mathrm{vote}}+L_{\mathrm{diff}}}{\text{slotLength}}\right\rceil=14.$$

The extra seven-second $L_{\mathrm{diff}}$ period is intended for subsequent vote and certificate diffusion; it does not extend the local voting deadline beyond seven seconds. Consequently it cannot rescue these `tooLate` votes.

This single-node capture cannot evaluate the worst-case, stake-coverage inequalities

$$L_{\mathrm{diff}} \ge \Delta_{\mathrm{EB}}^{W}+\Delta_{\mathrm{reapply}}-\Delta_{\mathrm{RB}}-3L_{\mathrm{hdr}}-L_{\mathrm{vote}}$$

or

$$\Delta_{\mathrm{EB}}^{W}<3L_{\mathrm{hdr}}+L_{\mathrm{vote}}+L_{\mathrm{diff}}+(\Delta_{\mathrm{RB}}-\Delta_{\mathrm{applyTxs}}).$$

Those require multi-node measurements of EB delivery across stake, certificate timing, and Ranking Block (RB) processing. Nor can one receiver establish the header-diffusion coverage assumed by $3L_{\mathrm{hdr}} \ge 3\Delta_{\mathrm{hdr}}$.

#### What the capture cannot diagnose

The traces identify the missed stage and report applied versus reapplied transaction counts, but they do not contain an explicit validation-start event, per-transaction durations, ledger-rule/script timing, CPU scheduling and saturation, garbage-collection pauses, disk I/O, or the cost of verbose tracing. The four late-acquisition cases can be followed through fetch requests and responses, but this receiver alone cannot distinguish remote withholding or sender congestion from network-path and local-fetch effects.

Useful additional instrumentation is: explicit validation start/finish and voting-queue residence traces; separate accumulated durations for `applyTx` and `reapplyTx`; runtime CPU and garbage-collection statistics over the same interval; and peer-keyed request/first-byte/completion timestamps for the late-acquisition cases.

### Certified-closure transaction work: validation reuse is implemented; antichain application is not

**Layer:** pinned node implementation (`ouroboros-consensus@b56977b`) compared with two upstream analyses. The [constraint model](https://github.com/input-output-hk/ouroboros-leios/tree/main/post-cip/constraint-model) is an optimization model, and the [DeltaQ preliminaries](https://github.com/input-output-hk/ouroboros-leios/blob/main/analysis/deltaq/linear-leios-preliminaries.md) explicitly describe their Petri nets as approximate. Neither describes the current node architecture by itself.

#### Result

The prototype implements the principle that expensive, transaction-intrinsic validation should not be repeated when an Endorser Block (EB) closure is finally adopted, but it does not implement the constraint model's directed-acyclic-graph (DAG) scheduler for parallel ledger application.

| Proposed principle | Pinned implementation |
|---|---|
| Check signatures once | **Yes, with scope qualifications.** During voting, a `LeiosTxCache` validated tag licenses `reapplyTx`, which repeats state-dependent checks but skips full validation. A cache miss uses `applyTx`. When a certified closure is later adopted, `ValidateNone` performs no signature validation. “Once” means once in a node's reusable validation lineage, not once network-wide: independent committee members must validate, and a node may validate again after loss or absence of the cache evidence. |
| Check Plutus once | **Yes, with the same qualifications.** Cached voting reapplication does not repeat script evaluation, and certified application uses `ValidateNone`; the source explicitly says that no script is evaluated on that path. A voting node nevertheless performs full validation on an unvalidated transaction, including checking that the transaction's declared script-validity flag agrees with evaluation. |
| Apply independent transactions in parallel according to DAG antichains | **No.** Voting's `goValidate` recursion and certified adoption's `foldM (applyOne env)` both pass the state produced by one transaction to the next. The process is serial even though the node has many other concurrent threads. There is no runtime transaction-DAG construction or antichain scheduler on either path. |
| Check transaction-input existence massively in parallel | **Only a storage-side precursor exists.** Before certified application, `resolveAndApplyLeiosClosure` unions the closure's transaction key sets and performs one batched `readValues`; voting similarly resolves the needed ledger-table values in a batch. Transaction application and its state-dependent checks are still serial. Certified adoption trusts the certificate and therefore does not independently validate input existence, but it still reads the values needed to construct the resulting ledger state and its table diff. |

📊 **EVIDENCE:** [`validateEbClosure`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosVoting.hs#L1981-L2160) documents and implements full `applyTx` on a cache miss, `reapplyTx` on a validated hit, and serial recursion. [`applyLeiosClosure`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus-cardano/src/shelley/Ouroboros/Consensus/Shelley/Ledger/Leios.hs#L158-L218) serially folds the closure through the ledger `LEDGER` rule with `ValidateNone`; its comment confirms that no script is evaluated. [`resolveAndApplyLeiosClosure`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/Ouroboros/Consensus/Storage/LedgerDB/Forker.hs#L948-L985) performs the batched key read before that fold. The same source states the trust boundary: a non-voting follower trusts the certificate's committee quorum rather than repeating the committee's checks.

#### What the constraint and DeltaQ models establish

The constraint model schedules separate verification, initial application, and final reapplication tasks. It permits verification as soon as a transaction arrives, initial application after the transaction and all ancestors are available, and reapplication after the transaction's own initial application and its parents' reapplications. This demonstrates a possible schedule under the model's assumptions; it is not evidence that the node uses that schedule. Its implementation constructs graph edges only from each scenario transaction's `inputs` list, so the modeled partial order is specifically an Unspent Transaction Output (UTxO) dependency graph.

The DeltaQ analysis assumes that certified reapplication is cheaper than full transaction application and identifies `Delta_reapply < Delta_applyTxs` as a security constraint. That matches the prototype's decision to use `ValidateNone` at certified adoption. The document also says that its ledger-update Petri net omits possible parallelism; it neither specifies nor verifies an antichain implementation.

#### Reward accounts and other non-UTxO dependencies

Reward *calculation* is not the immediate obstacle. That work is associated with epoch processing, whereas this path applies ordinary transactions in a certified closure. Reward-account **withdrawals**, however, are transaction effects and can create dependencies outside a graph built only from transaction inputs. Two transactions that touch the same reward credential cannot safely be treated as independent merely because their UTxO inputs are disjoint.

The same incompleteness applies to other ledger substate touched by transactions: stake-credential and pool certificates, delegation state, deposits and refunds, governance votes and proposals, treasury donations, fees and accounting pots, minting, collateral, and reference inputs. Some effects may commute or be reducible in parallel; others conflict or depend on the prior state. A sound scheduler therefore needs conservative read/write sets over the whole ledger transition, not only ancestry between spent and created UTxOs, plus a deterministic commit order and a fallback for conflicts. The constraint model's input-only DAG does not establish that this is safe for arbitrary Dijkstra transactions.

❓🤖 **SCRUTINY:** Non-UTxO state is a real limitation of the input-only model, but the source does not show that it is the reason the prototype remains serial. The immediate implementation reason is simpler: both paths call existing ledger APIs in a sequential fold. Determining the attainable parallelism for representative Dijkstra workloads requires extending the dependency extractor to all ledger read/write sets and measuring antichain width, span, conflicts, and scheduling overhead. The current Musashi trace has no instrumentation for those quantities.

### Prior proposal: bound transaction-DAG span with a protocol parameter

**Provenance:** Brian W. Bush reports that he proposed this idea in 2025. No contemporaneous proposal or discussion record has yet been linked here, so its historical reception is not independently verified.

The proposed parameter would bound the longest chain of transaction dependencies admitted in one ledger-application batch: a valid block or Endorser Block (EB) closure could not contain more than the configured number of successively dependent transactions. Unlike byte, transaction-count, execution-unit, and reference-script limits, this would place a direct consensus bound on the directed-acyclic-graph (DAG) span and hence on the irreducibly serial portion of an antichain-based application schedule.

This proposal is especially relevant to the post-CIP constraint model's result that the critical path can bind while CPUs remain idle. More cores cannot shorten a deliberately deep chain; an admission bound can. It would also prevent an otherwise size-valid closure from concentrating its work into a worst-case dependency chain. The bound would not by itself make parallel ledger application safe: a complete design still needs to account for conflicts through reward withdrawals, certificates, delegation, governance, deposits, collateral, reference inputs, and other ledger state that is absent from an input-only DAG.

Several details would need specification before such a parameter could be enforced: whether span counts transaction vertices or dependency edges; whether the relevant batch is the EB alone or the announcing Ranking Block (RB) plus EB closure; how dependencies on the preexisting ledger are represented; whether non-UTxO conflicts add ordering edges; and how malformed or double-spending candidate closures are handled while computing the bound. The cost is a new validity restriction that can delay legitimate long transaction chains across blocks, in exchange for a governable worst-case processing-latency bound.

📊 **EVIDENCE:** As of 2026-09-23, no such parameter or admission check appears in the pinned Dijkstra [`PParams`](https://github.com/IntersectMBO/cardano-ledger/blob/1587f21a7d1306dc590c2749a5c66232ef66aad0/eras/dijkstra/impl/src/Cardano/Ledger/Dijkstra/PParams.hs#L199), the prototype's nine-parameter Leios set, the [ledger implementation ticket's parameter list](https://github.com/IntersectMBO/cardano-ledger/issues/5965), or the [post-CIP constraint model](https://github.com/input-output-hk/ouroboros-leios/tree/main/post-cip/constraint-model). The constraint model measures span but does not constrain transaction admission with a protocol maximum. Repository and web searches found no public proposal under obvious “DAG span,” “transaction-chain depth,” or “maximum depth” terminology.

❓ **SCRUTINY:** The supported conclusion is that the proposal has not been incorporated into the public specification, current protocol-parameter set, constraint model, or prototype. Absence from those sources does not establish that the idea was never considered in an unindexed meeting, chat, or differently named analysis.

### Public-chain evidence for voting failures and certificate aggregation policy

**Layer:** canonical Musashi chain data, kleioscan's public chain index plus its separately collected off-chain vote observations, and pinned node implementation (`ouroboros-consensus@b56977b`). These sources must not be conflated: individual votes are network messages, not ledger records.

#### What canonical history can establish

Each Ranking Block (RB) exposes its slot, producer, ordinary body characteristics, and any Endorser Block (EB) announcement hash and encoded reference-body size. Joining an announcing RB to its immediate canonical successor establishes the slot gap and whether that successor carried a certificate. This permits two useful outcome classes:

1. **Structurally skipped:** the successor arrived before the implementation's certification-gap guard allowed certification. With the deployed 14-slot gap and the prototype's off-by-one guard, a successor at an elapsed distance of 14 slots or less cannot certify.
2. **Eligible but uncertified:** the successor arrived after the guard, but carried no certificate. This is the chain-visible residual of interest, but it is not synonymous with “voting failed.” It can also mean that the successor's producer lacked the complete closure, lacked a locally assembled certificate despite a quorum elsewhere, was on a different transient view, or encountered an implementation failure.

For certified EBs, the indexed ledger contains the applied closure transactions. Their sizes, scripts, inputs and outputs can be mined, and their Unspent Transaction Output (UTxO) dependency directed acyclic graph (DAG), span, width, and transaction mix can be reconstructed. The certificate exposes the aggregate signature and signer bitfield, which can be joined to committee stake.

For skipped EBs, canonical history retains only the announcement hash and size, not the off-chain EB body or its closure transactions. Consequently the public chain alone cannot recover transaction sizes, Plutus mix, cache overlap, validation cost, or DAG shape for the very closures whose votes may have failed. A transaction later appearing elsewhere does not prove that it belonged to the skipped EB because the announcement contains only the EB hash, not its transaction-reference list. Recovering those characteristics requires retained LeiosDb contents or contemporaneous network/node telemetry.

The public [kleioscan Leios-block endpoint](https://kleioscan.com/api/musashi/leios/blocks?limit=50) adds a valuable but non-chain field, `live_vote_pct`, which its user interface explicitly labels “Off-chain votes for the EB announced by this block.” In a 2026-09-23 check, 46 of the 47 announcements in the latest 50 Leios-bearing blocks had this field. This enables a stronger observational study of eligible-but-uncertified announcements, but the value is one observer's received-vote view: it does not prove what the eventual successor's producer received, and its historical coverage and collection topology need documentation before inferential use.

A defensible first analysis would join every announcement to its successor; stratify structural skips from eligible-but-uncertified cases; regress certification and observed vote percentage against announcement size, slot gap, producer, epoch, and time; and use retained node traces to explain a matched subset. Closure-level transaction/DAG characteristics can be analyzed only for certified EBs or skipped EBs whose off-chain bodies were independently archived. This produces correlations and candidate mechanisms, not a direct census of vote-failure reasons.

#### Certificates are aggregated aggressively and then frozen

📊 **EVIDENCE:** [`LeiosVoteState.addVote`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosVoteState.hs#L79-L179) maintains a running stake-weight tally and calls `aggregateLeiosCert` on the first accepted vote for which `totalW >= threshold`. It stores that certificate in `psCert`; later votes update the voter map and tally but reuse the existing certificate rather than rebuilding it. [`decideLeiosCertify`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus-diffusion/src/ouroboros-consensus-diffusion/Ouroboros/Consensus/NodeKernel/Forge.hs#L288-L356) later queries this cached certificate when an eligible successor is forged.

Thus aggregation is aggressive, not conservative: each node independently assembles a certificate as soon as the votes *that node has received* first cross the stake threshold. It does not wait for all committee votes or for the vote window to close. Certificate inclusion is nevertheless delayed until an eligible direct-successor forging opportunity after the minimum gap.

This policy sharply limits chain inference about failures. A signer absent from the on-chain certificate may have voted successfully but arrived after the aggregating node crossed quorum; the bitfield is the first threshold-crossing subset in that node's arrival order, not the complete voter set. On 2026-09-23, 15 of 19 certificates in kleioscan's latest-50-Leios-block sample had displayed signed stake of 75%, and the remaining four displayed 76–78%, consistent with a 75% threshold plus the discrete weight of the crossing vote. The source code, rather than this rounded observation, is the decisive evidence.

### Transaction availability for routine voting versus local forging

**Layer:** deployed Musashi node trace interpreted against the pinned implementation. **Capture:** [`musashi-bp.log.gz`](./musashi-bp.log.gz), SHA-256 `87bffbb5726e70dbf96b91d358951aeb1369175b34231454ab045bf39990a192`, node image `prototype-2026w36@sha256:0df972de2193f9299af4df409fde2b7ea56188ddfe2c3b77aa661e23b226a566`, consensus `b56977b`.

The unit below is an EB transaction **reference occurrence**, not a distinct transaction hash. A transaction referenced by several EBs is counted once per EB. `LeiosBodyHits` measures availability when the EB body is processed, before later voting validation. Its mempool and transaction-cache counts overlap, so adding their published percentages would double-count transactions present in both places. The implementation defines `missedBoth` as the references in neither store and uses precisely that set to construct network-fetch jobs ([`LeiosDemoLogic.hs`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosDemoLogic.hs#L961-L1034)). The disjoint counts below use `both = acquired + mempoolHits + missedBoth − txsInEb`, `mempool only = mempoolHits − both`, and `cache only = txsInEb − mempoolHits − missedBoth`; every row sums back to `txsInEb`.

| Population | EB bodies | References | Mempool only | Mempool + cache | Cache only | Neither → actively fetched |
|---|---:|---:|---:|---:|---:|---:|
| All received EB bodies in the capture | 994 | 2,094,231 | 519,840 (24.82%) | 647,412 (30.91%) | 364,855 (17.42%) | 562,124 (26.84%) |
| Closures that completed routine voting validation | 293 | 610,924 | 164,341 (26.90%) | 215,543 (35.28%) | 69,900 (11.44%) | 161,140 (26.38%) |

📊 **EVIDENCE:** For the 293 closures actually validated for voting, 379,884 references, or **62.18%**, were in the mempool. After adding cache-only availability, 449,784, or **73.62%**, were already local. The remaining 161,140, or **26.38%**, were in neither and generated active fetch work. The resulting validation trace reports 448,143 `reapplyTx` operations (73.35%) and 162,781 full `applyTx` operations (26.65%). The near match between local availability and reapplication is expected but not an identity: availability is sampled at body processing, while a transaction can acquire reusable validation evidence before the closure is later validated.

#### Local forging is a different path

The capture contains four locally forged RBs, carrying five ordinary transactions in total. Public block records and local traces show that none carried a Leios certificate or an EB announcement. Therefore this capture contains **no locally forged EB and no locally forged CertRB**, so there is no forging-specific EB fetch or closure-validation sample to compare statistically with routine voting. The five ordinary RB transactions came from the node's already validated mempool; block forging did not actively fetch them.

More generally, the implementation has no special “validate an EB immediately before forging” path:

- To forge a TxRB with an EB, it selects the EB transactions from its own mempool. The locally forged-body trace deliberately attributes every non-cache transaction to the mempool and records `missedBoth = 0`; the forge does not fetch ([`LeiosDemoLogic.hs`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosDemoLogic.hs#L198-L212)).
- To forge a CertRB, the node requires the closure and a locally assembled certificate to exist already. It does not fetch at forge time, and certified ledger application uses `ValidateNone` rather than repeating transaction signature or Plutus validation.

Thus “routine voting validation” accounts for the 26.38% active-fetch result. “Validation prior to forging” is not a second measured category in this capture—and, architecturally, forging consumes prior mempool, fetch, vote, and certificate work instead of initiating an analogous validation pass.

### Clarification: EBs announced by the parent of a locally forged block

The intended comparison is not the transactions placed into this node's own RB. It is the acquisition and voting-validation work for an EB announced by the canonical parent RB that this node is about to extend. Such work would occur earlier through the ordinary acquisition/voting path and could be labeled retrospectively as “parent EB before local forge”; forging itself still does not initiate a second closure-validation pass.

The four local forging events in this capture provide no examples of that cohort:

| Locally forged block | Local slot | Parent block | Parent slot | Slot gap | Parent announced an EB? |
|---:|---:|---:|---:|---:|---|
| 63,319 | 1,407,954 | 63,318 | 1,407,950 | 4 | No |
| 63,669 | 1,418,158 | 63,668 | 1,418,115 | 43 | No |
| 63,764 | 1,421,691 | 63,763 | 1,421,682 | 9 | No |
| 63,779 | 1,422,484 | 63,778 | 1,422,459 | 25 | No |

📊 **EVIDENCE:** The local `TraceForgedBlock` events identify each new block and parent hash; kleioscan's canonical block records identify the matching parent and report `eb_announcement_hash = null` for all four. Therefore the sample size for “transaction availability while validating the parent EB before this node's forge” is **zero**, and no fraction can yet be estimated. The previously reported 62.18% mempool / 11.44% cache-only / 26.38% fetched split remains the routine-voting baseline only.

When a suitable event eventually occurs, the correct join is: local `TraceForgedBlock.blockPrev` → parent RB hash → parent EB announcement hash → that EB's `LeiosBodyHits` and `LeiosEbValidated`. If the node was a committee voter, this recovers its earlier validation cohort; at forge time [`decideLeiosCertify`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus-diffusion/src/ouroboros-consensus-diffusion/Ouroboros/Consensus/NodeKernel/Forge.hs#L288-L356) merely requires the minimum gap, local closure, and cached certificate. If the node did not validate as a voter, it may still forge using a received certificate and apply the closure with `ValidateNone`.

### Clarification: active transaction fetching is strongly associated with `tooLate`, but its direct latency is not isolated

This clarifies the earlier [`tooLate` diagnosis](#toolate-vote-diagnosis-closure-validation-dominates-with-acquisition-and-serial-worker-tails). The phrase “cache-cold” compressed two different observations: a transaction can be absent from both the transaction cache and mempool, requiring a network fetch, and it can lack reusable validated evidence, requiring full `applyTx`. These usually coincide in this capture but are not logically identical.

**Layer and capture:** deployed Musashi trace, using the same capture and source pin identified above. `Consensus.LeiosKernel.BodyHits.missedBoth` is the number of an EB's transaction-reference occurrences found in neither the local transaction cache nor the mempool when the body is processed. The implementation uses exactly this set to create transaction-fetch jobs ([`LeiosDemoLogic.hs`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosDemoLogic.hs#L961-L1034)). Events were joined by `ebHash`.

| Voting outcome | EBs | Transaction references | `missedBoth` → actively fetched | Median per-EB fetched share | Full `applyTx` |
|---|---:|---:|---:|---:|---:|
| Voted successfully | 270 | 548,504 | 113,391 (20.67%) | 8.88% | 114,900 (20.95%) |
| Validated, then `tooLate` | 23 | 62,420 | 47,749 (76.50%) | 80.09% | 47,881 (76.71%) |

📊 **EVIDENCE:** Closures whose validation finished too late had a much larger actively fetched share than successful closures. Treating each EB, rather than each transaction reference, as an observation, a one-sided Mann–Whitney comparison of the fetched fractions gives $U=5{,}856$ and $p=1.89\times10^{-13}$. Within the 23 late validations, `missedBoth` and full-application counts are nearly identical in aggregate and strongly rank-correlated ($\rho=0.997$). This is expected from the implementation: newly fetched transactions normally lack the trusted validation evidence needed for `reapplyTx`, so availability misses create subsequent full-validation work.

This does **not** establish that bytes in flight directly consumed most of the deadline. All 23 closures in the second row completed acquisition by +3.428 seconds relative to the announcing slot, before the +7-second voting deadline; the late terminal event came after serial ledger validation. Four other `tooLate` cases did not complete closure acquisition until after +7 seconds, so direct acquisition delay is an observed secondary mechanism. However, `BodyHits` describes availability for the announced EB at one instant rather than timing each request and every closure component. The trace lacks per-transaction request, first-byte, completion, and validation-duration events. It therefore cannot partition elapsed time into network transfer, peer service, local fetch scheduling, and ledger validation.

❓🤖 **SCRUTINY:** The supported conclusion is an association with a source-grounded mechanism: active fetch misses are strongly concentrated among validation-late closures, and those misses normally force full validation. Closure size, transaction mix, machine load, and cache state are confounded in this one-node observational sample, so it is not a causal estimate of fetch latency. The earlier conclusion remains valid only when “cache-cold” is understood primarily as absence of reusable validation evidence, not as proof that network transfer itself exhausted the four-second validation window.

### Fetching and voting validation are staged, not interleaved

**Layer:** pinned node implementation (`ouroboros-consensus@b56977b`). Network fetch responses can arrive in separate jobs and from concurrent peer protocol threads. Each accepted response is checked and its transaction batch is inserted immediately into LeiosDb and the transaction cache as `Unapplied`. Thus acquisition is incremental at the storage layer; it does not wait to write one monolithic response.

Validation for a particular Endorser Block (EB), however, does not consume that partial stream. LeiosDb emits `AcquiredEbTxs` only when insertion makes an entire closure complete. `runLeiosVoting` ignores the earlier body-only `AcquiredEb` notification and creates a vote timer only upon `AcquiredEbTxs`. When the timer fires, `validateEbClosure` resolves the whole closure from LeiosDb, gathers all required ledger-table keys, decides the cache status of every transaction, and only then enters its serial `goValidate` recursion. No fetch is awaited or initiated inside that recursion.

Consequently, “does fetching block?” has three distinct answers:

- **It gates this EB's validation:** yes. One missing transaction prevents the whole-closure notification, so no validation work for that EB starts. Completion after the +3-second window opening schedules the vote immediately; completion after the +7-second deadline produces `tooLate` before validation.
- **It synchronously blocks the voting worker while bytes arrive:** no. The voting loop has no partially complete EB task to wait on; fetch runs elsewhere and the loop can process notifications and other due votes. Once it starts `goVote`, though, its serial validation blocks that one voting loop and can create head-of-line delay for other complete closures.
- **It overlaps fetch of later pieces with application of earlier pieces of the same closure:** no. The source explicitly marks streaming validation as a TODO. It also marks validating immediately upon whole-closure arrival as a separate, simpler TODO; currently even an early-complete closure waits until the +3-second vote-window opening before validation begins.

📊 **EVIDENCE:** [`processLeiosBlockTxs`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosDemoLogic.hs#L1269-L1407) incrementally ingests fetched jobs and traces closure completion only for points returned by `leiosDbInsertTxs`. [`runLeiosVoting`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosVoting.hs#L245-L357) acts only on `AcquiredEbTxs`, and [`validateEbClosure`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosVoting.hs#L416-L503) first resolves and classifies the entire closure before serial application. The source comments identify validation while streaming and validation immediately at closure completion as unimplemented alternatives ([`LeiosVoting.hs`](https://github.com/IntersectMBO/ouroboros-consensus/blob/b56977baae0740f563060a8a9171c78be865b357/ouroboros-consensus/src/ouroboros-consensus/LeiosVoting.hs#L119-L132)).

### Cross-language check: serial closure application is not specifically a Haskell artifact

**Hypothesis:** whole-closure blocking, lack of directed-acyclic-graph (DAG) antichain processing, and use of a fold in the Haskell prototype arise because its authors prefer pure functional programming.

**Assessment:** weakly supported at most, and contradicted as a language-level explanation. The implementation choices can reflect the existing Haskell ledger API and a preference for a simple deterministic state transition, but neither purity nor Haskell requires serial evaluation. Pure transaction-intrinsic checks are particularly amenable to parallel execution. The stronger explanations are prototype maturity, reuse of an existing sequential ledger transition, the need to preserve deterministic state-dependent semantics, and the absence of a complete read/write conflict model for non-Unspent-Transaction-Output (non-UTxO) ledger state.

#### Blink Labs Dingo in Go

**Source snapshot:** [`blinklabs-io/dingo@cde295a9`](https://github.com/blinklabs-io/dingo/tree/cde295a9c9685b1a99d2dd9355fbccaeb472ad7d), 2026-09-23, plus its wire-protocol library [`blinklabs-io/gouroboros@8c8901c4`](https://github.com/blinklabs-io/gouroboros/tree/8c8901c4039e6bee5dc31b2c6768a72e4c4cfc9c).

Dingo encodes substantial coarse-grained concurrency. Leios offers dispatch fetch work onto goroutines; different connections can fetch concurrently; historical EB backfills are dispatched concurrently; manifest and transaction persistence is moved to a background writer; and vote and pipeline managers each have their own event loop. One connection remains strict request/response: a per-connection mutex serializes its fetch operations, with at most four queued or running goroutines. Within one EB fetch, requests proceed in serial rounds, each requesting at most eight 64-transaction bitmap windows. Returned transaction bodies are hash/size/envelope checked individually as they arrive and partial progress is retained.

This is not transaction-ledger parallelism. Dingo's optional DAG mempool records UTxO parent/child relationships and maintains a deterministic topological order, but its own documentation says the DAG changes ordering and selection, not validation. Certified closure application decodes transactions in a `for` loop, builds a `LedgerDelta`, and applies the delta through another `for` loop over transactions inside one database transaction. There is no antichain executor.

More importantly, Dingo is not a valid performance comparison for the Haskell vote-validation path. A slot-verified EB manifest is published even when its transaction set is incomplete; publication calls `VoteManager.HandleEndorserBlock`, which may sign once the corresponding ranking-block announcement is known. The vote path checks timing, committee membership, keys, and signing, but performs no transaction ledger validation. Fetched transaction checks bind bytes to manifest references; they do not establish ledger validity. Thus Dingo avoids Haskell's pre-vote closure-validation bottleneck by currently omitting that work, not by parallelizing it. This is an implementation-completeness/conformance gap that would need resolution before using Dingo to estimate attainable vote latency.

📊 **EVIDENCE:** Fetch dispatch and serialized-per-connection admission are in [`leiosnotify.go`](https://github.com/blinklabs-io/dingo/blob/cde295a9c9685b1a99d2dd9355fbccaeb472ad7d/ouroboros/leiosnotify.go#L1017-L1450). [`storeLeiosEndorserBlock` and `publishLeiosEndorserBlock`](https://github.com/blinklabs-io/dingo/blob/cde295a9c9685b1a99d2dd9355fbccaeb472ad7d/ouroboros/leios_merged.go#L505-L700) show publication without a complete-closure condition, and [`HandleEndorserBlock`](https://github.com/blinklabs-io/dingo/blob/cde295a9c9685b1a99d2dd9355fbccaeb472ad7d/ledger/leios/manager.go#L2381-L2510) reaches vote signing without transaction validation. [`applyEndorserBlock`](https://github.com/blinklabs-io/dingo/blob/cde295a9c9685b1a99d2dd9355fbccaeb472ad7d/ledger/leios_apply.go#L151-L298) and [`LedgerDelta.applyWithDonationRecording`](https://github.com/blinklabs-io/dingo/blob/cde295a9c9685b1a99d2dd9355fbccaeb472ad7d/ledger/delta.go#L147-L230) are sequential. The [`transactionDAG`](https://github.com/blinklabs-io/dingo/blob/cde295a9c9685b1a99d2dd9355fbccaeb472ad7d/mempool/dag.go#L24-L160) is an ordering index rather than an executor.

#### Amaru in Rust

**Source snapshot:** [`pragma-org/amaru@5a2a08bc`](https://github.com/pragma-org/amaru/tree/5a2a08bc7ad2bd23367dfcf1d06c71cb2a7e96cd), 2026-09-22. No public Leios implementation exists on that main branch. Its block-forging architecture record explicitly describes votes, announcements, and EB handling as future independent processes. The only public branch with “Leios” in its name is [`rk/leios-workshop@12a7aded`](https://github.com/pragma-org/amaru/tree/12a7adedf087666566a87cd44367ae0aafe2f69c), dated 2026-03-23 and committed as “quick hack to see some leios notify protocol messages.” It implements only a LeiosNotify initiator that treats every received message as opaque bytes and logs it; it has no fetching, voting, closure validation, DAG scheduling, or certified application to compare.

Amaru's existing Praos/ledger architecture is nevertheless useful counterevidence to the language claim. It uses asynchronous pure-stage tasks for the node graph, parallel multi-peer block fetching, Rayon-parallel independent header assertions, and Rayon-parallel evaluation of the multiple Plutus scripts within one transaction. In contrast, all ledger requests go through one dedicated operating-system thread; block validation iterates transactions serially because each successful transaction mutates the context seen by the next. Amaru therefore parallelizes operations its authors have modeled as independent while retaining a serial transaction state transition. Rust did not by itself produce a transaction-antichain executor.

📊 **EVIDENCE:** [`BlockValidator`](https://github.com/pragma-org/amaru/blob/5a2a08bc7ad2bd23367dfcf1d06c71cb2a7e96cd/crates/amaru-consensus/src/block_validator.rs#L125-L170) states that all ledger operations execute sequentially on one thread. [`validate_block`](https://github.com/pragma-org/amaru/blob/5a2a08bc7ad2bd23367dfcf1d06c71cb2a7e96cd/crates/amaru-ledger/src/rules/block.rs#L220-L335) loops over transactions, while [phase-two execution](https://github.com/pragma-org/amaru/blob/5a2a08bc7ad2bd23367dfcf1d06c71cb2a7e96cd/crates/amaru-ledger/src/rules/transaction/phase_two/mod.rs#L180-L240) uses `into_par_iter` for scripts. Header assertions are also [Rayon-parallel](https://github.com/pragma-org/amaru/blob/5a2a08bc7ad2bd23367dfcf1d06c71cb2a7e96cd/crates/amaru-consensus/src/validate_header.rs#L80-L95). The workshop branch's entire Leios surface is [`leios_notify.rs`](https://github.com/pragma-org/amaru/blob/12a7adedf087666566a87cd44367ae0aafe2f69c/crates/amaru-protocols/src/leios_notify.rs).

#### Conclusion

The comparison rejects the strong form of the hypothesis. All three codebases use concurrency for independent protocol work, and both implemented ledgers examined here serialize transaction state changes. Go Dingo demonstrates more aggressive fetch concurrency but does not yet perform the closure validity work required before a sound vote. Rust Amaru demonstrates that a purity-oriented stage architecture can explicitly exploit data parallelism, but it has not implemented Leios and keeps its ordinary transaction sequence serial.

The Haskell prototype's specific decision to wait for the entire closure and then validate it inside the four-second voting window is a remediable prototype architecture choice. The lack of antichain ledger application is a deeper cross-language design gap: implementing it safely requires consensus-defined ordering semantics, complete read/write sets spanning UTxO and non-UTxO state, deterministic conflict handling and commit, reusable validation evidence, and resource bounds. Changing languages or replacing `foldM` with parallel syntax does not supply those properties.

## 2026-09-24

### Block-producer health is good, while fresh Leios traffic has stopped

**Layer:** deployed Musashi node telemetry. **Capture:** [`musashi-bp.log.gz`](./musashi-bp.log.gz), 39,984,816 bytes, SHA-256 `ea034eca903984b0e9f65b3ac128ee2ebcb0c2d103bb08a983e6662065db81d3`, covering 2026-09-22 13:29:59.581 UTC through 2026-09-24 10:23:52.002 UTC. The capture contains one process startup and no restart. The configured image remains `prototype-2026w36`; the source pin used for trace interpretation remains `ouroboros-consensus@b56977b`.

#### Ranking-block production

📊 **EVIDENCE:** The producer performed exactly 21,600 consecutive leadership checks, with no slot gap, in each complete epoch 64 through 68. The observed block counts were 0, 4, 2, 3, and 5, totaling 14. Using the recorded stake snapshot and active-slot coefficient gives an expectation of 3.0395 blocks per epoch, or 15.1975 across the five epochs. The observed-to-expected ratio is 0.9212; its exact 95% confidence interval is [0.5036, 1.5456], and the exact two-sided Poisson rate-test p-value is 0.8911. The fixed-rate and total-conditioned Monte Carlo dispersion tests give p = 0.4011 and p = 0.3082. These data show no production-rate anomaly, but five epochs remain too few for a sensitive test. Epoch 69 was partial at capture end and had produced one additional block, so it is excluded from the rate test.

Every one of the 15 `NodeIsLeader` events in the capture was followed by `ForgedBlock` and `AdoptedBlock` for the same slot and hash. Time from leader detection to forge ranged from 0.365 to 3.530 ms, with a 1.439 ms median; time to local adoption ranged from 5.897 to 53.614 ms, with a 31.785 ms median. There is no `CannotForge`, KES failure, invalid-block, or ledger-validation error. The node continued adding chain blocks through 10:22:46 UTC, one minute before its final leadership check. Peer churn produced 462 error-severity status-change or monitoring events over approximately 45 hours, but these did not interrupt leadership checking, chain growth, or successful local adoption.

Reproduce the complete-epoch rate analysis with:

```shell
python3 ./analyze-block-production.py --log musashi-bp.log.gz --first-epoch 64 --last-epoch 68 --stake 1009497788035 --total-active-stake 367948233779128 --simulations 200000 --seed 20260924
```

The stake values are the recorded snapshot used in the earlier analysis. Re-querying the current snapshot would be necessary before treating 3.0395 as the expectation for later epochs.

#### Leios voting is no longer receiving current work

📊 **EVIDENCE:** The last fresh accepted Endorser Block (EB) announcement was for slot 1,393,469 at 2026-09-23 03:04:29.659 UTC. Its closure was acquired, validated, and voted by 03:04:32.744, and the associated vote/certificate traffic ended seconds later. The log contains no later `AnnouncementAccepted`, `BlockTxsAcquired`, `VoteScheduled`, `EbValidated`, or `Voted` event. Consequently, the expanded capture adds no new sample to the earlier 270 votes and 28 eligible-period `tooLate` outcomes, and it cannot show whether the previous `tooLate` rate improved or worsened.

LeiosNotify did not become entirely silent. In epochs 65, 66, 68, and partial 69, the node received 289 announcements whose EB slots ranged from 467,154 to 1,335,015, all far behind the contemporaneous chain slots of 1,404,000 or later; none was accepted. These appear to be historical announcements from lagging or previous-incarnation peers rather than current Leios work. At the same time, transaction load collapsed from 297,041 mempool-add events in epoch 64 to 1,200, 1,015, 1,024, and 49 in epochs 65–68. That correlation is consistent with the network load generator or current EB producers stopping, but this single receiver does not establish the cause.

❓🤖 **SCRUTINY:** The node is healthy as a Praos ranking-block producer, and its production count agrees with the recorded stake expectation. Its present Leios voting performance is unknown because fresh Leios inputs stopped more than 31 hours before capture end. The absence of accepted current announcements is evidence about what reached this node, not proof of a network-wide outage or a fault in any particular producer. A second current node trace or public explorer history would distinguish a network/workload cessation from an isolated topology problem. This environment could not query the live pod directly because rootless Podman namespace setup was denied, so the assessment ends at the capture timestamp rather than asserting current process liveness after 10:23:52 UTC.
