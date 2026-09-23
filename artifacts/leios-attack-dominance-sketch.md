# A dominance sketch for Leios attacks

**Status: draft sketch, 2026-09-22.** Prepared for the Bush/Wolff working session on Thursday 2026-09-24, to give the loose consensus from the 2026-09-21 brainstorm — *"there is a hierarchy of plausible attacks, and mempool attacks are dominated by more effective ones that would use fewer resources"* — something falsifiable to argue with. Nothing here is a result. Every ranking below is a hypothesis with its evidence status attached, and the point of the exercise is to find out which rankings are already settled, which are cheap to settle, and which are the actual research question.

Provenance marker: ⏳🤖 — LLM-drafted, pending human review.

Abbreviations used throughout: **EB** endorser block, **RB** ranking block, **SPO** stake pool operator, **VRF** verifiable random function, **KES** key evolving signature, **BLS** Boneh–Lynn–Shacham (the signature scheme used for Leios votes), **MEV** maximal (or miner) extractable value, **DoS** denial of service, **UTxO** unspent transaction output, **CIP** Cardano Improvement Proposal, **TPS** transactions per second.

## 1. Don't build a new taxonomy — there are already four

The first finding of this pass is that the naming problem is solved, four times over, and the team has settled on one of them in practice.

| Corpus | What it is | Numbering | Currency |
|---|---|---|---|
| [`docs/threat-model.md`](https://github.com/input-output-hk/ouroboros-leios/blob/main/docs/threat-model.md) | The team's living threat model, v0.4, by Sebastian Nagel and Giorgos Panagiotakos | **T1–T35** | 2026-04-10, actively maintained |
| The **Anastasia Labs audit** | Third-party security audit, v1.0, 2026-09-01 — read in full for this note | **LEI-001 … LEI-014** (13 findings; no LEI-002) | Assessed 2026-08-31 at `ouroboros-consensus` `1820edf5` |
| The **ATK taxonomy** | 32 items; 26 analyzed against CIP-164 by an LLM pipeline, on Drive, owner Julián Mendiola | **ATK-001 … ATK-032** | 2025-09-19, ~1 year old |
| The **behavior-tree vocabulary** | 20 implemented adversarial action leaves in [`shared-rs/consensus/src/behaviour/actions/`](https://github.com/input-output-hk/leios-tools/tree/main/shared-rs/consensus/src/behaviour/actions), shared verbatim by sim-rs and Piranha | leaf names (`announce_equivocate`, `tx_flood`, …) | current |

**The red team writes in T-numbers.** Christopher Tilt's reports name "T-27 (wrt TX flooding)", "T10", "T23 (EB withhold then burst)"; Sebastian and Giorgos argue about "T22" in the same terms. So the threat model is the lingua franca, and any dominance ordering we produce should be an ordering *on T-numbers* if it is to be merged rather than admired. The ATK corpus is a year old and LLM-generated (the files carry visible "As an expert security analyst, I will…" preambles and hallucinated analysis dates), so treat its severities as prompts for thought, not as findings. Its value is coverage: it names things the threat model does not, notably Sybil (ATK-023), eclipse (ATK-024), and adaptive committee corruption (ATK-032).

**The Anastasia Labs report turns out to be the single most useful artifact for this exercise**, for a reason its title does not advertise: *every finding states its prerequisites explicitly*. The detailed table and individual findings contain thirteen entries — **0 Critical, 9 Major, 4 Medium, and all thirteen Unresolved** at publication — each carrying a `Prerequisites` line. The executive-summary prose instead says ten Major and four Medium, an internal arithmetic inconsistency; this note follows the detailed table rather than silently treating the report as consistent. The prerequisites are a finer-grained input to cost analysis than the threat model's one-phrase `Resources` column, but they are not themselves complete cost estimates. Two scope limits matter when reading the report: the review was **static and offline** — no execution, no live node, no fuzzing, no load — so effects are source-derived rather than demonstrated, and it is pinned to one unreleased revision (`1820edf5`), so "Unresolved" means "no shipped fix was verified as of 2026-09-01", not "still broken today". The disclosure page authorizes both parties to share the report publicly, so it may be cited here and onward.

**The threat model already has half the dominance axis.** Every T-row is `Method | Effect | Resources | Mitigation` — so the cost axis exists per threat, in the team's own words. What no artifact has is the **comparison**: nothing anywhere says T-x dominates T-y. That gap is the contribution available here, and it is small enough to fill in a couple of days.

## 2. Making "dominates" mean something

Informally the claim is "why would anyone bother fragmenting mempools when they could do *that* instead". To argue about it we need three commitments.

**(a) Dominance is Pareto dominance on (cost, damage).** Attack *A* dominates attack *B* when cost(*A*) ≤ cost(*B*) and damage(*A*) ≥ damage(*B*), with at least one strict. This yields a partial order, not a ranking — most pairs will be incomparable, and saying so is informative.

**(b) Dominance only holds within an adversary objective.** An adversary who wants throughput denied, one who wants value extracted, and one who wants a safety violation are not choosing from the same menu, and an attack that is useless for one may be the best available for another. Four objectives cover the corpus:

- **O1 Throughput denial** — reduce certified EB rate or effective TPS. (T9–T14, T20–T28.)
- **O2 Value extraction** — front-run, sandwich, reorder; profitable rather than merely costly. (T16–T19, T34; the whole [`docs/mev/`](https://github.com/input-output-hk/ouroboros-leios/tree/main/docs/mev) corpus.)
- **O3 Safety violation** — chain splits, invalid certified history. (T15, T29, T32–T34, and the audit's cache findings.)
- **O4 Operator attrition** — push resource cost above what SPOs will bear, thinning honest stake. (T23, T31, and asset A4.)

Cross-objective comparison is a *defender's* prioritization question, not a dominance question. Conflating the two is, I suspect, where the room's loose consensus will turn out to be doing its work: mempool attacks are weak at O1 and reasonable at O2, so "dominated" may be true at O1 and false at O2. ❓🤖

**(c) The cost vector is not one number.** At minimum: stake fraction σ; whether a *registered, elected* pool is needed (musashi requires refundable pool and key deposits; `minPoolCost` is a reward-distribution parameter, not a registration payment); egress bandwidth; node count and topology position; transaction fees actually paid; key material (a leaked key evolving signature (KES) key for the operational-certificate issue-number vector); sustained time; and detectability — peer disconnection, churn, or reputational loss are real costs that the tables above mostly omit. Capital committed must also be separated from economic cost consumed. The single most useful scalar to attach is the **griefing factor**: honest cost inflicted per unit of adversary cost. It is comparable across attack classes only when the cost boundary and attack window are held constant, and no Leios artifact currently computes one.

Two scoping conventions are already in force and should be stated, because they bound the cost axis:

- The red team caps itself at **≤25% stake** — "we already know that >25% is not a valid attack" (Tilt, 2026-07-27). Their pools sit near PIR0 ~20–30% plus a 10-pool cluster at ~1% each.
- Several analytic arguments nonetheless run at **50%** (Knutsson's leeching analysis, Panagiotakos's balancing-attack framing). These are honest-majority-boundary studies, not testnet practice. Don't mix the two budgets in one table.

## 3. What the audit's prerequisites do and do not establish

Sorting the thirteen findings by their stated prerequisites identifies low-credential paths, but it does not produce a total cost ordering: network admission, victim selection, topology, backend choice, and possession of valid protocol material are distinct gates.

| Prerequisite class | What the attacker needs | Findings | Effect (source-derived unless noted) |
|---|---|---|---|
| **Admitted-peer paths without attacker stake or a private protocol key** | Finding-specific combinations of an admitted or hot peer, victim selection or an established fetch session, backend state, ordering, and sometimes a genuine block hash or public committee verification key | **LEI-004, LEI-005, LEI-006, LEI-008, LEI-009, LEI-010, LEI-014** | Unchecked fixed-width cache reads; persistence of an object violating its own server invariant; unbounded process-resident metadata growth; unbounded SQLite row growth; peer-controlled vector allocation; poisoned authoritative body size; repeatable unbudgeted BLS verification work |
| **Valid committee material** | LEI-003 requires a current committee signing key; LEI-012 requires an admitted peer carrying an unseen valid vote, plus sufficient accumulated weight, a relevant announcing tip, a closure, and a remaining direct-child forge opportunity | **LEI-003, LEI-012** | Growth from valid votes on attacker-chosen hashes; a valid withheld vote accepted after the local deadline |
| **Producer capability** | Valid production credentials and finding-specific certificates, closures, announcements, or paired headers | **LEI-001, LEI-007, LEI-011** | Voting-worker termination on malformed committed transactions (**demonstrated live**); a certifying ranking block accepted inside the intended gap; voting despite observed announcement equivocation |
| **Committee-transition state** | Vote state surviving a committee change while the announcing hash remains relevant; the exception subcase also requires a shrink or reassignment and a valid new vote crossing the threshold | **LEI-013** | Certification-liveness loss, wasted forging, or a peer- or worker-reachable exception; no false-quorum acceptance established |

**Seven of thirteen findings require no attacker stake or private protocol key.** That makes them important low-credential hardening paths, but it does not establish zero cost or open reachability: peer admission and selection are deployment-dependent, and several findings require additional state or ordering conditions. The audit therefore supplies prerequisite gates, not enough information to prove that these paths dominate mempool fragmentation on total cost.

**The audit and the red team are complementary instruments, and the pairing is worth noticing.** Anastasia's review was static: it derived prerequisites and effects from source and says so plainly wherever it could not demonstrate them ("no trigger was executed", "no heap profile was run", "node-wide failure depends on unverified supervision"). The red team then demonstrated two of those findings on the live testnet within days — LEI-001 as the block-producer crash on 2026-09-02, LEI-005 as the oversized-EB bounds error on 2026-09-03. Static analysis supplies the prerequisite; live exercise supplies the blast radius. Neither alone gives both coordinates of a dominance argument.

**Four findings independently confirm divergences this repository found on 2026-09-17** ([protocol parameters](./leios-node-protocol-parameters.md) § 7), which is a useful check on our own reading of the same code: **LEI-007** is the forge-only minimum certification gap (our `Forker.hs` FIXME, and the basis of candidate workstream (e)); **LEI-011** is CIP-0164 vote condition 2, equivocation, unenforced at vote time; **LEI-012** is the missing timing check on received votes; **LEI-013** is the missing epoch check. LEI-005 is our unenforced `LeiosEbTooBig`. We reached those by reading for conformance and the auditors by reading for exploitability, and we landed on the same lines.

**And LEI-007 probably resolves the 10-versus-14 certification-gap discrepancy** that has been an open to-do since 2026-09-17. The audit states `minCertificationGap` is **10 at the assessed revision**, matching the August Slack figure, while our 14 is computed from musashi's *deployed* ledger parameters (3·L_hdr + L_vote + L_diff = 14 s at a 1 s slot). Two different parameterizations of the same rule, not a contradiction — worth one confirmation against the live value before closing it. ❓🤖

## 4. The comparison, first cut

Evidence status is the column that matters most for Thursday: it says which rows are already decided.

| T | Threat | Obj | Resource floor (from the threat model, plus what we know) | Observed / modelled effect | Evidence status |
|---|---|---|---|---|---|
| T11/T13 | Invalid EB / invalid txs referenced in EB | O1 | **One VRF win.** "Some (but not a lot of) stake… a single EB with 8 TXs, so one VRF slot is enough" | **Block producers network-wide crashed for a ~10-minute window**; the forged EB reached 60+ distinct peer IPs; relays unaffected | **Measured on testnet**, Red Team 2026-09-02; = audit LEI-001 |
| T13 | EB referencing txs never diffused ("EB Trojan Horse") | O2/O3 | One VRF win, one crafted EB | 1,000 ₳ taken from IOG1, testnet block #80676 | **Measured**, 2026-08-27; closed by tx validation on EB bodies in w35 |
| — | Oversized EB (13,889 txs) | O1 | An admitted peer whose self-consistent offered body is selected and fetched; the live demonstration's exact credentials are not recorded here | Peer connections torn down; **no node crash**, self-recovered on disarm | **Measured**, 2026-09-03; same ingress defect as audit LEI-005 |
| T21/T22 | Selective withholding from the committee / from most honest nodes | O1/O3 | "Network position control", modest stake; leeching variant needs **egress** | Simulated: a passive attacker **fails above 50 Mbps egress for a 12 MB EB**; certifying a cold 12 MB EB needs ~250–300 MB/s; resisting a leeching attacker pushes the requirement above 250 Mbps | **Simulated** (Knutsson, 2026-09-17); undecided analytically |
| T22 + balancing | Withholding used to widen a Praos balancing attack | O3 | ~50% stake | Unquantified; Panagiotakos: formal analysis needs an EB-diffusion delay distribution that does not exist yet | **Open, explicitly deferred** |
| T21 | Topology-aware selection of a bad initial diffusion set | O1 | Knowledge of stake-sampled topology + stake | At 50% adversarial stake, **11% of stake has zero outgoing stake-sampled edges** | **Analytic + plot** (Panagiotakos, 2026-09-01) |
| T23 | Withhold then release many EBs (burst) | O1/O4 | Stake, proportional to magnitude | **No measurable harm** up to 100 EBs / 3.6 h stale / 150 ms links — pull-based EB fetch self-regulates | **Measured (preliminary)**, Tilt 2026-09-06 |
| T10 | Decline to vote | O1 | Voting stake only; costs the attacker rewards | Lower throughput | **Reported**, Red Team T10 report 2026-08-25 |
| T24/T25 | Duplicate / invalid tx submission | O1 | Network bandwidth only | Resource waste; pull-based diffusion and pre-forward validation blunt it | Threat model: mitigated |
| T27 | **Mempool partitioning via network control** | O1 | "Network infrastructure control" | Inconsistent mempools, conflicting EBs, delayed certified EB delivery; mitigation listed as **"Limited"** | **Red Team tx-flooding report** 2026-08-25; sim available |
| T26 | Submit conflicting transactions | O1/O2 | "Transaction fees per conflict" — but see §5 | Processing waste; only one succeeds | Analytic + `mempool-sim-web`; front-running slopes confirmed against the simulator |
| T28 | Honeypot contract creating tx races | O1 | Contract deployment cost; **third parties pay the conflict fees** | Artificial high-volume conflicting traffic; mitigation "Limited" | **Unassessed** — no experiment found |
| T2/T3 | VRF grinding on EB / voting eligibility | O1/O3 | CPU + **>20% stake** | Concentrates EB production and committee seats beyond stake share | Analytic, deferred to Ouroboros Phalanx |
| T32/T33 | Silent BLS / VRF key accumulation | O3 | Adaptive adversary + **time** | Certificate forgery without quorum; eligibility beyond stake | Added v0.4; bounded by `maxKeyAge` = 374 epochs |

## 5. The claim under test, and what the evidence establishes

**The measured producer crash establishes severe damage, not dominance.** One verifiable random function (VRF) win and a malformed endorser block crashed the Haskell block producers observed on musashi for roughly ten minutes. No available experiment supplies a common total-cost calculation or an upper bound on mempool-fragmentation damage, so “strictly less stake” and “strictly more damage” do not follow. The Trojan Horse caused value loss, while the oversized-block case tore down peer connections without crashing a node; they are useful measurements but not the same outcome shape.

**Those measured cases are implementation defects rather than established protocol properties, and that changes what a future ranking would mean.** Reading the audit alongside the red-team results, the corpus splits three ways, and the three call for different work by different people:

1. **Resource and memory-safety defects** — LEI-001, LEI-004, LEI-005, LEI-006, LEI-008, LEI-009, LEI-010, LEI-014. Missing bounds, missing quotas, unchecked widths, unbounded retention. Several are admitted-peer paths and LEI-001 requires producer capability. They are primarily hardening work, and each leaves the ordering for a release once its triggering path is fixed.
2. **Conformance gaps** — LEI-007, LEI-011, LEI-012, LEI-013, and LEI-003 in part. Rules Cardano Improvement Proposal 0164 (CIP-0164) states and the implementation does not enforce: the certification gap on received blocks, equivocation before voting, vote timing, and committee-epoch binding. These are implementation/specification discrepancies whose main instruments are source review and conformance testing; whether the stated design rule is current still requires confirmation against authoritative upstream specification and code.
3. **Protocol properties** — T21/T22 diffusion denial, T27 mempool partitioning, T23 bursts, T2/T3 grinding, the balancing-attack question. These are candidates that could survive a correct and complete implementation because they exploit protocol mechanics. Analysis and simulation are primary instruments here, subject to their modeling assumptions.

> **Rank the three categories on separate boards.** A hierarchy that mixes them can be driven by a severe but patchable defect and become stale with the next release.

Restrict the comparison to protocol-level attacks and the picture changes. The principal objective-O1 candidates are **T21/T22** (withholding and diffusion denial, where Knutsson has egress numbers and Panagiotakos has a topology result) and **T27** (mempool partitioning by network control, whose threat-model mitigation column says "Limited"). None is yet shown to dominate another under a common cost and damage measure. T27 *is* a mempool attack, so the loose consensus cannot be stated as "mempool attacks are dominated" without immediately excepting the mempool attack the threat model is least confident about.

**Two unresolved inputs to the mempool comparison.**

1. **Losing transactions may avoid inclusion fees.** Cardano's determinism property means a conflicting transaction that never lands pays no inclusion fee. An adversary flooding *n* mutually conflicting transactions may therefore pay the ledger fee for only the transaction that wins. T26's resource column reads "transaction fees per conflict" and T28's mitigation reads "attacker pays for *some* conflicts." This is a discount on one component, not zero total marginal cost: construction, bandwidth, peer access, submission capacity, and temporarily usable funds remain. Confirm the fee premise against current ledger code, then measure the other components. ❓🤖
2. **Damage may be nonlinear or heavy-tailed.** A tail classification alone does not establish unbounded damage or dominance: scale, truncation, likelihood, and the selected risk functional all matter. A calibrated severity distribution could make fragmentation preferable, dominated, or incomparable under a stated budget and objective.

So the two halves of the meeting's short-term list are coupled but not equivalent. The fragmentation-severity distribution is one input to whether a mempool attack reaches the budget-relative frontier; the total-cost curve, objective, and risk functional are the others. Measuring these quantities can test the room's consensus without presupposing that either a thin or heavy tail determines the answer.

## 6. What is cheap, given the two cost constraints

The meeting flagged that large-scale telemetry is hard on a low budget and that large mempool experiments are expensive. That argues for putting *our* evidence cost in the same table as the adversary's, and picking from the cheap corner.

**Cheap, and mostly already possible:**

- **Compute a griefing factor for every T-row that has numbers.** Desk work on existing artifacts; produces the first cross-class comparison anyone has.
- **Use the 20 implemented behavior-tree leaves as the experiment menu.** An attack with a leaf already written (`tx_flood`, `withhold_txs`, `announce_equivocate`, `eb_burst`, `cert_suppressor`, `lazy_voter`, `t22`) costs a config file in sim-rs; one without costs an implementation. That mapping alone tells us which rows are cheap to settle — and note there is a leaf literally named `t22`, so the threat-model numbering already reaches into the code.
- **Take Marcin Wójtowicz up on his offer.** On 2026-09-14 he offered to show "what 100% mempool fragmentation leads to on the sim" — the pessimal end of the very distribution in question, free, from someone else's harness.
- **The certification-gap and π₁ → p_eb → P_certified pipeline** already in our artifacts gives an analytic damage model for anything that delays or suppresses certification, which covers T20–T23 without new telemetry.

**Expensive, and worth being explicit about declining:** anything needing many instrumented nodes across regions, sustained testnet load, or a bespoke mempool bed. If a question can only be answered that way, that is itself a finding for the scope statement.

**One ask still outstanding:** read access to `input-output-hk/leios-adversarial-tools`, where the private `behaviours/*.toml` compose the leaves into named attacks. The audit report is now in hand (`background/audit-report-20260902.pdf`), and it supplies finding-specific prerequisite gates—not complete costs—for the comparison above.

## 7. Questions for Thursday

1. Do we accept the three-way split — resource defects, conformance gaps, protocol properties — and scope analysis and simulation only to the third?
2. Is "dominated" being claimed at O1 (throughput denial) only, or across objectives? The answer changes whether MEV-class attacks belong in the same hierarchy at all.
3. What adversary budget do we standardize on — the red team's ≤25% stake, or the ~50% honest-majority boundary the analytic work uses?
4. Is the conflicting-transaction fee asymmetry real as stated in §5.1? Confirming or killing it is an afternoon's ledger reading and it is load-bearing for the whole argument.
5. If the long-tail question is the crux (§5), does that re-rank it to first among the short-term list?
6. Thirteen detailed audit findings are recorded Unresolved as of 2026-09-01 against revision `1820edf5`. Which are fixed by now? The answer determines which prerequisite-gated defect paths remain feasible, and it is a question for Sebastian rather than for us.

## Sources

### Threat and attack corpora

- [Leios threat model v0.4 — Sebastian Nagel, Giorgos Panagiotakos, `ouroboros-leios/docs/threat-model.md`](https://github.com/input-output-hk/ouroboros-leios/blob/main/docs/threat-model.md)
- [Leios MEV analysis corpus — `ouroboros-leios/docs/mev/`](https://github.com/input-output-hk/ouroboros-leios/tree/main/docs/mev), including `front-running-cost-model.md`, `classification.md`, `mitigations.md`, and five attack-vector notes
- [Leios Technical Report #1, threat-model section](https://github.com/input-output-hk/ouroboros-leios/blob/main/docs/technical-report-1.md#threat-model) and [Technical Report #2, notes on the Leios attack surface](https://github.com/input-output-hk/ouroboros-leios/blob/main/docs/technical-report-2.md#notes-on-the-leios-attack-surface)
- CIP-164 attack taxonomy analysis (ATK-001 … ATK-032) — Google Drive folder `1BPTDIZTWFPaL2SnTJo4hcTdTRDUjK4iO`, owner Julián Mendiola, 2025-09-19 (internal; LLM-generated per its own `SUMMARY.md`)
- **Security Audit Report — Ouroboros Consensus — Leios**, Anastasia Labs, v1.0, 2026-09-01; assessment performed 2026-08-31 against `IntersectMBO/ouroboros-consensus` revision `1820edf5e496fbec5aa230a8bee56397c76f474b`; 13 detailed findings (LEI-001 … LEI-014, no LEI-002), whose table totals 9 Major and 4 Medium, all Unresolved at publication. The executive-summary prose instead says 10 Major and 4 Medium. Static offline source review only. Local copy: `background/audit-report-20260902.pdf`. Its disclosure page authorizes both the customer and Anastasia Labs to share the document publicly.

### Red-team empirical results (all #team-leios, internal)

- Malformed-tx EB crash of block producers, Christopher Tilt, 2026-09-02
- EB Trojan Horse, 1,000 ₳ taken, testnet block #80676, Christopher Tilt, 2026-08-27
- Oversized-EB bounds error, Christopher Tilt, 2026-09-03
- T23 EB withhold-then-burst, no measurable harm, Christopher Tilt, 2026-09-06
- T27 tx-flooding and T10 reports, Dmitry Shtukenberg, 2026-08-25
- Leeching / cold-EB egress analysis, Karl Knutsson, 2026-09-17
- Topology-aware diffusion-set selection, Giorgos Panagiotakos, 2026-09-01
- Red-team stake allocation and the ≤25% convention, John Lotoski and Christopher Tilt, 2026-07-27 through 2026-08-25

### Implementation

- [Behavior-tree adversarial action leaves — `leios-tools/shared-rs/consensus/src/behaviour/actions/`](https://github.com/input-output-hk/leios-tools/tree/main/shared-rs/consensus/src/behaviour/actions)
- [Behavior-tree engine specification — `leios-tools/specs/001-behavior-tree-engine`](https://github.com/input-output-hk/leios-tools/tree/main/specs/001-behavior-tree-engine)
- [Attack simulation experiments — `ouroboros-leios/analysis/sims/attack/`](https://github.com/input-output-hk/ouroboros-leios/tree/main/analysis/sims/attack)

### This repository

- [Leios node protocol parameters](./leios-node-protocol-parameters.md) — § 5 certification gap, § 7 the prototype's unenforced acceptance and vote rules
- [Leios simulation and model catalog](./leios-simulation-model-catalog.md) — dives 1 (sim-rs), 7 (Piranha / net-rs), 10 (post-CIP mempool models, including the poisoned-mempool slopes)
- [Leios transaction-flow instrumentation](./leios-tx-flow-instrumentation.md) — what a single node can and cannot observe
