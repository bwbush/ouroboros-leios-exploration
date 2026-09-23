#!/usr/bin/env python3
"""Test epoch block counts against the pool's Praos expectation.

The primary rate test uses the fact that a sum of independent Poisson counts
is itself Poisson.  A Monte Carlo Pearson discrepancy test checks the complete
per-epoch sequence, and a conditional Monte Carlo test checks whether blocks
are unusually clustered across epochs independently of the total count.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import math
import sys
from pathlib import Path
from typing import Iterable, TextIO

import numpy as np
from scipy.stats import chi2, poisson


DEFAULT_GENESIS = Path(__file__).with_name("config") / "shelley-genesis.json"


def positive_float(value: str) -> float:
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        raise argparse.ArgumentTypeError("must be a positive finite number")
    return result


def nonnegative_int(value: str) -> int:
    result = int(value)
    if result < 0:
        raise argparse.ArgumentTypeError("must be nonnegative")
    return result


def positive_int(value: str) -> int:
    result = int(value)
    if result <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return result


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Analyze observed block counts under a Poisson model.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    source = p.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--log",
        action="append",
        type=Path,
        metavar="PATH",
        help="plain or .gz node log; repeat for rotated logs",
    )
    source.add_argument(
        "--counts",
        type=Path,
        metavar="CSV",
        help="CSV with epoch, blocks, and optional expected_rate columns",
    )
    p.add_argument("--first-epoch", type=nonnegative_int, help="first complete epoch in logs")
    p.add_argument("--last-epoch", type=nonnegative_int, help="last complete epoch in logs")
    rate = p.add_mutually_exclusive_group()
    rate.add_argument("--expected-rate", type=positive_float, help="expected blocks per epoch")
    rate.add_argument("--stake", type=positive_float, help="pool active stake in lovelace")
    p.add_argument(
        "--total-active-stake",
        type=positive_float,
        help="network active stake in lovelace; required with --stake",
    )
    p.add_argument(
        "--genesis",
        type=Path,
        default=DEFAULT_GENESIS,
        help="Shelley genesis used for epoch length and active-slot coefficient",
    )
    p.add_argument("--confidence", type=float, default=0.95, help="confidence level")
    p.add_argument("--simulations", type=positive_int, default=100_000, help="Monte Carlo replicates")
    p.add_argument("--seed", type=int, default=20260923, help="Monte Carlo random seed")
    return p


def open_text(path: Path) -> TextIO:
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return path.open(encoding="utf-8", errors="replace")


def json_payload(line: str) -> dict | None:
    start = line.find("{")
    if start < 0:
        return None
    try:
        value = json.loads(line[start:])
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def counts_from_logs(
    paths: Iterable[Path], first: int, last: int, epoch_length: int
) -> tuple[list[int], list[int]]:
    counts = [0] * (last - first + 1)
    leadership_slots: list[set[int]] = [set() for _ in counts]
    forged: set[tuple[int, str]] = set()
    for path in paths:
        with open_text(path) as stream:
            for line in stream:
                record = json_payload(line)
                if record is None:
                    continue
                data = record.get("data")
                if not isinstance(data, dict) or not isinstance(data.get("slot"), int):
                    continue
                slot = data["slot"]
                epoch = slot // epoch_length
                if first <= epoch <= last and data.get("kind") == "TraceStartLeadershipCheck":
                    leadership_slots[epoch - first].add(slot)
                if data.get("kind") != "TraceForgedBlock":
                    continue
                block_id = str(data.get("block", f"slot:{slot}"))
                if first <= epoch <= last and (slot, block_id) not in forged:
                    forged.add((slot, block_id))
                    counts[epoch - first] += 1
    return counts, [len(slots) for slots in leadership_slots]


def counts_from_csv(path: Path) -> tuple[list[int], list[int], list[float | None]]:
    rows: list[tuple[int, int, float | None]] = []
    with path.open(newline="", encoding="utf-8") as stream:
        for raw in csv.reader(stream):
            if not raw or not any(field.strip() for field in raw) or raw[0].lstrip().startswith("#"):
                continue
            try:
                epoch = int(raw[0].strip())
                blocks = int(raw[1].strip())
            except (ValueError, IndexError):
                if not rows and raw[0].strip().lower() == "epoch":
                    continue
                raise ValueError(f"invalid CSV row: {raw!r}") from None
            if epoch < 0 or blocks < 0:
                raise ValueError(f"epoch and blocks must be nonnegative: {raw!r}")
            expected = None
            if len(raw) >= 3 and raw[2].strip():
                expected = float(raw[2])
                if not math.isfinite(expected) or expected <= 0:
                    raise ValueError(f"expected_rate must be positive: {raw!r}")
            rows.append((epoch, blocks, expected))
    if not rows:
        raise ValueError("counts CSV contains no data rows")
    epochs = [row[0] for row in rows]
    if len(set(epochs)) != len(epochs):
        raise ValueError("counts CSV contains duplicate epochs")
    return epochs, [row[1] for row in rows], [row[2] for row in rows]


def exact_poisson_interval(total: int, exposure: float, confidence: float) -> tuple[float, float]:
    alpha = 1.0 - confidence
    lower = 0.0 if total == 0 else 0.5 * chi2.ppf(alpha / 2, 2 * total) / exposure
    upper = 0.5 * chi2.ppf(1 - alpha / 2, 2 * (total + 1)) / exposure
    return float(lower), float(upper)


def monte_carlo_pvalue(observed: float, statistics: Iterable[np.ndarray], simulations: int) -> tuple[float, float]:
    exceedances = sum(int(np.count_nonzero(batch >= observed - 1e-12)) for batch in statistics)
    p_value = (exceedances + 1) / (simulations + 1)
    standard_error = math.sqrt(p_value * (1 - p_value) / (simulations + 1))
    return p_value, standard_error


def fixed_discrepancy_batches(rng: np.random.Generator, expected: np.ndarray, simulations: int) -> Iterable[np.ndarray]:
    width = len(expected)
    batch_size = min(10_000, max(1, 5_000_000 // width))
    remaining = simulations
    while remaining:
        size = min(batch_size, remaining)
        draws = rng.poisson(expected, size=(size, width))
        yield np.sum((draws - expected) ** 2 / expected, axis=1)
        remaining -= size


def conditional_discrepancy_batches(
    rng: np.random.Generator, total: int, probabilities: np.ndarray, simulations: int
) -> Iterable[np.ndarray]:
    width = len(probabilities)
    conditional_expected = total * probabilities
    positive = conditional_expected > 0
    batch_size = min(10_000, max(1, 5_000_000 // width))
    remaining = simulations
    while remaining:
        size = min(batch_size, remaining)
        draws = rng.multinomial(total, probabilities, size=size)
        yield np.sum(
            (draws[:, positive] - conditional_expected[positive]) ** 2 / conditional_expected[positive], axis=1
        )
        remaining -= size


def main() -> int:
    args = parser().parse_args()
    if not 0 < args.confidence < 1:
        raise SystemExit("--confidence must be between 0 and 1")
    simulations = args.simulations
    if (args.stake is None) != (args.total_active_stake is None):
        raise SystemExit("--stake and --total-active-stake must be supplied together")

    genesis = None
    if args.log or args.stake is not None:
        with args.genesis.open(encoding="utf-8") as stream:
            genesis = json.load(stream)

    derived_rate = None
    if args.stake is not None:
        active_slots = float(genesis["activeSlotsCoeff"])
        epoch_length = int(genesis["epochLength"])
        sigma = args.stake / args.total_active_stake
        if sigma > 1:
            raise SystemExit("--stake cannot exceed --total-active-stake")
        derived_rate = epoch_length * (1 - (1 - active_slots) ** sigma)
    default_rate = args.expected_rate if args.expected_rate is not None else derived_rate

    if args.log:
        epoch_length = int(genesis["epochLength"])
        if args.first_epoch is None or args.last_epoch is None:
            raise SystemExit("--log requires --first-epoch and --last-epoch (complete epochs only)")
        if args.first_epoch > args.last_epoch:
            raise SystemExit("--first-epoch cannot exceed --last-epoch")
        if default_rate is None:
            raise SystemExit("--log requires --expected-rate or --stake with --total-active-stake")
        observed, leadership_checks = counts_from_logs(
            args.log, args.first_epoch, args.last_epoch, epoch_length
        )
        epochs = list(range(args.first_epoch, args.last_epoch + 1))
        expected = np.full(len(observed), default_rate, dtype=float)
        incomplete = [
            (epoch, checks)
            for epoch, checks in zip(epochs, leadership_checks, strict=True)
            if checks != epoch_length
        ]
        for epoch, checks in incomplete:
            print(
                f"WARNING: epoch {epoch} has leadership checks for {checks}/{epoch_length} slots; "
                "verify log retention and producer uptime.",
                file=sys.stderr,
            )
    else:
        if args.first_epoch is not None or args.last_epoch is not None:
            raise SystemExit("--first-epoch and --last-epoch apply only to --log")
        epochs, observed, row_rates = counts_from_csv(args.counts)
        if any(rate is None for rate in row_rates) and default_rate is None:
            raise SystemExit("supply --expected-rate/--stake or expected_rate in every CSV row")
        expected = np.array([rate if rate is not None else default_rate for rate in row_rates], dtype=float)

    x = np.asarray(observed, dtype=int)
    n = len(x)
    total = int(x.sum())
    expected_total = float(expected.sum())
    observed_mean = total / n
    mean_low, mean_high = exact_poisson_interval(total, n, args.confidence)
    ratio_low, ratio_high = exact_poisson_interval(total, expected_total, args.confidence)
    ratio = total / expected_total
    rate_p = min(1.0, 2 * min(float(poisson.cdf(total, expected_total)), float(poisson.sf(total - 1, expected_total))))

    fixed_stat = float(np.sum((x - expected) ** 2 / expected))
    rng = np.random.default_rng(args.seed)
    fixed_p, fixed_se = monte_carlo_pvalue(
        fixed_stat, fixed_discrepancy_batches(rng, expected, simulations), simulations
    )

    conditional_result: tuple[float, float, float] | None = None
    if n > 1 and total > 0:
        probabilities = expected / expected_total
        conditional_expected = total * probabilities
        conditional_stat = float(np.sum((x - conditional_expected) ** 2 / conditional_expected))
        conditional_p, conditional_se = monte_carlo_pvalue(
            conditional_stat,
            conditional_discrepancy_batches(rng, total, probabilities, simulations),
            simulations,
        )
        conditional_result = conditional_stat, conditional_p, conditional_se

    level = 100 * args.confidence
    print("Epoch counts")
    print("epoch  observed  expected")
    for epoch, value, expectation in zip(epochs, x, expected, strict=True):
        print(f"{epoch:5d}  {value:8d}  {expectation:8.4f}")
    print()
    print("Rate estimate")
    print(f"epochs:                       {n}")
    print(f"observed / expected total:    {total} / {expected_total:.4f}")
    print(f"observed mean per epoch:      {observed_mean:.4f}")
    print(f"exact {level:g}% CI for mean:       [{mean_low:.4f}, {mean_high:.4f}]")
    print(f"observed / expected ratio:    {ratio:.4f}")
    print(f"exact {level:g}% CI for ratio:      [{ratio_low:.4f}, {ratio_high:.4f}]")
    print(f"exact two-sided rate p-value: {rate_p:.4f}")
    print()
    print("Epoch-to-epoch diagnostics")
    print(f"fixed-rate Pearson statistic: {fixed_stat:.4f}")
    print(f"Monte Carlo p-value:          {fixed_p:.4f} (MC SE {fixed_se:.4f})")
    if conditional_result is None:
        print("conditional dispersion test:  unavailable (requires >=2 epochs and >=1 block)")
    else:
        statistic, p_value, standard_error = conditional_result
        print(f"conditional Pearson statistic:{statistic:9.4f}")
        print(f"conditional Monte Carlo p:    {p_value:.4f} (MC SE {standard_error:.4f})")
    if n < 30:
        print()
        print(
            "CAUTION: fewer than 30 complete epochs; treat all tests as descriptive. "
            "The exact interval shows the present uncertainty."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
