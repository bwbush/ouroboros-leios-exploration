# Mempool plausibility: candidate workstreams after the 2026-09-21 brainstorm

**Provenance:** ⏳🤖 LLM-generated, pending human review · **Recorded:** 2026-09-24 · **Status:** scope-discovery candidates, not commitments

## Decision context

Brian Bush and Will Wolff expect to choose roughly three tasks for the next two or three months, with research, experiments, and assessment as the center of gravity and only light prototyping in support. The two implementation-heavy ideas discussed separately — moving reusable validation work out of the vote-critical path and investigating a transaction-antichain ledger executor — remain important but are **parked for this round of scoping**. They are not rejected.

The [2026-09-21 brainstorm record](../journal/phase-0.md#scope-brainstorm-with-sebastian-nagel-and-william-wolff-four-horizons-nothing-selected-yet-) names the short-term question as the plausibility of different severities of memory-pool fragmentation, especially its tail, together with attack economics and mitigation. The [Monday working-session notes](https://docs.google.com/document/d/11-FYWpDyeyBgUHXuQz-7td6B3OSmAh9bXbxNYwwpuCY/edit) do not discuss memory pools directly; they concern vote diffusion. Their relevant methodological signal is Sebastian Nagel's insistence on plausible operator conditions: compare designs at realistic topology, quorum, upstream-peer count, burst size, and bandwidth rather than at an unconstrained optimum. The same standard should govern a fragmentation study.

The Slack-derived [open-issues summary](./leios-mempool-cache-open-issues.md) sharpens the research question. The Leios team can model the consequence of an assumed fragmentation level, but has not established how much fragmentation a realistic benign workload or affordable attacker can induce. That missing map from ingress conditions and attacker resources to a fragmentation distribution is the common object of the first two candidates below.

## Provisional ranking

| Rank | Candidate | Suggested size | Why it fits now |
|---:|---|---|---|
| 1 | Semi-centralized transaction-ingress scenarios | 6–8 weeks | Directly answers the benign-plausibility question using an upstream model that already identifies uniform ingress as a limitation |
| 2 | Resource-bounded fragmentation attacks | 6–10 weeks, overlapping candidate 1 | Turns the meeting's attack-dominance intuition into a falsifiable bound and reuses the existing economic framework |
| 3 | Transaction-availability service or “supernode” assessment | 2–4 weeks as a sub-study | Potential mitigation and architecture exploration, but premature as a standalone build until the miss/fetch problem is quantified |

These sizes are ❓🤖 **SCRUTINY** estimates for one or two researchers with light prototyping, not delivery commitments.

## Candidate 1 — Semi-centralized transaction-ingress scenarios

### Research question

How do realistic concentrations of transaction submission change memory-pool overlap, propagation tails, and the fraction of an Endorser Block (EB) closure that a voter must actively fetch, compared with the existing uniform-random-injection baseline?

“Blockfrost-like” is a useful motivating example, not yet a calibrated claim about Blockfrost's internal topology. Blockfrost exposes a hosted [`POST /tx/submit`](https://github.com/blockfrost/openapi/blob/master/src/paths/api/tx/submit.yaml) service, demonstrating that many clients can enter through a small public service surface, but the public interface does not establish how many Cardano nodes receive those transactions or how the backend fans them out. The model should therefore speak of **submission gateways** and sweep their number, placement, and fan-out rather than assert a particular vendor architecture.

### Why the existing model is a good starting point

At upstream `ouroboros-leios` commit [`f65db01`](https://github.com/input-output-hk/ouroboros-leios/tree/f65db01ca1f9462241e844bd3018cc4b78d41a30/post-cip/mempool-sim-web), the TypeScript discrete-event simulator registers every transaction in one loop and independently chooses a uniform-random honest node and a uniform-random submission time. Its own model card calls both choices unrealistic and says real submissions concentrate at popular endpoints. The simulation's application programming interface (API) already accepts an explicit `SubmitTx(clock, nodeIdx, txIdx)` event, so replacing the driver is mechanically small.

The conceptual change is more important: a gateway is not necessarily a gossip node. Add an explicit layer from transaction originator → submission service → one or more Cardano ingress nodes, then let the existing offer/request/send gossip operate among Cardano nodes. Otherwise “ten gateways” and “ten nodes” become the same thing and the experiment cannot represent multihoming, provider fan-out, gateway failure, or provider-correlated placement.

### Scenario matrix

Use the current uniform-random node/time case as the baseline, then sweep:

- gateway count and concentration, from one gateway through many, with both equal shares and measured or synthetic skew;
- backend fan-out per gateway and whether clients submit redundantly through multiple providers;
- placement relative to network communities, geography, node degree, and block-producer stake;
- steady Poisson-like arrivals, diurnal variation, bursts, and correlated application events;
- heterogeneous transaction sizes and load levels around both Praos and Leios capacity;
- ordinary gossip, peer churn, partial gateway outage, and a controlled request-on-miss availability service corresponding to candidate 3.

The primary outputs should be distributions, not averages: pairwise Jaccard overlap of producer memory pools; transaction coverage across producers over time; propagation and convergence quantiles; EB closure cache/memory-pool/miss shares; duplicate fetch work; and recovery or hysteresis after a burst. The simulator's coin-flip EB certification is too stylized to support a claim about real Leios certification, so certification rate should be reported only as an internal model response unless the experiment is ported to a protocol-faithful simulator.

### Minimum model repairs before interpreting results

The simulator uses unseeded `Math.random`, a random-regular topology, identical links, negligible jitter, no bandwidth contention, instantaneous transaction validation, and a size-only memory pool. A reproducible study needs at least a seeded random-number generator, scenario files that record every parameter, and per-run provenance. A plausibility claim additionally needs heterogeneous topology and links plus shared-link contention; without those, ingress concentration is being varied in a network that systematically suppresses the congestion and tail behavior concentration may create. Ledger rules are not necessary for the benign non-conflicting first pass, but they are necessary for candidate 2's conflicting-transaction attack.

### Evidence and stopping rule

Calibrate what can be observed from the existing three-region mainnet measurements, instrumented testnets, public endpoint market information, and operator interviews; mark unobservable provider fan-out as a sweep rather than a fact. Stop after producing a response surface from ingress concentration to fragmentation and fetch demand, with uncertainty across seeds and topologies. If plausible scenarios do not materially separate from the uniform baseline, that null result is the deliverable.

## Candidate 2 — Resource-bounded fragmentation attacks

### Research question

For each stated adversary objective and budget, what is the largest fragmentation severity the adversary can plausibly sustain, and is that strategy preferable to another attack using the same access, bandwidth, stake, funds, and time?

“The strongest attack” is undefined until the objective is fixed. Throughput denial, value extraction, safety failure, and operator attrition value damage differently. The study should therefore reuse the budget-relative dominance frontier in [the economics of attack resources](../assessments/attack-resource-economics.md), estimate the fragmentation damage function rather than invent another taxonomy, and compare only attacks serving a common objective.

### Work packages

1. Parameterize an attacker's submission endpoints, admitted-peer positions, geographic placement, egress, transaction construction rate, usable funds, stake or producer eligibility, and duration. Separate capital requirements from consumed economic cost.
2. Implement safe experiment scenarios for geographically ordered conflicting transactions and network-position-driven partitioning, corresponding to the upstream threat model's T26 and T27 families. Run them first in simulation and then, if authorized, on a private or purpose-built testnet; do not treat uncontrolled mainnet disruption as an experiment option.
3. Measure the severity distribution: producer memory-pool divergence, closure misses, certification impairment in a protocol-faithful environment, persistence after the attacker stops, and cost at each intensity.
4. Compare the resulting harm/cost curve with other attacks aimed at the same outcome, including EB withholding or diffusion denial. Report a crossover budget, a domination result, or “incomparable with present evidence.”

This candidate directly addresses the opportunity-cost question: if the same position and egress cause more harm through another strategy, fragmentation does not reach the relevant dominance frontier. Conversely, a cheap conflicting-transaction mechanism or a concentration-induced tail can put fragmentation on the frontier; neither should be assumed before measurement.

### Relationship to upstream work

The open [`ouroboros-leios#1022`](https://github.com/input-output-hk/ouroboros-leios/issues/1022) already calls for colored load at each block producer and a decentralized fragmentation experiment. Open [`ouroboros-leios#1058`](https://github.com/input-output-hk/ouroboros-leios/issues/1058) specifies conflicting transactions distributed in different orders across geographic submission points. This candidate should coordinate with or analyze those experiments, not independently rebuild their load generator. Its distinctive contribution is the plausible-resource bound and cross-attack comparison.

## Candidate 3 — Transaction-availability service (“supernodes”)

### Question and narrower interpretation

Could independently operated, highly connected availability servers answer a node's request for a transaction body as soon as an EB reveals that the node is missing it, reducing reliance on finding the right gossip peer within the vote window?

This is more coherent as a **request-on-miss availability layer** than as a replacement for gossip. Nodes still need transaction announcements or EB references, ordinary memory-pool diffusion remains valuable, and every fetched body still requires hash, syntax, and ledger validation. The service changes source discovery and availability latency; it does not confer trust in transaction validity.

The current lightweight simulator already makes an optimistic approximation in this direction: on EB receipt it inspects global transaction-presence state, chooses the first upstream peer known by the simulator to have the transaction, and makes one request with no retry. A useful supernode experiment would remove that oracle and explicitly model source discovery, several independent availability services, retry and hedging policy, service storage/retention, per-client and per-peer bandwidth budgets, and failure or malicious withholding.

### Questions to settle before any build

- Does measured EB miss demand justify a separate service, or would producer serving, better hedging, or ordinary high-connectivity relays solve the same problem?
- How does a node discover which service has a content-addressed transaction without leaking its interests or trusting a centralized index?
- What prevents distributed denial of service (DDoS), request amplification, free riding, censorship, selective withholding, and eclipse by a small provider set?
- Who pays for ingress, storage, and high-peak egress, and what evidence could support a revenue model?
- How long are transaction bodies retained, and does an eventual archival role create privacy, deletion, or unbounded-storage obligations?
- Can multiple independent services be used without putting a new trusted or privileged role into consensus?

The recommended Phase-0 treatment is a short architecture and simulation sensitivity study nested inside candidate 1. Promote it to a standalone workstream only if explicit-source discovery materially reduces tail fetch latency under measured or plausible miss rates and no simpler mitigation does.

## What the security audit says about memory pools

Yes, the Anastasia Labs audit highlighted cache, fetch-ingress, and storage issues, although it was a static review of `ouroboros-consensus` revision `1820edf5` on 2026-08-31, not a statement about current source. Its findings were unresolved **at that revision**.

- **LEI-004** is directly transaction-cache-related: peer-supplied transaction hashes were not constrained to 32 bytes before the optimized cache read offsets 0–31 with `unsafeIndex`.
- **LEI-008** is adjacent storage lifecycle: the SQLite Leios database had unbounded durable retention because garbage-collection and promotion callbacks were no-ops.
- **LEI-005, LEI-006, LEI-009, and LEI-010** concern body limits, future-offer retention, decoder allocation, and poisoned authoritative body size on the same EB acquisition path. They are relevant to resource-bounded fetch and availability work even though they are not ordinary memory-pool policy findings.

The audit's LEI-004 must not be conflated with the separate open cached-validity-context problem in [`ouroboros-leios#1084`](https://github.com/input-output-hk/ouroboros-leios/issues/1084). LEI-004 is about transaction-hash representation and memory safety; #1084 is about reusing a prior validation result after epoch or protocol-parameter context changes.

## Current open GitHub surface

A title-and-body search of open issues in `ouroboros-leios`, `ouroboros-consensus`, `cardano-node`, and `cardano-ledger` on 2026-09-24 found a larger relevant surface than the Slack summary alone. The most directly relevant open issues are:

| Area | Open issue | Relevance |
|---|---|---|
| Fragmentation experiment | [`ouroboros-leios#1022`](https://github.com/input-output-hk/ouroboros-leios/issues/1022) | Colored per-producer load, visualization, and decentralized test |
| Conflicting ingress attack | [`ouroboros-leios#1058`](https://github.com/input-output-hk/ouroboros-leios/issues/1058) | Geographic submission of conflicting transactions and convergence telemetry |
| Per-transaction Leios eligibility | [`ouroboros-leios#1077`](https://github.com/input-output-hk/ouroboros-leios/issues/1077) | Prototype transaction limits and measure their value on the testnet |
| Cached validation context | [`ouroboros-leios#1084`](https://github.com/input-output-hk/ouroboros-leios/issues/1084) | Validation evidence may become stale across epoch parameter changes |
| Live cache/database consistency | [`ouroboros-leios#1111`](https://github.com/input-output-hk/ouroboros-leios/issues/1111) | Relay stopped fetching part of an EB closure and parked its chain |
| Fetch policy and availability | [`ouroboros-leios#1105`](https://github.com/input-output-hk/ouroboros-leios/issues/1105), [`#1109`](https://github.com/input-output-hk/ouroboros-leios/issues/1109), [`#1113`](https://github.com/input-output-hk/ouroboros-leios/issues/1113) | Hedging, closure streaming, and preserving request budget for fresh EBs |
| Transaction-cache capacity | [`ouroboros-consensus#2290`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2290) | Legal EB reference windows can exceed the fixed cache table; failed insertion can leak slots |
| Fetch-buffer retention | [`ouroboros-consensus#2297`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2297) | Per-peer buffers retain pointers and transaction bodies after requests |
| Memory-pool observability | [`ouroboros-consensus#1607`](https://github.com/IntersectMBO/ouroboros-consensus/issues/1607) | Missing tracers and counters across memory-pool dimensions |
| Leios memory-pool requirements | [`ouroboros-consensus#1509`](https://github.com/IntersectMBO/ouroboros-consensus/issues/1509) | An unanswered 2025 design issue written for an earlier Input Block design; open status does not establish present relevance |
| Precompute independent validation | [`ouroboros-consensus#743`](https://github.com/IntersectMBO/ouroboros-consensus/issues/743) | Parallelize ledger-independent checks before serialized memory-pool admission; relevant to the parked validation work |
| Forge-snapshot validation | [`ouroboros-consensus#568`](https://github.com/IntersectMBO/ouroboros-consensus/issues/568) | Avoid eagerly validating every transaction when forging from a snapshot; relevant to the parked validation work |
| Snapshot indexing cost | [`ouroboros-consensus#2111`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2111) | Avoid rebuilding the transaction-identifier set on every snapshot |
| Validation reuse | [`cardano-ledger#4852`](https://github.com/IntersectMBO/cardano-ledger/issues/4852) | Memoization interface for computations repeated during validation and block extraction |

Two relevant implementation changes are open **pull requests, not issues**: [`ouroboros-consensus#2308`](https://github.com/IntersectMBO/ouroboros-consensus/pull/2308) proposes lock-free memory-pool reads, and [`cardano-node#6610`](https://github.com/IntersectMBO/cardano-node/pull/6610) is the optimistic-memory-pool integration. The previously referenced [`cardano-ledger#5965`](https://github.com/IntersectMBO/cardano-ledger/issues/5965), adding Leios protocol parameters, is closed as of 2026-09-02 and should not be listed as an open implementation item.

This inventory is a scope filter, not evidence that every issue belongs in Brian and Will's work. Several are implementation defects owned by the upstream engineering team. The research-shaped gaps are the ingress-to-fragmentation map, the resource-bounded attack frontier, recovery dynamics, and the comparative value of an explicit availability service.

## Sources

- [Leios working session — 2026-09-21 — Notes by Gemini](https://docs.google.com/document/d/11-FYWpDyeyBgUHXuQz-7td6B3OSmAh9bXbxNYwwpuCY/edit) — internal meeting notes; methodological context, not a memory-pool discussion
- [Open mempool and cache issues and hypotheses](./leios-mempool-cache-open-issues.md) — internal Slack synthesis, with public GitHub cross-checks
- [Post-CIP memory-pool simulator](https://github.com/input-output-hk/ouroboros-leios/tree/f65db01ca1f9462241e844bd3018cc4b78d41a30/post-cip/mempool-sim-web) — current source and model card inspected 2026-09-24
- [Post-CIP memory-pool model dossier](./leios-simulation-model-catalog/10-postcip-mempool-models.md) — this repository's earlier source survey
- [The economics of attack resources](../assessments/attack-resource-economics.md) — budget, cost, and dominance framework
- [*Security Audit Report — Ouroboros Consensus — Leios*](../background/audit-report-20260902.pdf), Anastasia Labs v1.0, 2026-09-01 — local authorized copy; static review of revision `1820edf5`
