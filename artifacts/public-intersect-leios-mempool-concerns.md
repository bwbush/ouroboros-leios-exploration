# Public Intersect Concerns about the Leios Mempool and Transaction Cache

**Status:** ⏳🤖 Large language model (LLM)-generated review of public material, pending human review. Search performed September 24–25, 2026; GitHub issue states last checked September 25, 2026.

## Executive summary

Public Intersect records contain substantive concerns about the Ouroboros Leios memory pool (mempool), transaction availability, and transaction cache. The strongest recurring themes are that realistic mempool fragmentation has not yet been characterized, missing transactions consume a limited diffusion and validation budget, a Praos-sized mempool may throttle Leios, and certifying an Endorser Block (EB) complicates ordinary mempool revalidation because it introduces another ledger state. Technical Steering Committee (TSC) members have also questioned whether performance is monotonic near the Praos–Leios crossover and whether optimistic transaction reuse produces unpredictable latency under load.

The current engineering tracker adds more concrete but narrower implementation concerns: transaction-submission parameters have not been tuned for a Leios-sized mempool; per-peer fetch buffers retain transaction data longer than necessary; a zero EB-reference limit can behave like an effectively unbounded limit; and the fixed transaction-cache table may be mismatched with other retention limits. The last point is disputed as of September 25: the issue reporter derived the mismatch from the codec limit, while a maintainer replied that the protocol parameter for a *valid* EB is much smaller. It should therefore be treated as an unresolved invariant question, not a confirmed exploitable defect.

These public records support two proposed research directions particularly well: modeling natural fragmentation under realistic transaction-injection patterns and bounding fragmentation or cache-pressure attacks by the resources needed to sustain them. No public Intersect document found in this search proposes transaction-availability “supernodes,” analyzes concentrated gateways such as hosted submission services, or compares the opportunity cost of fragmentation attacks with alternative attacks using the same resources.

## Scope and evidentiary limits

This review searched public Intersect committee minutes, team updates, product material, and the public issue trackers for `ouroboros-consensus` and `ouroboros-network`. It also followed public Intersect updates into the upstream `ouroboros-leios` tracker where the update depended on that issue. Searches covered combinations of *Leios*, *mempool*, *transaction cache*, *TxCache*, *fragmentation*, *missing transaction*, *fetch*, *revalidation*, *latency*, *discarded work*, and related terms.

The sources have different evidentiary weight:

- TSC minutes establish that a concern was raised and preserve the response to it; they do not establish that the concern is correct.
- Team updates report engineering work and benchmark conclusions, but the short updates generally do not include the complete configurations, seeds, raw results, or machine descriptions needed to reproduce them.
- Open issues are implementation claims awaiting resolution. Their open status is not confirmation, and recent comments may materially qualify the original report.
- Design documents and Cardano Improvement Proposals were not treated as proof of current implementation behavior.

This is a survey of the public record, not an independent source-code audit of every issue below.

## Concerns raised in committee discussion

### Fragmentation creates transaction gaps inside a limited vote budget

The clearest committee-level mempool concern appears in the [TSC minutes for October 8, 2025](https://github.com/IntersectMBO/tsc-documentation/blob/main/meeting-minutes/2025-tsc-meeting-minutes/meeting-minutes-october-08-2025.md). Participants described EB diffusion as optimistic: a receiving node is expected to possess most referenced transactions already and fetch only the “gaps.” They observed that gaps may become larger under load and that fetching missing transactions adds network delay that consumes the time available for validation and voting.

This is a direct statement of the mechanism that makes mempool overlap important to Leios. It does not quantify the distribution of gaps under realistic transaction injection, topology, or workload conditions.

### Wasted work, crossover behavior, and unpredictable latency

The same October meeting considered the transition between Praos-like and Leios-like operation. Neil Davies argued that EB production, dissemination, and voting can be discarded when a Ranking Block (RB) intervenes, and that transactions can consequently experience longer and less predictable inclusion delays near the crossover. The minutes record an illustrative claim about a mempool containing one RB of work plus another 50%, not a measured result. Sebastian Nagel acknowledged a boundary region in which Praos might outperform Leios but disputed the broader conclusion about high-load behavior.

The concern reappeared in the [TSC minutes for May 6, 2026](https://github.com/IntersectMBO/tsc-documentation/blob/main/meeting-minutes/2026-tsc-meeting-minutes/meeting-minutes-may-06-2026.md). Davies characterized Linear Leios as a preemptive system that discards work and might not have monotonic performance under load. Nagel responded that the discarded fraction should be small relative to the throughput gain and emphasized that Leios avoids resubmitting transactions already present in mempools. Davies also questioned whether the assumed 12 MB transfer could be achieved over lossy transcontinental paths and warned of a sharp performance collapse.

These are disputed protocol-performance concerns rather than settled findings. The minutes are nevertheless important because they identify the measurements needed to settle the dispute: latency distributions across the crossover, the amount of discarded work, transaction overlap, loss-sensitive transfer time, and recovery after overload.

## Concerns reported by engineering teams

### A Praos-tuned mempool may throttle Leios throughput

The [Performance and Tracing update of May 29, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-05-29-performance-and-tracing.md) reports full-cluster `tx-centrifuge` benchmarks across different levels of mempool fragmentation and capacity. The team concluded that a standard mempool tuned for Praos would likely throttle maximum Leios throughput. The update says the work was intended to close the gap between simulation and the timings of a concrete mempool implementation.

This is the strongest public experimental statement found in the search. Its wording remains appropriately qualified—“likely”—and the update does not link a complete benchmark report containing the run configurations and results. It establishes the mempool as a plausible bottleneck, not a universal throughput ceiling across all parameterizations.

### Certification can invalidate the assumptions behind ordinary mempool state

The [Consensus update of June 2, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-06-02-consensus.md) says that revalidating whole transaction sequences against multiple ledger states is wasteful and that certifying an EB creates a ledger state that can make the basic mempool state irrelevant. Designs under discussion included two distinct mempools and a directed acyclic graph (DAG) for the ledger.

This is an architectural concern about current mempool semantics under Leios, not simply an optimization request. The update does not record a final design decision, nor does it show that either proposed design was implemented.

### Peer reliability, slow serving, and optimistic fetch assumptions

The same June update reports a multi-peer EB-fetch design centered on a large request to a high-latency peer, with roughly 30 MB in flight per EB in the scenario described. It states that slow-loris impact was still being assessed and that the Rust simulator assumed peer reliability, an assumption judged unsafe for mainnet. These are broader fetch concerns, but they directly affect whether missing mempool transactions can be obtained before the vote deadline.

### Admission and prioritization remain design questions

The [Consensus update of July 28, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-07-28-consensus.md) reports discussion of current mempool requirements, a high-throughput mempool, and a tiered-pricing mempool in which higher-paying, non-conflicting transactions could move ahead of ordinary-paying transactions. This creates unresolved questions about starvation, strategic transaction construction, fee policy, and whether transaction conflicts interact with priority under fragmentation.

## Current public implementation issues

### Transaction submission is not yet parameterized for Leios load

Open [`ouroboros-network#5429`](https://github.com/IntersectMBO/ouroboros-network/issues/5429) records that transaction-submission version 2 uses fixed request and in-flight limits and calls for investigation of settings capable of filling a Leios-sized mempool. This is a concrete capacity and convergence concern: increasing the mempool alone does not ensure that transaction diffusion can populate it at the required rate.

### Fetch buffers retain transaction payloads per hot peer

Open [`ouroboros-consensus#2297`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2297) reports that each Leios fetch responder allocates two boxed scratch buffers and does not clear their contents between requests. Each connection can therefore retain the largest transaction request it has served until the connection closes. The issue further says that an honest client stays near its request-byte bound, but the server independently checks only the request bitmap shape, allowing a peer to request an entire closure. If the source analysis is correct, retained memory scales with hot-peer count and the largest request per peer.

This is an open implementation report, not yet a demonstrated denial-of-service result. It nevertheless provides a specific resource-amplification mechanism suitable for measurement.

### Cache capacity and eviction invariants are disputed

Open [`ouroboros-consensus#2290`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2290) argues that the fixed transaction-cache table holds about 58 EBs at the maximum number of references accepted by the codec while the node retains 128 recent EBs. It also alleges that occupancy does not drive eviction, lookup cost rises before the table fills, and a failed insertion can leave entries that eviction will not reclaim.

On September 25, a maintainer challenged the issue's premise: the maximum size of a *valid* EB is governed by a protocol parameter reportedly never proposed above 500 KiB, rather than by the larger codec limit used in the issue's calculation. At that size, the maintainer calculates fewer than 16,000 transaction references per EB. The issue remains open. The questions to settle are therefore whether an invalid but codec-accepted body can reach cache insertion, which bound current source actually enforces before insertion, and whether the table, residency window, and rollback behavior are mutually consistent for every valid parameter set. The reported partial-insertion leak also warrants review independently of the disputed maximum.

### A zero reference limit can reverse its intended meaning

Open [`ouroboros-consensus#2291`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2291) reports that the prototype represents one unbounded RB measure using `Word32`'s maximum and relies on arithmetic overflow to recover the EB limit. On the reported path, an EB reference limit of zero does not mean that no references fit; it can instead leave that dimension effectively unbounded. This is primarily a parameter-representation and forging defect, but it illustrates why resource bounds must be checked compositionally rather than one parameter at a time.

### Earlier mempool requirements issue uses stale protocol terminology

Open [`ouroboros-consensus#1509`](https://github.com/IntersectMBO/ouroboros-consensus/issues/1509) records that the mempool behavior depended on unresolved Leios requirements. It is written in terms of Input Blocks and their RB pointers, reflecting an earlier design lineage. Its open status should not be read as evidence that those exact questions remain applicable to current Linear Leios. It is evidence that mempool semantics have long depended on protocol choices, but current relevance must be re-established against the implemented design.

## Mitigations and work already reported

The transaction cache itself was introduced to avoid downloading and validating transactions that a node had already seen and to mitigate fragmented mempools. The upstream [transaction-cache prototype issue](https://github.com/input-output-hk/ouroboros-leios/issues/1021), linked from Intersect implementation work, was closed after delivery in the `prototype-2026w35` release.

The [Consensus update of September 8, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-09-08-consensus.md) reports several related mitigations:

- fetch decisions now have bounded computation time and pending-download memory;
- newer EBs are prioritized;
- requests for missing transactions are randomized to avoid several requests saturating the same limits;
- a cache retains transactions from recent EBs, and download decisions consult both that cache and the mempool; and
- ledger-state disk reads initiated through the mempool are time-bounded so a block producer does not delay forging past its slot.

These changes address particular implementation paths. They do not establish the natural fragmentation distribution, prove that all cache and database views remain consistent, settle admission and priority policy, or bound an adversary's cost of creating persistent transaction divergence.

## Implications for candidate research tasks

### Natural fragmentation under realistic injection

The public evidence strongly supports this task. Intersect has benchmarked imposed fragmentation and recognizes missing-transaction gaps as a cost, while the transaction-cache motivation explicitly assumes that fragmented mempools need mitigation. The unfilled gap is the mapping from realistic transaction origins and submission paths to the fragmentation presented to Leios. No public document found here analyzes concentrated hosted gateways, exchanges, wallets, regional applications, multihoming, correlated bursts, or other nonuniform ingress patterns.

### Resource-bounded fragmentation attacks

The public record also supports this task. Cache occupancy, retained per-peer payloads, slow serving, unreliable peers, fixed transaction-submission limits, and parameter-boundary behavior provide concrete mechanisms. What remains missing is a common resource model: how much bandwidth, connectivity, stake, capital, transaction construction, or time an attacker needs; how persistent the effect is; and whether those resources would cause greater harm through EB withholding, diffusion denial, or another strategy serving the same objective.

### Transaction-availability supernodes

No public Intersect minutes, updates, or tracked issues found in this search propose independently operated, high-connectivity transaction-availability servers. The nearest work concerns multi-peer EB fetch, ordinary transaction submission, producer or peer serving, request hedging, and cache-assisted avoidance of redundant downloads. A supernode study would therefore explore new design space, but it would first need to show an advantage over improving those existing mechanisms and critically evaluate centralization, privacy, denial-of-service, censorship, and incentives.

## Negative space

The search did not find a public Intersect analysis that:

- estimates natural fragmentation from realistic, nonuniform transaction injection;
- derives an economically plausible upper bound on fragmentation or cache-pressure attacks;
- compares fragmentation attacks with alternative uses of the same resources;
- publishes a complete reproducible report for the May 2026 fragmentation and capacity benchmarks;
- specifies recovery and hysteresis after fragmentation or overload subsides; or
- evaluates transaction-availability supernodes or their incentive and attack models.

Absence from the searched public record does not establish that these topics have not been discussed privately or in unindexed recordings. It does show that they are not readily answered by the public minutes, updates, and issue trackers reviewed here.

## Sources

### Committee records

- [Technical Steering Committee minutes — October 8, 2025](https://github.com/IntersectMBO/tsc-documentation/blob/main/meeting-minutes/2025-tsc-meeting-minutes/meeting-minutes-october-08-2025.md)
- [Technical Steering Committee minutes — May 6, 2026](https://github.com/IntersectMBO/tsc-documentation/blob/main/meeting-minutes/2026-tsc-meeting-minutes/meeting-minutes-may-06-2026.md)

### Intersect team updates

- [Performance and Tracing update — May 29, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-05-29-performance-and-tracing.md)
- [Consensus update — June 2, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-06-02-consensus.md)
- [Consensus update — July 28, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-07-28-consensus.md)
- [Consensus update — September 8, 2026](https://github.com/IntersectMBO/cardano-updates/blob/main/blog/2026-09-08-consensus.md)

### Public engineering trackers

- [Leios requirements for the transaction mempool — `ouroboros-consensus#1509`](https://github.com/IntersectMBO/ouroboros-consensus/issues/1509)
- [Transaction-cache capacity and retention limits — `ouroboros-consensus#2290`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2290)
- [Zero EB-reference limit behavior — `ouroboros-consensus#2291`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2291)
- [Fetch-buffer transaction retention — `ouroboros-consensus#2297`](https://github.com/IntersectMBO/ouroboros-consensus/issues/2297)
- [Transaction-submission parameters for Linear Leios — `ouroboros-network#5429`](https://github.com/IntersectMBO/ouroboros-network/issues/5429)
- [Transaction-cache prototype — `ouroboros-leios#1021`](https://github.com/input-output-hk/ouroboros-leios/issues/1021)
