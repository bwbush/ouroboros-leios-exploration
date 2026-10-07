"""Read-only, project-scoped Cost Explorer report; money is never a float."""

import argparse
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import json
from pathlib import Path
import subprocess
import sys


SKILL = Path(__file__).resolve().parents[1]
ROOT = SKILL.parents[2]
METRIC = "UnblendedCost"
ZERO = Decimal("0")


class AwsError(RuntimeError):
    pass


class Aws:
    def __init__(self, profile):
        self.profile = profile
        self.cost_pages = 0

    def call(self, service, operation, request):
        command = [
            "aws", "--profile", self.profile, "--region", "us-east-1",
            "--no-cli-pager", "--no-paginate", service, operation,
            "--cli-input-json", json.dumps(request), "--output", "json",
        ]
        if operation == "get-cost-and-usage":
            self.cost_pages += 1
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise AwsError(f"{service} {operation}: {result.stderr.strip()}")
        return json.loads(result.stdout)


def pages(aws, operation, request):
    """Explicit pagination, preserving the request between pages."""
    request = dict(request)
    seen = set()
    while True:
        response = aws.call("ce", operation, request)
        yield response
        token = response.get("NextPageToken")
        if not token:
            return
        if token in seen:
            raise AwsError(f"{operation}: repeated pagination token")
        seen.add(token)
        request = {**request, "NextPageToken": token}


def cost_summary(responses):
    daily = defaultdict(lambda: {"cost": ZERO, "estimated": False})
    services = defaultdict(Decimal)
    record_types = defaultdict(Decimal)
    positive, negative = ZERO, ZERO
    for response in responses:
        for period in response.get("ResultsByTime", []):
            day = daily[period["TimePeriod"]["Start"]]
            day["estimated"] |= period.get("Estimated", False)
            # This helper always requests SERVICE and RECORD_TYPE groups.
            # Total can be empty or repeat across pages: never add it as well.
            for group in period.get("Groups", []):
                metric = group["Metrics"][METRIC]
                if metric["Unit"] != "USD":
                    raise ValueError(f"Expected USD, received {metric['Unit']}")
                amount = Decimal(metric["Amount"])
                if not amount.is_finite():
                    raise ValueError("Non-finite cost amount")
                service, record_type = group["Keys"]
                services[service] += amount
                record_types[record_type] += amount
                day["cost"] += amount
                if amount >= 0:
                    positive += amount
                else:
                    negative += amount
    return {
        "reported_unblended_usd": str(positive + negative),
        "positive_group_charges_usd": str(positive),
        "negative_group_adjustments_usd": str(negative),
        "any_estimated": any(v["estimated"] for v in daily.values()),
        "daily": [
            {"date_utc": k, "unblended_usd": str(v["cost"]), "estimated": v["estimated"]}
            for k, v in sorted(daily.items())
        ],
        "by_service_usd": {k: str(v) for k, v in sorted(services.items())},
        "by_record_type_usd": {k: str(v) for k, v in sorted(record_types.items())},
    }


def budget_status(charges, settings):
    check_in = Decimal(settings["check_in_usd"])
    budget = Decimal(settings["budget_usd"])
    if not ZERO < check_in <= budget:
        raise ValueError("Expected 0 < check-in <= budget")
    status = ("budget_reached" if charges >= budget else
              "check_in_with_David" if charges >= check_in else
              "below_reported_thresholds_coverage_incomplete")
    return {
        "status": status,
        "basis": "positive SERVICE/RECORD_TYPE/day groups; reported costs only",
        "check_in_usd": str(check_in),
        "budget_usd": str(budget),
        "reported_distance_to_check_in_usd": str(check_in - charges),
        "reported_distance_to_budget_usd": str(budget - charges),
        "not_a_complete_available_balance": True,
    }


def collect(aws, settings, tags, through, now):
    start = date.fromisoformat(settings["budget_start"])
    if not start <= through <= now.date():
        raise ValueError("Through-date must be between budget start and today's UTC date")
    if not tags.get("project") or not all(isinstance(v, str) and v for v in tags.values()):
        raise ValueError("Canonical tags must contain nonempty strings, including project")
    budget_status(ZERO, settings)  # Validate before paid queries.
    account = aws.call("sts", "get-caller-identity", {})["Account"]
    if account != settings["account"]:
        raise ValueError(f"Wrong AWS account: expected {settings['account']}, received {account}")

    warnings = [
        "Billing data lags and can be revised, even for earlier days; today is partial.",
        "Project-untagged, shared, or unallocated costs are excluded; coverage is incomplete.",
        "Negative adjustments are shown separately; positive-group charges drive conservative warnings.",
    ]
    tag_status = {"inspection": "available", "tags": []}
    try:
        for response in pages(aws, "list-cost-allocation-tags", {"TagKeys": list(tags)}):
            tag_status["tags"].extend(response.get("CostAllocationTags", []))
        active = {t["TagKey"] for t in tag_status["tags"] if t.get("Status") == "Active"}
        if set(tags) - active:
            warnings.append("Billing tags not confirmed active: " + ", ".join(sorted(set(tags) - active)))
    except AwsError as error:
        tag_status = {"inspection": "unavailable", "error": str(error)}
        warnings.append("Cannot inspect billing-tag activation; cost coverage is unknown.")

    def tag_filter(key):
        return {"Tags": {"Key": key, "Values": [tags[key]], "MatchOptions": ["EQUALS", "CASE_SENSITIVE"]}}

    account_filter = {"Dimensions": {"Key": "LINKED_ACCOUNT", "Values": [account]}}
    filters = {
        "project": {"And": [account_filter, tag_filter("project")]},
        "all_required_tags": {"And": [account_filter, *[tag_filter(k) for k in sorted(tags)]]},
    }
    queries, summaries = {}, {}
    for name, cost_filter in filters.items():
        request = {
            "TimePeriod": {"Start": start.isoformat(), "End": (through + timedelta(days=1)).isoformat()},
            "Granularity": "DAILY", "Metrics": [METRIC], "Filter": cost_filter,
            "GroupBy": [{"Type": "DIMENSION", "Key": key} for key in ("SERVICE", "RECORD_TYPE")],
        }
        queries[name] = request
        summaries[name] = cost_summary(pages(aws, "get-cost-and-usage", request))
        expected_days = { (start + timedelta(days=i)).isoformat() for i in range((through - start).days + 1) }
        returned_days = {d["date_utc"] for d in summaries[name]["daily"]}
        if returned_days != expected_days:
            warnings.append(f"{name}: returned billing dates do not cover the requested period exactly.")
    project, strict = summaries["project"], summaries["all_required_tags"]
    difference = Decimal(project["reported_unblended_usd"]) - Decimal(strict["reported_unblended_usd"])
    if difference:
        warnings.append("Project and all-required-tags costs differ; investigate billing attribution, not just live tags.")
    if not Decimal(project["positive_group_charges_usd"]):
        warnings.append("No positive project costs reported: this does not establish zero spending.")
    return {
        "schema_version": 1, "queried_at_utc": now.isoformat(),
        "profile": aws.profile, "account": account, "required_tags": tags,
        "queries": queries, "billing_tag_status": tag_status,
        **summaries,
        "project_minus_all_required_tags_usd": str(difference),
        "budget": budget_status(Decimal(project["positive_group_charges_usd"]), settings),
        "cost_query_pages_requested": aws.cost_pages,
        "warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", help="AWS profile; account guard remains enabled")
    parser.add_argument("--through", type=date.fromisoformat, help="Inclusive UTC billing date (default: today)")
    parser.add_argument("--save-report", action="store_true", help="Also retain timestamped JSON in gitignored reports/")
    args = parser.parse_args()
    settings = json.loads((SKILL / "settings.json").read_text())
    tags = json.loads((ROOT / settings["tags_file"]).read_text())
    now = datetime.now(timezone.utc)
    report = collect(Aws(args.profile or settings["profile"]), settings, tags, args.through or now.date(), now)
    output = json.dumps(report, indent=2) + "\n"
    if args.save_report:
        folder = SKILL / "reports"
        folder.mkdir(exist_ok=True)
        destination = folder / (now.strftime("%Y%m%dT%H%M%S.%fZ") + ".json")
        with destination.open("x") as handle:
            handle.write(output)
        print(f"Evidence saved: {destination}", file=sys.stderr)
    print(output, end="")


if __name__ == "__main__":
    try:
        main()
    except (AwsError, ValueError, KeyError, OSError, subprocess.TimeoutExpired) as error:
        print(f"Spending check failed: {error}", file=sys.stderr)
        sys.exit(1)
