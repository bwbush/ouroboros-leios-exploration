# Architectural Intelligence Guide

## Project: Ouroboros Leios Exploration and Troubleshooting

This document is the primary context for interpreting the contents of this repository. It defines the strategic objectives, scope, and technical boundaries of this effort, and the conventions every contributor — human or LLM — is expected to follow.

This repository is a **research-and-development exploration workspace**, not a product repository. Nothing here ships. The output is understanding: reproducible experiments, written assessments, and a defensible record of what was tried, what was learned, and what remains unknown.

> [!IMPORTANT]
>
> **Current direction: initial experiment planning.** On 2026-10-05, Brian and Will agreed to pursue incremental memory-pool and transaction-cache experiments on the Musashi Dojo testnet, supporting the Leios high-confidence workstream (HCW). Shared work belongs in [arc-leios-ha](https://github.com/input-output-hk/arc-leios-ha), checked out locally as a top-level submodule. The [agreed plan](arc-leios-ha/experiment-plan.md) supersedes earlier provisional scope suggestions where they differ; it is not a fixed multi-month epic. This repository remains the exploration notebook and troubleshooting record.

## 🎯 Mission Objectives

### Phase 0 — Scope discovery foundation

1. **Primary goal:** Determine what this effort should actually be. Enumerate the open questions about [Ouroboros Leios](https://github.com/input-output-hk/ouroboros-leios) that are (a) worth answering, (b) answerable with the resources available here, and (c) not already answered by the upstream Leios team. The deliverable is a written scope statement with candidate workstreams, each sized and ranked.
2. **Secondary goal:** Establish a working environment. Get the upstream Leios artifacts — simulators, formal specifications, trace tooling, analysis scripts — building and running locally, and record what that took. A dead end that is documented is a result; an undocumented one will be paid for twice.
3. **Tertiary goal:** Build the team's shared mental model of Leios: its block classes and their roles, its diffusion and voting mechanics, its parameter space, and the failure modes that distinguish it from Praos.

### Agreed next increment — Musashi Dojo experiments

Brian and Will will record honest and adversarial experiment ideas as issues in the shared repository, classify their infrastructure requirements, and group runs to reuse deployments. They also plan a large language model (LLM) meta-experiment exploring memory-pool and transaction-cache performance; its objective and execution controls remain to be designed. Game-theoretic experiments are postponed. No individual experiment or execution schedule has yet been selected by this agreement.

**Testnet authorization — recorded 2026-10-05 from Brian's report.** Sebastian, who leads the Leios engineering effort, has confirmed that Brian and Will may obtain as much test ADA as needed and are fully authorized to use the Musashi Dojo testnet for this work, including adversarial experiments that disrupt or break that network. Disruption of this designated testnet is an authorized experimental outcome, not by itself a reason to reject a proposed experiment. This authorization does not extend to mainnet, other networks, unrelated infrastructure, or spending beyond the approved budget. Record the target network identity and run configuration before execution so that the authorization is applied to the intended network. This planning record does not itself start a run or reactivate the retired pool.

**Cloud budget — recorded 2026-10-05 from Brian's report.** David has allocated USD 2,000 for Amazon Web Services (AWS) infrastructure; check in with him when cumulative spending reaches USD 1,500. Count compute, storage, data transfer, addresses, and supporting services, not just node instance charges. The [plan's node-hour estimates](arc-leios-ha/experiment-plan.md#aws-planning-estimate) are conditional planning arithmetic, not a spend commitment or a validated node-sizing recommendation.

**Mandatory AWS resource tags — specified by Brian on 2026-10-06.** All provisioned AWS resources that support tags must carry these exact, case-sensitive pairs: `owner=ARC`, `environment=development`, `project=ARC-C007-HC`, `costCenter=C0505`, and `provisionedBy=brian.bush@iohk.io`. This applies across regions and includes disks, network interfaces, and supporting infrastructure—not only instances. Use the shared [tag policy](arc-leios-ha/baselining/terraform/required-tags.json); verify coverage in plans and after deployment, including implicitly created resources. Document AWS objects that do not support tags rather than silently omitting taggable resources. Do not assume provider defaults tag every AWS-created child object.

### Standing charter — troubleshooting

Independently of phase, this repository is the home for **R&D-level troubleshooting** of Leios: reproducing anomalies, bisecting simulation divergences, explaining surprising trace output, and isolating whether an observed behavior is a protocol property, a specification gap, an implementation bug, or a measurement artifact. Troubleshooting work is first-class and gets the same evidentiary treatment as planned experiments — a reproduction recipe, a `lessons-learned.md` entry, and a 📊 **EVIDENCE** marker tying the conclusion to its data.

## 🎯 Goals and Constraints

### Primary goals

1. **Explain, don't just observe.** A measurement without a mechanism is an anecdote. Every reported number should come with a claim about *why* it has that value, and that claim should be falsifiable.
2. **Reproducibility over volume.** One experiment a colleague can re-run from a clean checkout is worth more than five that live only in a terminal scrollback. Every experiment carries its own build and run instructions.
3. **Separate the protocol from its implementations.** Leios exists as a paper, as one or more formal specifications, and as one or more simulators and node implementations. Findings must state which of these they are about. A simulator artifact is not a protocol property, and a protocol property is not automatically an implementation guarantee.
4. **Quantify the parameter space, don't sample it anecdotally.** Leios behavior depends on a large, interacting parameter set (stage lengths, block-size and rate limits, committee and quorum sizes, network topology and bandwidth). Conclusions should name the region of parameter space they hold in.

### Hard constraints

- **No authority over upstream.** This repository does not own the Leios specification or its reference implementations. Proposed changes go upstream through normal review; nothing here is a decision of record for the protocol.
- **Public-by-default protocol, private-by-exception materials.** Leios is developed in the open. Anything placed in this parent repository's `background/` is the exception and is treated as private/proprietary — see the blueprint below. The shared repository's `background/pre-scoping/` is a separate collection of explicitly transferred work products, not a transfer of the parent's private reference materials.
- **Small-scale compute by default.** Assume a single workstation outside the explicitly approved Musashi Dojo AWS budget above. Where a question genuinely requires a geographically distributed multi-node testbed, say so explicitly in the experiment's `design-history.md` rather than substituting a single-machine run and reporting it as if it answered the question. Single-machine "large network" runs measure CPU and scheduler contention, not network consensus behavior.
- **Simulation results are not deployment claims.** Never present simulator output as a statement about mainnet behavior without naming the modeling assumptions that carry the inference.

### Additional requirements and considerations

- **State the baseline.** Leios claims are throughput and latency claims, and throughput and latency claims are meaningless without a comparator. Name it: Praos as deployed, Praos at some parameterization, or a prior Leios variant.
- **Version everything.** Record the upstream commit, simulator version, parameter file, and seed for every run. An unversioned result cannot be defended.
- **Prefer upstream tooling.** Before writing a new simulator, analysis script, or trace parser, look for the upstream one. Divergent tooling produces divergent numbers and costs more to reconcile than it saves.
- **Negative and null results are recorded, not discarded.** They are the main product of a scope-discovery phase.

### Formal-methods workstream

Leios has an Agda specification lineage upstream, and the properties at issue — safety, liveness, and the throughput-under-adversary arguments — are exactly the kind that reward mechanization. Where this repository touches formal methods, the expectations are:

- Flag any safety or liveness claim in prose that would benefit from mechanized proof, and note whether such a proof already exists upstream or in the literature.
- Distinguish clearly between *proved*, *specified but unproved*, *simulated*, and *asserted*.
- Keep executable specifications executable: a specification that no longer typechecks or runs against the current toolchain is a liability, and its breakage should be recorded in `lessons-learned.md`.

## 👥 Project Staff

| Person | Role | Responsibility |
|--------|------|----------------|
| Brian W. Bush (`bwbush`) | Everything | Scope discovery, upstream-artifact survey, experiments and troubleshooting, assessments, and the repository itself |
| Will Wolff | Shared experiment work | Joint planning and execution with Brian in `arc-leios-ha`, as agreed 2026-10-05 |

Brian maintains this exploration notebook; Brian and Will now collaborate in the shared repository. Two documentation expectations remain:

- **No assumed review.** Collaboration does not establish that any particular artifact has received independent review. The written record must carry explicit scrutiny: use the ❓ / ❓🤖 **SCRUTINY** markers, the `facts.md` sourcing discipline, and append-only experiment logs on your own work, not only on someone else's.
- **Write for the next person, not for today.** Every document should read as though handed to a colleague who has not been in any of the conversations — see the document-class reader table in [`.claude/skills/reader-audit/SKILL.md`](.claude/skills/reader-audit/SKILL.md). Single-author repositories decay into private notation faster than shared ones.

The roles this effort is expected to draw on if and when it is staffed further: researcher (literature and upstream-artifact survey, protocol analysis, knowledge-base curation), prototyper (simulation runs, trace analysis, benchmark harnesses, troubleshooting reproductions), formal-methods engineer (specification reading and mechanization, safety and liveness analysis), and network engineer (diffusion and propagation measurement, topology modeling, bandwidth accounting).

## 📣 Communication

To be established. Record the engagement's Slack channel and stakeholder list here once they are set, in the form `[#channel](URL)` with the workspace named.

## 📋 Key Facts

Verified facts established through this effort are maintained in [`facts.md`](./facts.md). Consult that file for confirmed findings before reasoning from first principles, and add to it whenever something is confirmed rather than leaving the confirmation buried in a journal entry. Each fact carries its date and its source.

## 📂 Repository Blueprint

Directories are created on first use; in the scope-discovery phase most of this is a target layout rather than a current one.

- `/arc-leios-ha/`: Local submodule checkout of Brian and Will's [shared work repository](https://github.com/input-output-hk/arc-leios-ha). This is an authored work repository, not a vendored upstream implementation; its own documents and code belong there directly. See the [initial experiment plan](arc-leios-ha/experiment-plan.md). Do not transfer private `background/` material merely because this checkout is local.
- `/arc-leios-ha/background/pre-scoping/`: The former `artifacts/` and `assessments/` collections, consolidated on 2026-10-05: notes, diagrams, briefs, synthesis documents, and technical assessments. The simulation catalog retains its supporting subdirectory. Rendered PNG previews remain gitignored. Every assessment, regardless of location, must include a `## Sources` section at the end with entries in `[Title — Publisher/Context](URL)` format; use `Title — Publisher/Context (internal)` for internal documents without public URLs. Split the sources section into named subsections (e.g., `### General Sources`, `### Protocol Sources`, `### Cardano Sources`) when the source base spans multiple distinct domains.

  **Quality-assessment Afterword:** Only add an `## Afterword: Quality Scrutiny` section when explicitly asked to do so. When asked, append it after all existing content and structure it as five subsections:
  1. **Sources correspond to retrievable URLs** — attempt to fetch each cited URL; note which are accessible, which redirect, and which are unreachable.
  2. **Internal consistency** — verify that the document's claims do not contradict one another and that conclusions follow from the stated evidence.
  3. **Accuracy against sources** — flag paraphrases presented as quotations, omitted qualifications, and claims that go beyond what the sources state.
  4. **Areas of greatest uncertainty** — list unsourced claims, single-source claims, and design-intent attributions that could not be independently verified.
  5. **Robustness of primary conclusions** — assess whether the main conclusions survive the uncertainties identified above.

- `/background/`: **[PRIVATE/PROPRIETARY]** Centralized storage for reference materials, papers, internal roadmaps, and sensitive communications. Nothing in this directory is quoted verbatim into an outward-facing document without checking its distribution status first.
- `/arc-leios-ha/experiments/`: Shared code spikes, simulation harnesses, trace-analysis scripts, troubleshooting reproductions, and their records. Shared work belongs here so collaborators can use the shared repository without this parent checkout. The parent's `/experiments/` is reserved for personal or private explorations, if needed. Each experiment subdirectory must contain two append-only files:
  - `design-history.md` — records design decisions and their rationale as the experiment evolves.
  - `lessons-learned.md` — records findings, surprises, and actionable conclusions.

  Both files are append-only: do not edit or delete previous entries. The only permitted modifications to past entries are ~~strikethrough~~ to mark superseded content, or adding a `> [!TIP]` block referencing a later finding. An experiment directory should also carry enough build/run instructions (a `README.md`, a `Makefile`, or both) that a clean checkout can reproduce its results.
- `/musashi/`: the live node environment for the `musashi` Leios prototype testnet — `podman kube` pod specs for a relay and a block producer, a script that pins the live network configuration, credential and registration scripts, the pool's published metadata, two guides (`cheatsheet.md`, `block-producer.md`). The Tidbyt status display for the network and the pool was developed here and now lives in its own repository, [`functionally/tidbyt-musashi`](https://github.com/functionally/tidbyt-musashi); changes belong there, not here. The pinned configuration, the chain database, and any block-producer keys are gitignored: the network's configuration rolls, and a committed snapshot of it is a trap rather than a record.
- `/journal/`: phase-keyed logs (e.g., `phase-0.md`). Entries are in **reverse-chronological order**: when inserting a new entry, add it as the first H3 under today's H2 section. Horizontal rules (`---`) separate date sections (H2 headings) **only**; never use a horizontal rule within a journal entry. **Weekly summary entries** use a short bulleted list, 5–7 bullets maximum. Each bullet names a *topic or activity area* — not an individual implementation step — written at a level a non-specialist could understand, in neutral tone without asserting conclusions. **A weekly summary in the journal is derived from a longer weekly report**: first write the single-file weekly report in `/weekly-reports/`, then derive the journal bullets by summarizing each H2 as one bullet, hyperlinked to that H2's anchor in the weekly-report file. **Weekly plan entries** follow the same brevity discipline: a single bulleted list of focus items only, no theme/sequencing/risks/deliverables prose. Ticket numbers go at the **end** of each bullet (`Description [#NN].`), obvious recurring items are omitted, and sub-issues nest as indented bullets.
- `/weekly-reports/`: Detailed single-file weekly reports, named by the Friday end-of-week date (e.g., `2026-09-18.md`). One H2 per topic, a one-paragraph description under each, written to be readable on its own.
- `/_templates/`: Reusable semantic-marker snippets for use when authoring documents.
- `README.md` (top level): Human entry point — what this repository is, the current phase, and a question-indexed map of the artifacts. `AGENTS.md` remains the charter.
- `facts.md` (top level): Verified findings, dated and sourced.
- `/.claude/skills/`: Agent skills, ported from the sibling `arc-mn-consensus` study and retargeted here. Four prose skills (`abstract`, `executive-summary`, `highlights`, `tighten-prose`) plus `humanize-prose` and `reader-audit`; `deep-dive` and `qa-afterword` for assessments; `archival-index` for triaging Drive / Confluence / GitHub corpora; `gslide` and `slides-iog` for briefing decks; `ticket-create` / `ticket-update` / `ticket-tree` for GitHub Projects work; and [`aws-spending`](.claude/skills/aws-spending/SKILL.md) for read-only project-tagged cloud spending and budget checks. The document-class reader table in [`reader-audit`](.claude/skills/reader-audit/SKILL.md) is the canonical reader definition for this repository and is referenced by the other prose skills; keep it in sync with this blueprint.
- `meta-lessons-learned.md` (top level): Append-only log of project-level lessons about research methodology, document quality, and process gaps — the project-level analog of the per-experiment `lessons-learned.md` files. Update whenever a cross-cutting failure mode or process gap is identified.
- `flake.nix` / `flake.lock`: The Nix development shell. **Inherited from a sibling study and not yet pruned for this effort** — it currently carries a large toolchain (Lean, Rust, Substrate build tooling, Python scientific stack, R) whose relevance to Leios is unestablished. Treat additions the way the existing entries are written: every package gets a comment saying which experiment needs it and why. Removals are welcome once an entry is confirmed unneeded.

## 📝 Conventions

**Working timezone.** Brian is currently using Mountain Daylight Time (MDT, UTC−06:00). Interpret conversational dates such as "today," "yesterday," and meeting dates in that timezone unless he specifies otherwise. Preserve the original timezone on source timestamps and telemetry; the container's UTC clock does not define Brian's local date. This preference was confirmed on 2026-10-02 and should be revisited when daylight saving time changes.

**Spelling.** Use American English throughout this repository (e.g., "color" not "colour", "centralized" not "centralised", "behavior" not "behaviour", "finalized" not "finalised", "utilization" not "utilisation", "catalog" not "catalogue"). This applies to prose, comments, and identifiers introduced in this repo; preserve the spelling of identifiers from upstream code and of direct quotations as written.

**Markdown line width.** Do not hard-wrap prose in Markdown documents to a fixed column limit. Write each paragraph or bullet as a single logical line and let editors and renderers soft-wrap it. Fixed-width hard wrapping makes edits and diffs noisier and reflows badly across viewers; reserve hard line breaks for actual paragraph, list-item, and block boundaries.

**Visual accessibility.** Use colorblind-safe color schemes in plots and UIs — the [Okabe-Ito palette](https://jfly.uni-koeln.de/color/) (sky blue, vermillion, yellow, bluish green, blue, orange, reddish purple) is the established reference and remains distinguishable under the three most common forms of color vision deficiency. Avoid red/green as the sole distinguisher of state. For any color-coded state, include a non-color redundancy (symbol, label, pattern, or position) so meaning survives if color is invisible or stripped.

**Acronyms and abbreviations.** Define every acronym or abbreviation at its first use in each document, then use the short form freely. Because documents are read independently, "already defined elsewhere in the repository" does not count; define it again here. Exempt only terms universally understood outside this project (e.g., CPU, RAM, URL); spell out domain-specific abbreviations — including the Leios block-class abbreviations (IB, EB, RB), and terms such as VRF, KES, DAG, UTxO, TPS, and DA — on first use in each document.

**Reference documents by Markdown hyperlink.** When you refer to another document in this repository, link it with a Markdown hyperlink `[title](relative/path)` so the reader can open it, rather than naming it in bare backticks. Backticks are for showing a literal path or filename as a string; a reference the reader may want to follow is a link. Tooling files under `.claude/`, where relative links are brittle, are exempt.

**Minimize GitHub ticket references.** Avoid referring to GitHub issues or pull requests by number in analytical and outward-facing documents (assessments, synthesis artifacts, reports); name the technique, mechanism, document, or result instead. Ticket references are acceptable in memory-like and progress-tracking documents — the journal, weekly reports, `lessons-learned.md`, experiment `design-history.md`, `meta-lessons-learned.md` — and where a ticket is genuinely the subject. When referencing an upstream ticket, qualify it with its repository (`ouroboros-leios#NN`), since a bare `#NN` here is ambiguous.

**Frozen historical documents.** Weekly reports and journal entries are historical records; do not edit their existing text. Surface a factual correction by adding a `> [!WARNING]` callout at the point of the error, noting the correction and its date, and leave the original wording in place.

**Provenance of numbers.** Any quantitative result in this repository should be traceable to the run that produced it: upstream commit, tool version, parameter file, seed, and machine. Where a number is an estimate rather than a measurement, mark it ❓ **SCRUTINY** (or ❓🤖 if LLM-derived) rather than letting it acquire false authority by repetition.

**Upstream fidelity.** When describing Leios mechanics, prefer the current upstream specification over the paper, and the paper over secondhand summaries — and say which you used. Where they disagree, that disagreement is itself a finding worth a journal entry.

The following semantic markers are used throughout this repository:

- 🧪 **HYPOTHESIS**: A theory or technical assumption about to be tested.
- 📊 **EVIDENCE**: Links specific experimental data or benchmark results to a claim.
- 🛑 **BLOCKER**: High-priority technical hurdle requiring architectural resolution.
- 🏛️ **ADR**: (Architecture Decision Record) Formal marker for a finalized design choice.
- 🛡️ **SPEC**: A specific requirement that an implementation or parameterization must satisfy.
- ⚠️ **RISK**: Potential risk needing consideration and evaluation.
- ❓ **SCRUTINY**: Marks a quantitative estimate or conclusion produced by a human that has not been empirically verified.
- ❓🤖 **SCRUTINY**: Marks a quantitative estimate or conclusion produced by LLM-assisted reasoning, requiring particular scrutiny.

Provenance markers for journal entries and documents:

- ⏳🤖 Generated by an LLM, pending human review.
- 🤖 Generated by an LLM, reviewed by a human.
- 👱🤖 Drafted by a human, collaboratively refined by an LLM.
- 🤖👱 Drafted by an LLM, collaboratively refined by a human.
- Unmarked entries were solely drafted by a human.

The provenance marker on an assessment document is propagated to its journal summary entry.

**Protocol cheatsheet.** `arc-leios-ha/background/pre-scoping/leios-cheatsheet.md` is a living reference document, first populated on 2026-09-17 (Leios mechanisms and the protocol-parameter set; the Ouroboros-family, comparators, and baselines sections are still stubs). Update it whenever a Leios mechanism, block class, parameter, or comparable protocol is newly discussed or explored more deeply — including anything mentioned in an assessment, journal entry, or brainstorming document. Each entry must include at least one source link. It is intended as an onboarding resource for new team members, so descriptions should be objective and self-contained.

**Vendored submodules and patches.** If upstream Leios repositories are vendored as git submodules, modifications are **not** committed inside the submodule. They live as tracked `.patch` files re-applied on build, with the patch files — plus the experiment's `Makefile` — as the reproducible source of truth: a submodule reset or a fresh clone must reconstruct the tree from the patches alone. Therefore, whenever you edit a vendored submodule in place, regenerate the corresponding patch in the same change and commit it. Verify patch currency non-destructively with `git apply --reverse --check <patch>` before relying on a patch set, and wire every patch into the experiment's `make patches` target — an unapplied patch silently has no effect. Where a submodule is shared by more than one experiment, each experiment owns a disjoint patch set and all of them must be accounted for on any reset or re-apply.

The authored `arc-leios-ha` work repository is not subject to this vendored-code restriction. Changes belong directly in that repository; committing them and advancing the parent gitlink remain separate Git operations and require the usual user direction.

**Transaction-formatter exception, authorized 2026-10-08.** For [transaction-formatter](transaction-formatter/) only, Brian explicitly authorized direct, logically scoped commits and amendments while developing an upstream contribution. This submodule is a checkout of `IntersectMBO/cardano-node`, initially pinned to the deployed w40 revision `8206f9f843d46f9fa9a58449ed2387e2c0aa1a84`; it is not a standalone formatter package. Preserve the reviewable branch history rather than maintaining duplicate patches. This authorization does not permit commits in the parent or `arc-leios-ha`, nor creation of pull requests. Local commits must be published to an agreed fork before another checkout can resolve a parent gitlink pointing to them.

Brian subsequently authorized the [personal fork](https://github.com/bwbush/cardano-node) and publication of `configurable-transaction-logging` on the same date. The submodule URL and local `origin` use that fork; `upstream` remains `IntersectMBO/cardano-node`. Parent/shared commits and pull requests still require separate direction.

## ⏳ Timeline

The initial shared experiment direction was agreed on **2026-10-05 (Mountain Daylight Time)**. Work proceeds incrementally through experiment ideas and selected tickets rather than a predefined multi-month epic. No run dates or fixed completion date have been committed.

## 🤖 Persona & Analysis Instructions

When working in this repository, LLM assistants should:

1. **Assume a Senior Systems Architect and Distributed-Systems Researcher role.** Prioritize correctness, safety, and liveness, and apply the "No Free Lunch" principle across throughput, latency, storage, and fault-tolerance trade-offs. Leios buys throughput with structure; the interesting question is always what it pays.
2. **Be explicit about the layer under discussion.** Paper, formal specification, simulator, node implementation, and deployed network are five different objects. Name which one a claim is about, every time.
3. **Maintain traceability.** Link each 🧪 **HYPOTHESIS** in the journal to the code in `/arc-leios-ha/experiments/` (or the parent's `/experiments/` for private explorations) that tests it and to the resulting 📊 **EVIDENCE**.
4. **Be formal-methods aware.** Flag claims about safety and liveness that would benefit from mechanized verification, and note where Agda, TLA+, Isabelle, or Coq treatments already exist upstream or in the literature.
5. **Troubleshoot by bisection, not by narrative.** When explaining an anomaly, isolate it — smaller parameter set, fewer nodes, fixed seed, one changed variable — before proposing a mechanism. Record the reduction, not just the conclusion.
6. **Prefer "unknown" to a confident guess.** In a scope-discovery phase, a well-posed open question is a deliverable. Say what would settle it.
7. **Write to `facts.md` when something is confirmed**, and to `meta-lessons-learned.md` when the process itself failed.

## 💬 Useful Prompts

- **Status summary:** "Summarize the last 10 journal entries. List new 🛑 BLOCKER items or 🏛️ ADR entries."
- **Scope status:** "What candidate workstreams have been identified so far, and what is the current ranking and rationale?"
- **Open questions:** "List the open questions about Leios recorded so far, with what evidence would settle each."
- **Reproduction check:** "For each experiment directory, does it record the upstream commit, parameters, and seed needed to reproduce its results?"
- **Landscape:** "What protocols have been assessed as comparators so far? Summarize their throughput and finality properties."

## Instructions specific to particular LLMs

- *Claude*, please read [CLAUDE.md](./CLAUDE.md) for additional instructions.
