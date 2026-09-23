# The economics of attack resources: a budget-constrained model and a dominance relation

**Scope and stance.** This is a broad, analytic, *defensive* assessment. It builds the groundwork a game-theoretic analysis of Leios attacks needs before any specific attack is modeled: a catalog of the physical and economic resources an adversary consumes, a price model that turns one adversarial budget in US dollars (USD) into a feasible mix of those resources, and a mathematical definition of what it means for one attack to *dominate* another. It proposes no attack and provides no operational parameters for mounting one; every quantity here serves the defender's question — *is it worth defending against this, relative to that?* It is deliberately abstract, and it defers the empirical calibration of its own constants to the measurement and simulation work cataloged elsewhere in this repository.

**Provenance marker: ⏳🤖** — LLM-drafted, pending human review. Estimates carry ❓🤖.

**Abbreviations.** EB endorser block, RB ranking block, SPO stake pool operator, VRF verifiable random function, KES key evolving signature, BLS Boneh–Lynn–Shacham signatures, MEV maximal (or miner) extractable value, DoS denial of service, TPS transactions per second, ₳ ada, USD US dollars, RPD rational protocol design, MDP Markov decision process, SSG Stackelberg security game, CIP Cardano Improvement Proposal. Defined again at first substantive use.

---

## 0. What already exists, and what this borrows

The instinct to model an attacker as a budget converted into resources is not new, and the defensive literature has settled several of the pieces this assessment needs. The task here is less to invent than to assemble the right existing tools around the specific resource set that Leios exposes. Six strands are directly load-bearing; § 5 relates them to what follows.

- **The griefing factor** (Vitalik Buterin, *A Griefing Factor Analysis* and *The Triangle of Harm*) is the ratio of victim loss to attacker cost, and the design goal is to bound it. It is the closest existing thing to the dominance relation this assessment needs, and § 4 generalizes it rather than replacing it.
- **Rational protocol design** (Garay, Katz, Maurer, Tackmann, Zikas; extended to Bitcoin by Badertscher, Garay, Maurer, Tschudi, Zikas, and to 51% attacks by Badertscher, Lu, Zikas) frames security as a two-party game in which the adversary pays to corrupt participants and gains utility only by breaking a guarantee; a protocol is secure when no attack strategy has positive utility. That utility-must-be-negative test is exactly the defensive posture adopted in § 4.
- **The economic-limits argument** (Eric Budish, *The Economic Limits of Bitcoin and the Blockchain*) ties the flow cost of attacking a chain to the flow of rewards, and warns that a one-off "stock" prize can dwarf a "flow" cost. Leios's attacks are overwhelmingly flow-cost throughput denials, so the stock/flow distinction is one this model must carry explicitly (§ 3.4).
- **Quantitative security frameworks** (Gervais, Karame, Wüst, Glykantzis, Ritzdorf, Čapkun, *On the Security and Performance of Proof of Work Blockchains*) show how to turn protocol and network parameters into an MDP whose optimal adversarial policy is computable. This assessment stops short of an MDP but keeps its habit of expressing the adversary's problem as a constrained optimization.
- **Cost-of-takeover accounting** (Joseph Bonneau, *Hostile Blockchain Takeovers*; the crypto51 methodology) distinguishes *buying* a resource from *renting* it, and finds renting and bribery routinely cheaper than acquisition — a distinction § 2 and § 3 make first-class, because a rented botnet and purchased stake price completely differently.
- **Cardano's own incentive model** (Brünjes, Kiayias, Koutsoupias, Stouka, *Reward Sharing Schemes for Stake Pools*) supplies the equilibrium pool count, pledge behavior, and cost structure of an honest stake pool operator (SPO), which is a baseline against which an attacker's stake-related costs can be measured. The deployed musashi parameters, rather than that paper, supply the numerical deposit and `minPoolCost` values discussed in § 2.3.

The one framing this assessment adds is the explicit **budget simplex**: prior work usually fixes the resource (hashpower, or stake) and prices it. Leios attacks draw on a *heterogeneous* resource basket — compute, bandwidth, hosted nodes, stake, transaction fees, time, and specialized position — and the interesting defensive question is how a fixed USD budget is best *allocated across* that basket. That is a resource-allocation problem of the kind studied in Stackelberg security games (Tambe and successors), and § 3 casts it in that shape.

---

## 1. A resource catalog

An attack consumes resources. Before pricing anything, we enumerate them at the level the user asked for — CPU, bandwidth, servers, ada — and no finer. The catalog is deliberately protocol-agnostic in its axes and Leios-specific only in its annotations, so that the same axes serve any attack in the [dominance sketch](../artifacts/leios-attack-dominance-sketch.md)'s three-way split (resource defects, conformance gaps, protocol properties).

We distinguish five quantitative resource types, an explicit time horizon, and one categorical prerequisite. An attack is therefore not a point in an undifferentiated seven-dimensional vector space: it has a quantitative resource vector, a duration, and a position gate.

| Sym | Resource | Unit | Metered how | Leios relevance |
|---|---|---|---|---|
| $r_1$ | **Compute** | CPU-core-hours | flow | VRF grinding (T2/T3) is CPU-bound; forging valid-looking EBs and signatures is cheap per unit but scales with attack volume |
| $r_2$ | **Bandwidth (egress)** | GB transferred over the attack window, with peak Mbit/s as a capacity constraint | flow | the binding resource for the withholding/leeching family (T21/T22): certifying a "cold" 12 MB EB needs hundreds of MB/s; diffusion denial is an egress race |
| $r_3$ | **Hosted nodes** | node-hours over the attack window | flow | node count and geographic spread set topology position; the red team's cluster is 10 geo-distributed pools plus one large one |
| $r_4$ | **Stake** | ₳ held (bonded) | stock (capital) | committee seats and EB eligibility are stake-weighted; a pool with zero active stake seats in no committee |
| $r_5$ | **Protocol fees and deposits** | ₳ spent (flow) + ₳ locked (refundable) | mixed | pool deposit (refundable), key deposits, and the per-transaction fees an attack actually pays; conflicting-transaction attacks turn on which of these are paid |
| $\tau$ | **Time horizon** | wall-clock hours the attack must be sustained | model horizon | adaptive-corruption vectors (T32/T33) and any "accumulate then strike" attack require a longer horizon; $\tau$ determines the accumulated quantities of the flow resources above |
| $q$ | **Position / privilege** | categorical prerequisites, potentially overlapping | prerequisite gate | the Anastasia audit states prerequisites per finding: admitted peer, access to valid committee material, producer credentials, backend state, and ordering conditions all gate reachability |

Two axes deserve comment because they behave unlike the rest.

**$q$ is a gate, not a quantity or a total order.** An admitted peer, a holder or relay of valid committee material, and an elected producer satisfy different prerequisites; one role does not automatically include every network condition of another. Seven audit findings require no attacker stake or private protocol key, but they still depend on conditions such as admission, victim selection, an established fetch session, offer ordering, a useful genuine hash, or use of the SQLite backend. Authentication, admission control, state quotas, and stake-gating act on different parts of this gate.

**$r_4$ (stake) is capital, not consumption.** Bonded stake is not spent; it is locked and exposed to slashing or to devaluation if the attack succeeds and the token price falls. Its *cost* is therefore an opportunity cost (foregone yield) plus a risk premium, not its face value — the distinction Budish draws as flow-versus-stock and § 3.4 formalizes. Treating a $10B stake requirement as a $10B "cost" overstates it for a brief attack and understates it for one that craters the token.

---

## 2. Pricing each resource

The adversary begins with a budget $B$ in USD. Each resource has a price that converts USD into units of that resource. Prices are not constants: several are convex (the marginal unit costs more than the last), which is where the interesting defensive structure lives.

Let $x = (x_1, \dots, x_5)$ be the quantitative resources acquired over a fixed attack window $\tau$, and let $q$ be the categorical position. Two dollar quantities must remain separate. The **capital requirement** $K_{\tau,q}(x)$ is the cash or collateral that must be available, including purchased stake and refundable deposits. The **economic cost** $C_{\tau,q}(x)$ is what utility loses over the window: consumed compute, bandwidth, node rental, fees, opportunity cost, bribes, and expected devaluation or slashing loss. A refundable deposit can therefore be large in $K$ and small in $C$.

### 2.1 Compute $r_1$ — linear, rentable, deeply liquid

Cloud and spot compute is effectively linear over any range an attacker needs: $p_1(x_1) = c_1 \, x_1$, with $c_1$ the USD per core-hour (order $10^{-2}$ USD/core-hour on spot markets ❓🤖). VRF grinding is the only Leios vector that is genuinely compute-bound, and CIP-0161 (Ouroboros Phalanx) is designed precisely to make $c_1$ for grinding rise by a factor of ~$10^{10}$ — i.e., to bend this line into a wall. Absent that, compute is the cheapest and most liquid resource in the basket, and rarely the binding constraint.

### 2.2 Bandwidth $r_2$ — linear to a ceiling, then convex

Egress bandwidth prices linearly up to what a hosting provider will sell on one machine, then convexly as the attacker must fan out across machines or regions to sustain aggregate rate: $p_2(x_2) = c_2 \, x_2$ for $x_2 \le \bar{x}_2$, and steeper beyond, because sustaining hundreds of MB/s to *many distinct peers* is not the same purchase as a single fat pipe. This convex-beyond-a-knee shape is the whole reason the withholding/leeching family has a defensive handle: the protocol parameter $L_\text{diff}$ and the EB size set where the knee bites (Knutsson's simulation: a passive attacker fails above ~50 Mbit/s for a 12 MB EB, and resisting a leeching attacker pushes the requirement past ~250 Mbit/s). Raising the required $x_2$ past a provider's linear ceiling is a cost amplification the defender controls through parameters, not code.

### 2.3 Hosted nodes $r_3$ and stake $r_4$ — the buy-versus-rent fork

Nodes price approximately linearly in node-hours, $p_3(x_3) = c_3 \, x_3$ (equivalent to order $50$–$300$ USD/node-month in the upstream front-running cost model, Hetzner to AWS ❓). The subtle resource is stake.

Stake can be **bought** or **rented (delegated/bribed)**, and the two price entirely differently — the Bonneau distinction. Let $S$ be the ada the attack requires and $P$ the USD/ada price.

- **Buying** moves the market. Acquiring $S$ ada at depth is not necessarily $S \cdot P$ dollars; its capital requirement is $\int_0^{S} P(s)\,ds$ where $P(s)$ rises with cumulative purchase (slippage). A convex, depth-dependent first approximation is:
$$p_4^\text{buy}(S) = P \cdot S \cdot \big(1 + \tfrac{1}{2}\,\kappa\, \tfrac{S}{D}\big),$$
with $D$ a market-depth parameter and $\kappa$ a slippage coefficient. This expression belongs in $K$, not directly in $C$: purchased stake remains capital, while its economic cost over the attack window is opportunity cost plus expected price-collapse or slashing loss (§ 3.4).
- **Renting** — via a bribe to existing stakeholders to delegate or misbehave — has cost set by what those holders forgo, i.e., roughly their reward flow over the attack window plus a premium. This is generally *far cheaper* than buying for a short attack, which is precisely Bonneau's and the crypto51 finding, and it interacts with Cardano's reward-sharing equilibrium (Brünjes–Kiayias): the bribe must beat honest pool profitability, a quantity that model pins down.

The pool deposit (500 ₳ on musashi) and applicable key deposits (2 ₳) are deterministic capital requirements for registration. Because they are refundable, their face value enters $K$ while only their holding cost and loss risk enter $C$. The 170 ₳ `minPoolCost` parameter is different: it is a floor on the pool's declared operating-cost deduction from available rewards, not a registration payment or an amount spent to win a production slot. It can affect foregone or distributed rewards but is not an entry toll.

### 2.4 Fees $r_5$ — and the determinism discount

Per-transaction fees follow the network's fee formula (Cardano: $\text{fee} = a + b\cdot\text{size}$; the MEV cost model uses $a = 0.155381$, $b = 0.0000440576$ ₳/byte). The defensively critical feature is Cardano's **determinism property**: a transaction that fails to be included consumes no fee. An attacker flooding $n$ mutually-conflicting transactions to fragment mempools pays for the *one* that lands, not for $n$. So for the conflicting-transaction family,
$$p_5^\text{conflict}(n) \approx (a + b\,\bar{s}) \quad\text{independent of } n,$$
a near-constant fee component, not one linear in $n$. This does **not** make the attack's total marginal cost zero: constructing and disseminating additional transactions still consumes compute, bandwidth, peer capacity, and temporarily usable funds. The inclusion-fee asymmetry is therefore a potentially important discount whose effect on total cost must be measured, not itself a dominance result. Confirming it against the current ledger rules is flagged in the dominance sketch as load-bearing and cheap. ❓🤖

### 2.5 Time $\tau$ — the accounting horizon

Time does not price independently. The quantities $x_1$, $x_2$, and $x_3$ are already totals over $\tau$, so multiplying them by time again would double-count duration. Rates such as CPU cores, Mbit/s, and node count are integrated over $\tau$ to obtain those quantities; rented stake, bribes, and capital holding cost are likewise accumulated over the same window. This is why `maxKeyAge` (374 epochs) matters to "accumulate silently then strike" adaptive-corruption vectors (T32/T33): it bounds the relevant accumulation horizon, though a calibrated model must still specify how each required resource grows with that horizon.

### 2.6 Summary: the cost function

For a fixed horizon $\tau$, position $q$, and acquisition mode $m$ (buy or rent), write the economic cost schematically as
$$
C_{\tau,q,m}(x) = c_1x_1 + p_2(x_2) + c_3x_3 + c^{m}_{4,\tau}(x_4) + p_5(x_5) + \rho\tau L,
$$
where $L$ is refundable capital locked in deposits and $c^{m}_{4,\tau}$ is either the holding-and-risk cost of purchased stake or the accumulated bribe/rental cost. Separately, $K_{\tau,q,m}(x)$ includes the cash required to acquire purchased stake and post deposits. Position $q$ is a feasibility gate: a producer attack is infeasible unless the credentials, stake eligibility, and required locked capital are available. The exact functions remain inputs to calibration rather than facts established here.

---

## 3. The budget-constrained resource-allocation model

Now the game-theoretic framing the user asked for: an adversary holds USD and chooses a resource mix to maximize the damage of *some* attack, subject to affording it.

### 3.1 Feasible set

Given available capital $B$, the feasible quantitative region for a fixed horizon, position, and acquisition mode is
$$\mathcal{F}_{\tau,q,m}(B) = \{\,x \in \mathbb{R}^5_{\ge 0}: K_{\tau,q,m}(x) \le B\,\}.$$
If the selected capital-requirement functions are convex, this continuous slice is convex. The full feasible set is a union of slices across categorical positions and buy-versus-rent modes and therefore need not itself be convex. As $B$ grows, it expands non-uniformly: purchased stake and high-aggregate bandwidth may grow slowly while liquid compute grows quickly. That shape is a defensive artifact because it says which attacks become affordable and in what order; “budget simplex” is only an intuition, not a mathematical characterization of the full set.

### 3.2 An attack as a requirement, damage as an outcome

Model an attack $A$ as (i) a **resource requirement** — the minimum mix $x^A$ needed to run it at intensity 1, possibly with an intensity multiplier $\lambda_A \ge 0$ scaling that mix — and (ii) a **damage function** $H_A(\lambda_A, \text{env})$ giving the harm inflicted (in USD-equivalent to victims, or in a protocol-health unit such as lost certified-EB throughput) at that intensity in a network environment `env`. The environment carries the parameters the defender controls: $L_\text{diff}$, EB size, committee size, mempool capacity, `maxKeyAge`, and the reward flow.

The adversary's problem, for a chosen objective (throughput denial, value extraction, safety violation, operator attrition — the § 2 objectives of the dominance sketch), is
$$
\max_{A \in \mathcal{A},\ \lambda_A \ge 0} \; U_A \;=\; V_o\big(H_A(\lambda_A,\text{env})\big) \;-\; C_{\tau,q,m}(\lambda_A x^A)
\qquad\text{s.t.}\qquad K_{\tau,q,m}(\lambda_A x^A) \le B,
$$
where the common objective-specific function $V_o$ translates an outcome into adversary *value* (for extraction it can be profit; for pure griefing it can be harm scaled by a malice weight). Using one $V_o$ is necessary for cross-attack comparison; attack-specific valuations would make “dominance” depend on arbitrary rescaling. This is the rational-protocol-design utility, specialized to a capital budget, and cast as the Stackelberg *follower's* best response to a defender who has already committed to `env`.

For readability, the fixed subscripts $\tau,q,m$ on $K$ and $C$ are suppressed below.

### 3.3 The defender's reading

The protocol is **secure against $A$ under budget $B$** in the RPD sense when
$$\max_{\lambda_A:\ K(\lambda_A x^A)\le B} U_A \;\le\; 0,$$
i.e., no affordable intensity yields positive adversary utility. The defender's levers are visible in the formula: raise $K$ or $C$ (make the resource mix harder to finance or costlier to consume — Phalanx on $r_1$, the bandwidth knee on $r_2$, admission controls on $q$), lower $V_o$, or lower $H_A$ for fixed intensity. Refundable deposits mainly raise $K$ and their holding cost contributes to $C$; they should not be treated as consumed expenditure. The security test is budget-relative: an attack with negative utility at small $B$ can turn positive at large $B$ if damage keeps scaling while marginal economic cost flattens.

### 3.4 Stock, flow, and the risk of self-defeat

Two corrections keep the model honest, both from the prior literature.

**Flow versus stock (Budish).** Flow costs (compute, bandwidth, nodes, rented stake, fees, holding costs) accrue per unit time; the prize may be a one-off stock (a single double-spend, a single extracted MEV opportunity). A model that compares a flow cost to a stock prize will mis-rank persistent throughput attacks against one-shot extraction attacks unless both are put on the same footing — either by integrating the flow over the attack window or by amortizing the stock prize. This assessment's $U_A$ must be evaluated over a fixed window $\tau$ with both sides expressed as totals over $\tau$.

**Self-defeat (Budish's collapse term, and the proof-of-stake literature).** For stake-based attacks, a successful attack that damages confidence may lower $P$, devaluing the attacker's own bonded stake $r_4$. This adds an expected term such as $-\Delta_P(H_A)\cdot S$ to utility — a possible disincentive absent when the relevant stake or infrastructure is rented without residual exposure. Its magnitude is an empirical input, not a guaranteed restraint. Position obtained through stake carries exposure that an ordinary admitted peer may lack, but peer admission and network access are not therefore costless.

---

## 4. A dominance relation

The user asked for a formula for one attack dominating another. The right object generalizes both Pareto dominance (used informally in the dominance sketch) and Buterin's griefing factor.

### 4.1 Definitions

Fix an environment `env`, attack window $\tau$, capital budget $B_0$, and adversary objective $o$. Define the attack-specific best affordable intensity
$$\lambda_A^*(B_0,o) \in \arg\max_{\lambda\ge0:\ K(\lambda x^A)\le B_0}\left[V_o(H_A(\lambda,\text{env}))-C(\lambda x^A)\right].$$
Write its realized economic cost as $c_{B_0,o}(A)=C(\lambda_A^*x^A)$, its capital requirement as $k_{B_0,o}(A)=K(\lambda_A^*x^A)$, and its realized damage as $h_{B_0,o}(A)=H_A(\lambda_A^*,\text{env})$, all evaluated over $\tau$. The subscripts matter: optimized outcomes can change with budget and objective.

**Griefing ratio.** For positive economic cost, $\displaystyle g_{B_0,o}(A)=h_{B_0,o}(A)/c_{B_0,o}(A)$ — victim harm per unit attacker cost. A zero-cost case must be handled separately rather than divided by zero. A protocol-level bound takes the supremum over the attack family and stated budget range.

**Pareto dominance (cost–damage).** $A$ **weakly dominates** $B$, written $A \succeq B$, iff
$$c_{B_0,o}(A) \le c_{B_0,o}(B) \quad\text{and}\quad h_{B_0,o}(A) \ge h_{B_0,o}(B),$$
with strict dominance $A \succ B$ if at least one inequality is strict. This is a partial order; most attack pairs are incomparable, and saying so is informative.

### 4.2 The proposed relation: budget-relative dominance

Pareto dominance is too weak (it rarely fires across a heterogeneous basket) and the griefing ratio is too aggregated (it hides the budget at which an attack becomes best). The relation this assessment proposes combines them by asking which attack a rational adversary *actually chooses* at each budget:

> **$A$ is strictly preferred to $B$ at budget $B_0$ and objective $o$**, written $A \succ_{B_0,o} B$, iff both attacks have a feasible positive intensity under $K\le B_0$ and their optimized outcomes satisfy
> $$V_o(h_{B_0,o}(A))-c_{B_0,o}(A) > V_o(h_{B_0,o}(B))-c_{B_0,o}(B).$$

This is decision-relevant: it says that a rational adversary with $B_0$ dollars pursuing objective $o$ prefers $A$. It reduces to the special cases the literature uses:

- When $V_o(h)=h$ and costs are equal, strict preference reduces to greater realized damage.
- When realized damages are equal, strict preference reduces to lower realized economic cost — “the same harm for fewer resources.”
- If $A$ strictly Pareto-dominates $B$ at a specified $(B_0,o)$, then it is strictly preferred under a common $V_o$ when either cost is strictly lower or damage is strictly higher and $V_o$ is strictly increasing over that interval. This implication is conditional; it is not invariant to budget, objective, or attack-specific valuation scales.

### 4.3 The dominance frontier

Collecting, for each budget $B_0$, the utility-maximizing attack

$$A^*(B_0,o) \in \arg\max_{A\in\mathcal A}\;\max_{\lambda\ge0:\ K(\lambda x^A)\le B_0}\left[V_o(H_A(\lambda,\text{env}))-C(\lambda x^A)\right]$$

traces a **dominance frontier**: the attack a rational adversary of each wealth would mount for objective $o$. This is the defender's prioritization curve. Its shape answers the meeting's question directly:

- If, across the whole plausible budget range for objective $o = $ throughput denial, $A^\*$ is never a mempool-fragmentation attack, the room's loose consensus holds *for that objective*.
- If $A^*$ switches to a fragmentation attack beyond some budget because its measured total-cost and damage functions yield greater utility, then fragmentation is *not* dominated at that scale, and the crossover budget is the number the defender needs. A near-constant fee component or a heavy tail alone is insufficient to establish that crossover.

The tail of fragmentation severity is one input to $H_\text{frag}$, but tail class alone neither determines boundedness nor fixes scale. The relevant comparison requires a stated risk functional — such as expected utility, a quantile, or conditional value at risk — together with a calibrated severity distribution and total-cost curve. The dominance frontier is the formal object that unifies the cost model and that distribution once those choices are explicit.

### 4.4 A worked schematic (illustrative, not calibrated)

To show the machinery without claiming numbers: take objective $o$ = throughput denial, window $\tau$ = one epoch. Consider three attacks.

| Attack | Position gate $q$ | Binding resource | Cost shape | Damage shape |
|---|---|---|---|---|
| Peer-triggered resource exhaustion (audit LEI-008-class) | admitted and selected peer; SQLite backend | access and sustained storage growth | total cost unknown | source establishes row growth; exhaustion not executed |
| Withholding / leeching (T21/T22) | producer | egress $r_2$ | convex past bandwidth knee | rises with EB size, capped by $L_\text{diff}$ |
| Mempool fragmentation (T27/conflicting-tx) | funded submitter and network access | fees, bandwidth, and submission capacity | inclusion-fee component may be nearly flat; total cost unknown | unknown distribution and scale |

The audit suggests that some peer-triggered defects may have low protocol-credential requirements, but it does not establish their network-access cost or enough common damage measurements to prove dominance. Once a defect is patched, its corresponding attack leaves the frontier for that release. Among protocol-property attacks, neither withholding nor fragmentation can be placed on the frontier until their total-cost functions, damage distributions, objective, and risk functional are calibrated. Whether a crossover exists in the plausible budget range is the empirical question a scoped study could answer. ❓🤖

---

## 5. Relation to the existing frameworks, and what this leaves open

The model above is a specialization, not a novelty. Its utility function and no-positive-utility security test ($U_A \le 0$) come from rational protocol design; its dominance relation extends Buterin's griefing factor with a budget and objective; its stock/flow and self-defeat corrections are Budish's; its buy-versus-rent distinction is Bonneau's; and its constrained-allocation framing resembles a Stackelberg follower's problem. Cardano's reward-sharing work informs stake incentives, while deployed musashi configuration supplies the local protocol-parameter values. What is assembled here is the **heterogeneous resource basket priced from a single budget**, with the **budget-relative dominance frontier** as the defender's prioritization object.

Four things are deliberately left for the calibrated successor to this groundwork:

1. **The constants.** $c_1, c_2, c_3$, the slippage $\kappa$ and depth $D$, the bribe premium, and the holding rate $\rho$ are all empirical. The repository's [Leios node protocol parameters](../artifacts/leios-node-protocol-parameters.md) records relevant network constants, while the upstream maximal-extractable-value (MEV) cost-estimate corpus contains hosting and transaction-cost estimates; the rest require market data.
2. **The damage functions $H_A$.** These are what the simulators produce. The measured-$\pi_1 \to p_\text{eb} \to P_\text{certified}$ pipeline gives $H$ for certification-delay attacks; the mempool simulators give $H_\text{frag}$ and, critically, its tail. This is the bridge from this abstract model to candidate workstreams (a) and (d).
3. **The objective function $V_o$.** For extraction objectives it can use measurable yield; for griefing it encodes adversary preferences that a defensive model should sweep across rather than fix. It must remain common across the attacks being compared.
4. **Multi-round and adaptive play.** The model here is single-shot over a window $\tau$. Adaptive corruption (T32/T33), repeated bribery, and the balancing-attack interaction with Praos are dynamic games; the MDP habit from Gervais et al. is the natural next step, and is out of scope for groundwork.

The defensive payoff of stopping at groundwork is a disciplined list of unknowns rather than a ranking: peer-triggered defects may have low credential requirements but environment-dependent access costs; protocol-property attacks may be bandwidth-, stake-, topology-, or transaction-flow-driven; and budget-relative utility supplies a common comparison only after capital requirements, economic costs, damage, objectives, and risk treatment are calibrated.

---

## Sources

### Game-theoretic and economic frameworks

- [SoK: Tools for Game Theoretic Models of Security for Cryptocurrencies — Azouvi & Hicks, Cryptoeconomic Systems](https://arxiv.org/abs/1905.08595)
- [Rational Protocol Design: Cryptography Against Incentive-Driven Adversaries — Garay, Katz, Maurer, Tackmann, Zikas](https://crypto.ethz.ch/publications/files/GKMTZ13.pdf)
- [But Why Does It Work? A Rational Protocol Design Treatment of Bitcoin — Badertscher, Garay, Maurer, Tschudi, Zikas](https://eprint.iacr.org/2018/138.pdf)
- [A Rational Protocol Treatment of 51% Attacks — Badertscher, Lu, Zikas](https://eprint.iacr.org/2021/897.pdf)
- [The Economic Limits of Bitcoin and the Blockchain — Eric Budish, NBER Working Paper 24717](https://www.nber.org/papers/w24717)
- [On the Security and Performance of Proof of Work Blockchains — Gervais, Karame, Wüst, Glykantzis, Ritzdorf, Čapkun, ACM CCS 2016](https://eprint.iacr.org/2016/555.pdf)

### Attack-cost accounting and incentives

- [A Griefing Factor Analysis / The Triangle of Harm — Vitalik Buterin](https://vitalik.eth.limo/general/2017/07/16/triangle_of_harm.html)
- [Hostile Blockchain Takeovers (Short Paper) — Joseph Bonneau, FC 2018](https://fc18.ifca.ai/bitcoin/papers/bitcoin18-final17.pdf)
- [Cost of a 51% Attack for Different Cryptocurrencies — Crypto51 (methodology)](https://www.crypto51.app/)
- [Reward Sharing Schemes for Stake Pools — Brünjes, Kiayias, Koutsoupias, Stouka, EuroS&P 2020](https://arxiv.org/pdf/1807.11218)
- [Stackelberg Security Games (SSG) Basics and Application Overview — Sinha, Fang, An, Kiekintveld, Tambe](https://personal.ntu.edu.sg/boan/papers/Milindchapter.pdf)

### Leios-specific inputs (internal / upstream)

- [Leios threat model v0.4 — Nagel, Panagiotakos, `ouroboros-leios/docs/threat-model.md`](https://github.com/input-output-hk/ouroboros-leios/blob/main/docs/threat-model.md)
- [Leios MEV corpus, including the front-running cost model — `ouroboros-leios/docs/mev/`](https://github.com/input-output-hk/ouroboros-leios/tree/main/docs/mev)
- Security Audit Report — Ouroboros Consensus — Leios, Anastasia Labs v1.0, 2026-09-01 (internal; `background/audit-report-20260902.pdf`) — finding-specific prerequisite gates used to define $q$

### This repository

- [A dominance sketch for Leios attacks](../artifacts/leios-attack-dominance-sketch.md) — the informal three-way split and objective taxonomy this assessment formalizes
- [Leios node protocol parameters](../artifacts/leios-node-protocol-parameters.md) — deposits, `minPoolCost`, committee size, and the certification-gap parameters used as constants
- [Catalog of Leios simulations and models](../artifacts/leios-simulation-model-catalog.md) — the source of the damage functions $H_A$ the calibrated successor needs
