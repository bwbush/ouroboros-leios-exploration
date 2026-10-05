# Musashi Dojo experiment ideas

Draft issues for Brian and Will to study memory-pool (mempool) and transaction-cache fragmentation under the [agreed experiment plan](arc-leios-ha/experiment-plan.md). These are alternatives, not a committed sequence. All runs target Musashi Dojo; game-theoretic comparisons remain postponed. Requirements and plans below are tentative.

Related-work statuses were checked October 5, 2026. An open issue establishes planned work, not a completed result; a closed tooling issue does not establish performance on the deployed Haskell node. “No direct match identified” refers to the earlier review of notes and public tickets, not an exhaustive novelty claim.

For each selected experiment, pin the deployed software and parameters, record background traffic, and define the confirmation criterion used to measure settlement time. Preserve treatment/control logs and recovery observations. Node counts, duration, and cost remain to be determined unless stated otherwise.

Distinguish transaction bodies missing from both mempool and cache from missing reusable validation evidence. Measure late or absent votes against observed eligible voting opportunities; unknown outcomes remain unknown. Cache misses and failed certification do not by themselves establish settlement harm.

⏳🤖 Drafted by a large language model (LLM), pending human review.

## Experiments

### 1. Concentrated honest injection

Vary where and how quickly honest transactions enter the network, then measure mempool fragmentation and its cost.

#### Question or hypothesis

Concentrating submissions at a few ingress points may disadvantage distant participants even when total load is unchanged. This tests whether uniform injection misses an important operating condition.

#### Test and evidence

Compare uniform and concentrated injection at matched total rates. Measure cross-node mempool overlap, cache-miss rates, fetch and validation cost, late votes, and submission-to-confirmation times by origin. Relate concentration to both fragmentation and its consequences.

#### Tentative plan

Reuse the regional workload tooling. Begin with one steady load and a small concentration sweep, then increase intensity. Alternate control and treatment intervals.

#### Infrastructure

- Deployment: stock relays and submitters in separated regions; cooperating producer logs for voting outcomes.
- Changes: injection scheduler and transaction-origin tracking; no node patch initially.
- Run: allow synchronization and warm-up; duration and cost follow a pilot.

#### Related work

- [Regional fragmentation tooling](https://github.com/input-output-hk/ouroboros-leios/issues/1022) — open, assigned to `fmaste` and collaborators; direct overlap requiring coordination.
- [Leios benchmark-cluster testing](https://github.com/input-output-hk/ouroboros-leios/issues/1085) — open; provides a controlled-cluster comparator.

#### Risks and limitations

Background load and unknown peer connections may obscure the effect. Regional differences alone do not identify injection concentration as the cause.

### 2. Concentrated conflicting injection

Submit mutually exclusive transactions through different ingress points and vary how much of the workload conflicts.

#### Question or hypothesis

Conflicts may keep mempools divergent and increase cache misses, processing cost, and settlement delay beyond concentrated, independent traffic. The question is how much additional harm contention causes.

#### Test and evidence

Compare conflicting and non-conflicting workloads at matched submission rates and similar transaction sizes. Vary conflict-set size and conflicting fraction; measure mempool overlap, cache misses, revalidation cost, missed votes, and completion time for the intended user action.

#### Tentative plan

Coordinate with the existing conflict experiment and reuse its generator. Start with two arrival orderings, then vary geographic skew and conflict intensity.

#### Infrastructure

- Deployment: distributed submitters and stock relays; cooperating producer telemetry.
- Changes: conflict-set generation, submission ordering, and action tracking.
- Run: fund independent conflict sets and repeat control/treatment intervals; estimate duration and cost after generator calibration.

#### Related work

- [Geographic conflicting-transaction testing](https://github.com/input-output-hk/ouroboros-leios/issues/1058) — open, assigned to `shd`; directly overlaps the mechanism and proposed measurements.
- [Multi-node transaction flooding](https://github.com/input-output-hk/ouroboros-leios/issues/1066) — closed; related load-distribution machinery and a non-conflicting comparator.

#### Risks and limitations

Only one mutually exclusive transaction can win. Counting every losing alternative as a failed user action would overstate harm.

### 3. Heavy and light Plutus interference

Mix expensive and inexpensive scripts with non-script transactions and measure whether one class delays the others.

#### Question or hypothesis

Expensive scripts may amplify validation-cache misses or slow admission enough to fragment mempools. This could delay cheap transactions sharing the same processing resources.

#### Test and evidence

Compare light-only, heavy-only, and mixed workloads. Measure mempool overlap, cache misses, CPU cost, late votes, useful throughput, and settlement tails by class. Record transaction, Ranking Block (RB), and Endorser Block (EB) budgets to distinguish execution limits from processing delays.

#### Tentative plan

Reuse the stressful-script tooling and coordinate with the planned Musashi load. Vary one script-cost dimension first; investigate cache conditions if the mixed workload shows interference.

#### Infrastructure

- Deployment: stock relays, script-capable generators, and cooperating voters.
- Changes: workload mixing and per-class identifiers; additional tracing if existing logs cannot separate costs.
- Run: calibrate script budgets before network trials; duration and cost remain open.

#### Related work

- [Stressful Plutus transactions](https://github.com/input-output-hk/ouroboros-leios/issues/1032) — closed; candidate generator to reuse.
- [Musashi Plutus load](https://github.com/input-output-hk/ouroboros-leios/issues/1043) — open, assigned to `fmaste`, `bwbush`, and `perturbing`; cross-class interference would distinguish this experiment.

#### Risks and limitations

Changing script cost may also change transaction size or cache reuse. Separate execution budgets do not imply isolated CPU resources.

### 4. Client versus peer submission

Compare equivalent workloads submitted through client-to-node and node-to-node interfaces.

#### Question or hypothesis

The submission interface may change mempool overlap and cache coverage through admission and propagation differences. This tests whether peer-based load generators represent clients' fragmentation and settlement outcomes.

#### Test and evidence

Hold workload, placement, and offered rate comparable while changing the submission route. Measure admission delay, rejection/backpressure, mempool overlap, cache misses, traffic, and settlement time. Distinguish attempted, accepted, and ledger-included transactions; use producer logs to relate misses to failed voting.

#### Tentative plan

Check the available generator interfaces against the deployed node. Begin at one ingress location, then repeat the comparison across regions if a difference appears.

#### Infrastructure

- Deployment: stock relay endpoints and submitters supporting both interfaces; producer logs optional for voting attribution.
- Changes: matched submission drivers and admission timestamps.
- Run: short calibration followed by repeated comparable intervals; duration and cost remain open.

#### Related work

- [Fragmentation tooling](https://github.com/input-output-hk/ouroboros-leios/issues/1022) — open; adjacent submission and observation work.
- [Transaction-generator development](https://github.com/IntersectMBO/cardano-node/pull/6494) — closed without merging; historical interface work, not proof of deployed support. No completed matched comparison was identified.

#### Risks and limitations

Driver pacing or queueing can produce apparent interface effects. Equal attempted rates may produce unequal admitted loads; report both.

### 5. Warm and cold validation evidence

Measure the cost of missing transaction bodies separately from the cost of missing reusable validation evidence.

#### Question or hypothesis

A node holding a transaction may still need expensive validation. Differences in reusable evidence across voters may therefore matter even when their transaction-body caches agree.

#### Test and evidence

Compare equivalent EB transaction sets when bodies are absent, present without reusable validation evidence, or fully reusable. Measure body- and validation-cache miss shares across voters, acquisition/validation time, full-validation counts, and missed voting weight.

#### Tentative plan

Trace the deployed cache and voting paths first. Check whether existing logs distinguish the states, then introduce the smallest controlled state intervention needed for a matched comparison.

#### Infrastructure

- Deployment: cooperating eligible producer/voters; an observer relay alone cannot supply voting outcomes.
- Changes: cache-state tracing and possibly a test-only patch; preserve ordinary validity checks.
- Run: synchronize ledger context and repeat equivalent workload trials; development effort and runtime remain open.

#### Related work

- [Cache-aware fetching](https://github.com/IntersectMBO/ouroboros-consensus/pull/2237) — merged; implementation context, not a controlled cost measurement.
- [Cache-miss sensitivity analysis](https://github.com/input-output-hk/ouroboros-leios/pull/889) — merged; model comparison. No complete matched validation-state experiment was identified.

#### Risks and limitations

Ledger changes can invalidate cached evidence. State manipulation must not skip required checks or produce an unrealistically cheap baseline.

### 6. Coordinated adversarial relays

Use privileged insertion and private coordination among adversary-controlled relays to create unequal transaction visibility across honest nodes.

#### Question or hypothesis

An adversary coordinating selective release may sustain more harmful mempool/cache fragmentation than independent relays. This tests the additional effect of coordination at comparable load and peer access.

#### Test and evidence

Compare ordinary submission, independent adversarial relays using privileged insertion and selective release, and coordinated relays. Measure honest-node mempool/cache overlap, misses, acquisition and validation costs, missed voting weight, settlement delay, and persistence after intervention stops. Account for back-channel traffic.

#### Tentative plan

Verify raw-body insertion separately from validated mempool admission. Start with independent release policies, then privately share transactions and coordinate synchronized or staggered public release. Reuse the controls studied in [selective transaction diffusion](#7-selective-transaction-diffusion).

#### Infrastructure

- Deployment: geographically separated patched relays, stock honest observers, and cooperating voters.
- Changes: authenticated insertion hooks, private coordination, per-peer release policies, and correlated traces.
- Run: local checks, matched trials, and recovery intervals; duration and cost follow a pilot.

#### Related work

- [Transaction-cache implementation](https://github.com/IntersectMBO/ouroboros-consensus/pull/2188) — merged; insertion and validation paths.
- [Regional fragmentation experiment](https://github.com/input-output-hk/ouroboros-leios/issues/1022) — open; workload baseline. No direct matching coordinated-relay experiment was identified.

#### Risks and limitations

Preserve validation checks; privileged insertion does not represent ordinary client access. Alternative peers may defeat selective release, while residual cache state can confound successive trials.

### 7. Selective transaction diffusion

Selectively suppress transaction announcements, requests, or responses and measure mempool/cache fragmentation and recovery.

#### Question or hypothesis

Different diffusion controls may produce different costs even when they create similar transaction visibility. Identifying the effective control would clarify which network behaviors threaten timely voting.

#### Test and evidence

Compare normal diffusion with one suppression policy at a time. Measure mempool overlap, cache misses, fetch retries and bytes, missed voting weight, settlement delay, and recovery after release.

#### Tentative plan

Inspect the existing per-peer announcement controls before writing a Haskell patch. Reproduce announcement suppression first, then distinguish transaction-submission traffic from explicit Leios fetching when adding request or response controls.

#### Infrastructure

- Deployment: controlled relay peers and stock observers; cooperating voters for certification effects.
- Changes: patched relay or compatible adversarial-node tooling, policy controller, and protocol-specific traces.
- Run: include suppression, release, and recovery intervals; duration and cost depend on topology.

#### Related work

- [Per-peer mempool partitioning](https://github.com/input-output-hk/ouroboros-leios/issues/1033) — closed; announcement-gating machinery to inspect and reuse.
- [Committee propagation disruption](https://github.com/input-output-hk/ouroboros-leios/issues/1122) — open, assigned to `shd`; coordinate overlapping interventions.

#### Risks and limitations

Other peers may route around the intervention. Suppressing all protocol traffic would confound transaction availability with block or vote delivery.

### 8. Producer withholding near the threshold

Delay a producer's EB transaction release to study whether certification can coexist with cache fragmentation and late availability for a minority of nodes.

#### Question or hypothesis

A carefully timed release may leave enough timely voting weight for certification while other nodes remain unable to process the transactions. The proposed three-quarter/one-quarter split is a target to investigate.

#### Test and evidence

Sweep release time against immediate release. Measure cache-miss shares by voter, fetch delay, late/absent votes, certificates observed, and subsequent adoption delay. Use the deployed quorum denominator; node counts and voting weight are different quantities.

#### Tentative plan

Coordinate with the withholding work. Begin with uniform delayed release, then test selective release if peer visibility and control permit it. Verify alternative fetch paths before interpreting the split.

#### Infrastructure

- Deployment: modified, eligible producer and geographically separated cooperating observers/voters.
- Changes: transaction-serving policy, release controller, and correlated traces.
- Run: budget for registration, stake activation, and enough actual forging opportunities; duration cannot be chosen from node count alone.

#### Related work

- [Transaction withholding](https://github.com/input-output-hk/ouroboros-leios/issues/1031) and [withholding reports](https://github.com/input-output-hk/ouroboros-leios/issues/1035) — open, assigned to `shd`; substantial overlap, including planned testnet runs.

#### Risks and limitations

Onward diffusion may prevent precise targeting. An on-chain signer set alone cannot establish which nodes voted late or lacked transactions.

### 9. Persistent fragmentation through transaction chains

Use dependent transaction chains and controlled release to test whether cache divergence persists after the initiating disturbance ends.

#### Question or hypothesis

Transaction dependencies may prolong an initial difference in availability or validation state. Establishing whether that happens would distinguish temporary misses from a sustained operating problem.

#### Test and evidence

Compare independent transactions with chains under matched load. Vary depth, branching conflicts, and release timing. Track mempool/cache overlap, miss rates, missed votes, acquisition/validation cost, and settlement delay through intervention and recovery.

#### Tentative plan

Start with non-conflicting chains and ordinary distributed submission. Add conflicting branches or selective release only if needed to test a specific persistence mechanism. Observe a recovery interval after every treatment.

#### Infrastructure

- Deployment: distributed submitters and stock relays initially; patched relay or producer for controlled withholding variants.
- Changes: dependency-aware generator, chain identifiers, and cache-state observations.
- Run: allow longer observation than burst tests; duration and cost depend on the persistence found in pilots.

#### Related work

- [Conflicting transactions](https://github.com/input-output-hk/ouroboros-leios/issues/1058) — open; related branching machinery.
- [Mempool partitioning](https://github.com/input-output-hk/ouroboros-leios/issues/1033) — closed; related visibility control. No direct sustained-chain experiment was identified.

#### Risks and limitations

Missing or invalid predecessors can cause expected rejection rather than cache pathology. Continuing injection must not be mistaken for self-sustaining fragmentation.

### 10. A high-volume exchange workload

Run a realistic decentralized-exchange workload and measure completed user actions under contention.

#### Question or hypothesis

An intent-based or shared-contract workload may create mempool divergence and cache misses absent from independent payments. The useful outcome is whether those differences delay completed user actions.

#### Test and evidence

Compare increasing application load with a low-load baseline and a resource-matched synthetic workload. Relate mempool overlap and cache misses to missed votes, validation cost, completed actions, replacements, and settlement tails; include expired or unfinished actions.

#### Tentative plan

Select an actual contract and define its user actions with someone familiar with it. Validate a small workload first, then increase concurrency and injection concentration. Economic profitability analysis stays deferred.

#### Infrastructure

- Deployment: stock nodes, funded application clients, and cooperating producer telemetry.
- Changes: application setup, realistic workload driver, and intent-to-transaction tracking.
- Run: contract preparation and workload validation may dominate effort; estimate runtime after a small pilot.

#### Related work

- [Application attack analysis](https://github.com/input-output-hk/ouroboros-leios/pull/747) — merged; application-mechanism background, not a matching live workload study. No direct matching Dojo experiment was identified.

#### Risks and limitations

An unrealistic driver may benchmark its own behavior. Contract-level serialization or legitimate conflicts can explain delays independently of Leios caching.

### 11. LLM-guided experimental search

Compare LLMs choosing workload and intervention parameters to find reproducible mempool/cache fragmentation and its performance consequences.

#### Question or hypothesis

Different LLMs may find different fragmentation mechanisms or harmful combinations that parameter sweeps miss. Their value depends on repeatable effects within comparable experiment budgets.

#### Test and evidence

Compare several LLM models with each other and with sweep/random-search baselines under comparable trial and infrastructure budgets. Measure mempool/cache overlap and misses; score reproducible settlement delay, capacity loss, or missed voting weight. Report model cost separately.

#### Tentative plan

Give each model the same verified controls, observations, and starting instructions. Record model/version and settings, repeat searches, and replay promising cases without adaptive intervention on fresh intervals.

#### Infrastructure

- Deployment: controller, access to several LLM models, and the selected experiment's nodes.
- Changes: bounded control interface, automated measurement, replay, and spend tracking.
- Run: fix trial and runtime budgets before search; account for model costs separately from the Amazon Web Services (AWS) node budget.

#### Related work

- [Agreed meta-experiment direction](arc-leios-ha/experiment-plan.md#suggested-llm-meta-experiment-design) — proposed local approach, not an existing result. No direct matching upstream meta-experiment was identified in the earlier search.

#### Risks and limitations

Adaptive search can reward noisy measurements or harmless misses. Fix the target network and available actions, and verify discoveries outside the search that produced them.

## Appendix

### Issue template

Use a brief, recognizable issue title. Aim for roughly 150–250 words in the body, excluding references; leave unknown requirements as “TBD.” In this document, each issue title is an H3 and its sections are H4s. For a standalone issue, use the following body:

```markdown
One sentence describing the experiment.

### Question or hypothesis

What we want to find out, or what we expect to happen. One sentence explaining why the answer matters.

### Test and evidence

What we would vary and compare. Name the mempool/cache-fragmentation measure and its cost, voting, or settlement outcome, including a useful null result.

### Tentative plan

The first few steps: what to reuse or check, the initial test, and how we might extend it. Keep the detailed procedure in the experiment notes.

### Infrastructure

- Deployment: locations, node counts and roles; relay or producer; stake or eligibility needs.
- Changes: generator, instrumentation, configuration, or node patches.
- Run: preparation, duration, recovery, and rough cost, where known.

### Related work

- [Descriptive link](URL) — what was done or is planned; what we would reuse or investigate differently.

### Risks and limitations

Specific ways the experiment could be misleading, difficult to observe, costly, or slow to recover from.
```

### AWS estimate

❓🤖 **SCRUTINY — indicative planning arithmetic, not a quote or node-sizing benchmark.** These are the October 5, 2026 inputs from the [experiment plan](arc-leios-ha/experiment-plan.md#aws-planning-estimate), using published US East (Northern Virginia) on-demand price examples. Confirm the operating system, tenancy, region, and account-specific charges before launch. AWS means Amazon Web Services; GiB denotes gibibytes of RAM.

| Instance | Virtual CPUs / RAM | Compute USD/hour | Compute-only node-hours per USD 1,000 | With disk and address, before traffic | Also 1 MB/s billable internet egress |
|---|---:|---:|---:|---:|---:|
| c6i.xlarge | 4 / 8 GiB | 0.170 | 5,882 | 5,070 | 1,919 |
| m6i.xlarge | 4 / 16 GiB | 0.192 | 5,208 | 4,562 | 1,841 |
| r6i.xlarge | 4 / 32 GiB | 0.252 | 3,968 | 3,581 | 1,658 |

A node-hour assumes one node on one instance. The disk/address column assumes 200 GB of gp3 storage at USD 0.08/GB-month over a 720-hour month, plus one public IPv4 address at USD 0.005/hour. The traffic column assumes USD 0.09 per decimal GB, so an average 1 MB/s adds USD 0.324/hour. This is a sensitivity scenario; actual routes, allowances, and rates differ.

Calculation: `node-hours = 1000 / (compute + storage + address + transfer cost per hour)`.

For eight nodes using the 32 GiB example, USD 1,000 buys about **19 days before traffic, or 9 days with the illustrated egress**. Controllers, generators, synchronization, extra disk performance, retained storage, monitoring, model calls, and taxes can reduce usable experiment time. Neither 200 GB disk nor any listed memory size has been established as sufficient for the current node.

David's stated AWS allocation is **USD 2,000**, with a check-in at **USD 1,500 spent**, as recorded in the agreement. Run a short sizing-and-egress pilot and track cumulative charges across all experiment resources. Model costs are not assumed to be covered by that allocation.

- [Instance prices and sizes — AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/optimize-costs-microsoft-workloads/right-size-selection.html).
- [Storage pricing — AWS](https://aws.amazon.com/ebs/pricing/).
- [Public IPv4 address pricing — AWS](https://aws.amazon.com/vpc/pricing/).
- [On-demand pricing and transfer allowances — AWS](https://aws.amazon.com/ec2/pricing/on-demand/). The USD 0.09/GB traffic assumption above is not an account-specific quote.
