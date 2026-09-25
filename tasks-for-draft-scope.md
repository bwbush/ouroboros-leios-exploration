# Tasks for the Draft Scope

These are candidate research tasks for discussion, not settled work packages. The plans are specific enough to compare, but the methods and boundaries can change.

## Natural Mempool Fragmentation under Different Workloads and Injection Scenarios

### Problem Statement

Study how much memory-pool (mempool) fragmentation arises naturally under realistic workloads and submission patterns. The starting point is the ARC simulation work from last year, which spread transaction arrivals broadly across nodes. We would add concentrated gateways, regional applications, direct operator submission, multihoming, and mixtures of these patterns. The goal is not to declare one scenario “real,” but to map plausible conditions to mempool overlap and transaction-fetch demand.

### Motivation

Leios works best when voters already hold many of the transactions referenced by an Endorser Block (EB). Measurements suggest high mempool alignment during ordinary Cardano operation, and models show what happens at an assumed fragmentation level. What is missing is the step between them: how much fragmentation should we expect from realistic workloads and submission paths?

Concentrated gateways might improve alignment through common entry points, or worsen it through regional clusters and correlated failures. Bursty applications, transaction dependencies, retries, and multihoming may also matter. Establishing this natural range would give the attack study a credible baseline and help distinguish protocol problems from workload or deployment effects.

### Tentative Plan

First reproduce and clearly state the relevant ARC baseline. Then add a layer from transaction originators through submission gateways to Cardano ingress nodes. Keep uniform injection as a control and vary gateway concentration, backend fan-out, multihoming, placement, transaction mix, and burstiness. Unknowns such as a hosted provider's internal fan-out would be swept as ranges rather than treated as facts.

We would choose the simulator after clarifying the scenarios. The TypeScript `mempool-sim-web`, the Rust simulator, or another simulator could be used, depending on the detail required. Runs should have deterministic seeds and recorded configurations. A few limited, low-cost experiments on local or coordinated nodes may test assumptions that simulation cannot settle. Node telemetry and chain-derived EB overlap would provide calibration.

### Expected Outputs

- A small, documented family of workload and injection scenarios.
- Reproducible simulation code and a workstation-scale experiment matrix.
- Results relating ingress patterns to mempool overlap, EB miss shares, convergence time, and fetch demand.
- An assessment of which scenarios differ materially from the uniform baseline and which assumptions drive the difference.
- Recommendations for any focused multi-node measurements still needed.

## Resource-Bounded Mempool-Fragmentation Attacks

### Problem Statement

Estimate the strongest plausible mempool-fragmentation attacks available to adversaries with stated resources, access, goals, and time horizons. Instead of asking whether extreme fragmentation is theoretically possible, ask what severity an adversary could afford and sustain, and whether the same resources would do more harm through another attack.

### Motivation

Severe fragmentation can damage certification and goodput, but an adversary capable of causing it may have cheaper or more disruptive options. That opportunity cost should affect priorities. An attack matters when it is competitive for a relevant goal—not simply because it works under unlimited assumptions.

The existing resource-economics work provides a framework for comparing capital requirements, operating costs, and damage at a common budget. Candidate scenarios include conflicting transactions, flooding, EB withholding, and diffusion denial. The missing piece is a calibrated relationship between attacker resources and fragmentation damage. The first task supplies the benign baseline.

### Tentative Plan

Define a few adversary profiles using submission capacity, bandwidth, hosted nodes, network access, geographic placement, funds, stake or producer eligibility where relevant, and duration. Comparisons would be made within a stated objective; there is no single “strongest” attack across unrelated goals.

Use the same simulator as the first task so benign and adversarial runs share assumptions and metrics. Sweep concentrated flooding, reordered conflicting transactions, selective placement, and timed bursts. Limited, low-cost experiments on a local devnet, small deployment, or authorized testnet may check key assumptions. Measure fragmentation above baseline, persistence, closure-fetch work, certification effects, and impact on Praos. Resource prices would be ranges, not precise estimates.

Finally, compare fragmentation with alternative attacks serving the same objective. Dominance, a crossover budget, and “incomparable with present evidence” are all useful answers.

### Expected Outputs

- A small set of attacker profiles and safe scenarios.
- Cost–severity and cost–damage ranges with explicit assumptions.
- Comparisons with alternative attacks under common objectives.
- The strongest plausible fragmentation case within each budget range studied.
- A recommendation on whether further fragmentation mitigation is warranted and where defensive leverage is greatest.

## Transaction-Availability Supernodes

### Problem Statement

Assess whether independent, highly connected transaction-availability nodes could help Leios voters retrieve missing transaction bodies quickly. These “supernodes” would serve content-addressed transactions when an EB shows that a node lacks part of its closure. They would supplement ordinary gossip, not validate transactions or become a trusted consensus role. The task would test whether the idea is useful enough to justify the complexity and new risks it introduces.

### Motivation

A cache-cold voter may need transactions held by poorly connected or overloaded peers, all within a short voting deadline. Once the missing hashes are known, the immediate problem is finding a responsive source. Well-provisioned availability services might reduce that tail by retaining recent transactions and answering direct requests.

They could also become censorship points, eclipse tools, privacy leaks, or denial-of-service targets. Clients could amplify requests or exhaust storage; providers could withhold, observe interests, or serve stale data. The service might encourage ordinary nodes to underinvest in gossip while a few operators absorb the cost. We should first ask whether measured misses justify it and whether simpler alternatives would suffice.

### Tentative Plan

Sketch a minimal service with hash-addressed bodies, bounded retention, independent providers, and no authority over validity. Compare it with peer fetching and simpler alternatives. Model discovery, routing, hedging, rate limits, placement, storage, egress, overload, and withholding using miss rates from the first task.

The evaluation would focus on tail fetch latency and vote-window success. It would examine denial of service, amplification, Sybil and eclipse strategies, withholding, poisoning, privacy, centralized discovery, and correlated failures. It would also ask who benefits, who pays, how useful service could be measured, and whether reciprocity, subscriptions, protocol rewards, or another model could work without creating a privileged role. Simulation or trace replay should suffice unless the idea shows a clear benefit.

### Expected Outputs

- A simple architecture sketch and explicit trust boundaries.
- A comparison with producer serving, ordinary relays, fetch hedging, and no special service.
- Sensitivity results showing when supernodes materially improve tail latency or vote success.
- Critical attack-surface and incentive assessments.
- A recommendation to discard the idea, retain it as a fallback, or study it in more detail.
