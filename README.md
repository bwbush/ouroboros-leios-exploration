# Ouroboros Leios — Exploration and Troubleshooting

Research-and-development exploration of [Ouroboros Leios](https://github.com/input-output-hk/ouroboros-leios), the Cardano throughput-scaling protocol ([CIP-0164](https://github.com/cardano-foundation/CIPs/blob/d07a30bca36a28535afa151915bb4900b2116d3a/CIP-0164/README.md)). This repository is a working notebook, not a deliverable: it holds the survey work, source-level maps, diagrams, verified facts, and process lessons that a scope decision will rest on.

**Provenance:** ⏳🤖 LLM-generated index, pending human review · **Charter and conventions:** [AGENTS.md](./AGENTS.md) · **Work stream:** [ARC-operating-model #83](https://github.com/input-output-hk/ARC-operating-model/issues/83)

> [!NOTE]
>
> **Current direction — October 5, 2026.** Brian and Will have agreed to begin incremental mempool and transaction-cache experiments on Musashi Dojo, including honest and adversarial workloads and an LLM-guided meta-experiment. Shared work belongs in [arc-leios-ha](https://github.com/input-output-hk/arc-leios-ha), available here as a top-level submodule; see the [agreed plan](arc-leios-ha/experiment-plan.md). This repository remains the exploration notebook and troubleshooting record. Game-theoretic experiments are postponed.

## Start here, by question

| If you want to know… | Read |
|---|---|
| What did Brian and Will agree to do next? | [Musashi Dojo experiment plan](arc-leios-ha/experiment-plan.md) — agreement, proposed classification and metrics, and AWS planning estimate |
| What simulators and models of Leios exist, and how faithful, current, and capable is each? | [Catalog of Leios simulations and models](arc-leios-ha/background/pre-scoping/leios-simulation-model-catalog.md) — 12 entries, plus a [per-entry dossier](arc-leios-ha/background/pre-scoping/leios-simulation-model-catalog/) with commit pins |
| Where is the production Leios code staged, and on which branches? | [Leios production staging branches](arc-leios-ha/background/pre-scoping/cardano-node-status.md) |
| How does a transaction actually move through the prototype node? | [Transaction-lifecycle diagram](arc-leios-ha/background/pre-scoping/leios-node-tx-lifecycle.svg), backed by [the mempool and LeiosTxCache map](arc-leios-ha/background/pre-scoping/leios-node-mempool-txcache.md) |
| How would an adversary turn a dollar budget into an attack, and when does one attack dominate another? | [The economics of attack resources](arc-leios-ha/background/pre-scoping/attack-resource-economics.md) — a resource catalog, a budget-constrained price model, and a dominance relation, built on existing game-theoretic frameworks |
| Can current evidence establish which Leios attacks dominate others, and what would each cost an adversary? | [A dominance sketch for Leios attacks](arc-leios-ha/background/pre-scoping/leios-attack-dominance-sketch.md) — a prerequisite and evidence map over the threat model's T-numbers, with the missing comparisons made explicit |
| Which parameters and inequalities decide whether blocks, votes, and certificates are created and accepted — and which are actually enforced? | [Protocol parameters and admission inequalities](arc-leios-ha/background/pre-scoping/leios-node-protocol-parameters.md), with the [timing-inequalities timeline](arc-leios-ha/background/pre-scoping/leios-timing-inequalities.svg) |
| How is the testnet and our pool doing, at a glance? | [`functionally/tidbyt-musashi`](https://github.com/functionally/tidbyt-musashi) — a 64×32 Tidbyt app over kleioscan's API, developed here and now maintained in its own repository |
| How do I turn the relay into a block producer, with a Leios voting key? | [musashi/block-producer.md](./musashi/block-producer.md) — keys, certificates, deposits, rotations |
| How do I collect data on transaction flow — push, pull, mempool, cache — from a running node? | [Collecting transaction-flow data](arc-leios-ha/background/pre-scoping/leios-tx-flow-instrumentation.md) — namespace map, config patch, jq recipes |
| What tools exist for working with a running Leios node — CLI, load generators, local devnets, offline analysis? | [Tooling for a running Leios node](arc-leios-ha/background/pre-scoping/leios-node-tooling.md) — verified by running the image's own binaries |
| How do I run a node on the musashi testnet myself? | [musashi/cheatsheet.md](./musashi/cheatsheet.md) — a podman relay, with the config-pinning and image-week traps that stop it syncing |
| What mempool and cache issues and hypotheses are still open on the team? | [Open mempool and cache issues](arc-leios-ha/background/pre-scoping/leios-mempool-cache-open-issues.md) — a #team-leios snapshot: the relay-stall/cache-staleness bug, the fragmentation-bound and bistability debates, backend/GC, cross-referenced to our records |
| Which research-sized mempool tasks could answer the team's plausibility question? | [Mempool plausibility workstream candidates](arc-leios-ha/background/pre-scoping/mempool-plausibility-workstream-candidates.md) — semi-centralized ingress, resource-bounded attacks, and a transaction-availability-service sub-study |
| How do the kleioscan chain metrics, the node's telemetry funnel, and the models' alignment quantities line up? | [Mempool-alignment metric mapping](arc-leios-ha/background/pre-scoping/leios-mempool-metrics-mapping.md) |
| What does a Leios term or parameter mean? | [Leios cheatsheet](arc-leios-ha/background/pre-scoping/leios-cheatsheet.md) — written for a new team member on day one |
| What have we actually confirmed, with a date and a source? | [facts.md](./facts.md) |
| What was done, when, and why? | [journal/phase-0.md](./journal/phase-0.md) (reverse-chronological) |
| What have we learned about *how* to do this work? | [meta-lessons-learned.md](./meta-lessons-learned.md) |

## Layout

- `AGENTS.md` — the charter: mission, goals, constraints, repository blueprint, conventions, and analysis instructions. Read before contributing.
- `arc-leios-ha/` — local submodule of Brian and Will's shared work repository; the [experiment plan](arc-leios-ha/experiment-plan.md) records the October 5 agreement.
- `CLAUDE.md` — Claude-specific addenda; defers to `AGENTS.md`.
- [Pre-scoping archive](arc-leios-ha/background/pre-scoping/) — the former `artifacts/` and `assessments/` collections, consolidated in the shared repository; synthesis documents, source maps, diagrams, and assessments (the table above).
- `musashi/` — the Musashi testnet node environment: two `podman kube` pod specs (relay and block producer), config-pinning, registration and retirement scripts, the pool's published metadata, and two guides. Pool **ΘΕΛΩ** (`THELO`) operated from epochs 64 through 84 and is now retired; no node is intentionally running. The environment is retained for analysis and possible later reactivation. Its `config/`, `data/`, and plaintext `keys/` are gitignored. The Tidbyt status display developed here now lives at [`functionally/tidbyt-musashi`](https://github.com/functionally/tidbyt-musashi).
- `journal/` — dated work log, newest first. A historical record: existing text is not edited.
- `facts.md` — verified findings, each with its date, source, and layer.
- `meta-lessons-learned.md` — append-only log of methodology and process lessons.
- `.claude/skills/` — agent skills ported from a sibling consensus study and retargeted here.
- `flake.nix` / `flake.lock` / `nix/` — the Nix development shell, **inherited from that sibling study and not yet pruned** for Leios. Its one Leios-specific addition is `nix/cardano-node-leios.nix`, which puts the prototype `cardano-cli`, `cardano-node`, `tx-firehose`, and `mempool-monitor` on `PATH` from a pinned upstream release tarball.

Other directories in the blueprint are created as needed. The former `artifacts/` and `assessments/` directories were moved into the shared repository on October 5, 2026.

## How to read the records

**Everything about the implementation is pinned.** The Leios code moves daily, so source claims cite an exact commit and the documents say so at the top. The current pin set is `ouroboros-consensus @ b56977b`, `cardano-node @ 7e33674`, `cardano-ledger @ 1587f21`, `cardano-base @ fbfb3f0` (2026-09-16), with deployed values read from the musashi testnet configuration on 2026-09-17. **Permalinks stay valid; branch tips diverge within days** — re-pin before relying on any of it, using the re-verification commands embedded in each document.

**Claims carry their layer.** A statement about the paper, the formal specification, a simulator, the implementation, and a deployed network are five different things, and the documents distinguish them. Where a number is an estimate rather than a measurement it is marked ❓ **SCRUTINY**, or ❓🤖 when it came from LLM-assisted reasoning.

**Provenance is explicit.** 🤖 means LLM-generated and human-reviewed; 👱🤖 human-drafted and LLM-refined; 🤖👱 the reverse; unmarked means human-written. See `AGENTS.md` § Conventions for the full marker set.

**Corrections are additive.** Journal entries are frozen once written; a later finding is recorded as a dated `> [!WARNING]` callout at the point of the error, leaving the original wording in place. Several such corrections already exist — they are the record working as intended, not noise.

## Temporary hosting and deliberate absences

The standalone history is temporarily published as the unrelated [`bwbush/tmp-explorations`](https://github.com/input-output-hk/ouroboros-leios/tree/bwbush/tmp-explorations) branch of `ouroboros-leios`; it is not a normal feature branch or pull-request precursor. This work falls under [`input-output-hk/ARC-operating-model` #83](https://github.com/input-output-hk/ARC-operating-model/issues/83) (“[CBU] - Leios: mempool fragmentation TBD”, labeled **Stream**, assigned to Brian W. Bush and Will Wolff). As agreed October 5, shared experiment ideas will be tracked as issues in [arc-leios-ha](https://github.com/input-output-hk/arc-leios-ha); this exploration repository retains its findings, source maps, and historical records.
