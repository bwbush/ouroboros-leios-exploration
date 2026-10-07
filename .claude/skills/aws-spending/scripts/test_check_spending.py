import copy
from datetime import date, datetime, timezone
from decimal import Decimal
import unittest

from check_spending import AwsError, budget_status, collect, cost_summary, pages


SETTINGS = {"account": "123", "budget_start": "2026-10-05", "budget_usd": "2000", "check_in_usd": "1500"}
TAGS = {"project": "ARC-C007-HC", "owner": "ARC"}
NOW = datetime(2026, 10, 7, tzinfo=timezone.utc)


def period(amount, record="Usage", estimated=True):
    return {"ResultsByTime": [{
        "TimePeriod": {"Start": "2026-10-05", "End": "2026-10-06"},
        "Estimated": estimated,
        "Total": {"UnblendedCost": {"Amount": "9999", "Unit": "USD"}},
        "Groups": [{"Keys": ["EC2", record], "Metrics": {
            "UnblendedCost": {"Amount": amount, "Unit": "USD"}}}],
    }]}


class FakeAws:
    profile = "test"

    def __init__(self, replies, account="123", deny_tags=False):
        self.replies = iter(replies)
        self.account = account
        self.deny_tags = deny_tags
        self.calls = []
        self.cost_pages = 0

    def call(self, service, operation, request):
        self.calls.append((service, operation, copy.deepcopy(request)))
        if service == "sts":
            return {"Account": self.account}
        if operation == "list-cost-allocation-tags":
            if self.deny_tags:
                raise AwsError("AccessDenied: linked account")
            return {"CostAllocationTags": [{"TagKey": k, "Status": "Active"} for k in TAGS]}
        self.cost_pages += 1
        reply = next(self.replies)
        if isinstance(reply, Exception):
            raise reply
        return reply


class SpendingTests(unittest.TestCase):
    def test_decimal_adjustments_and_paginated_days_without_double_count(self):
        report = cost_summary([period("0.1"), period("0.2"), period("-0.05", "Credit")])
        self.assertEqual(report["reported_unblended_usd"], "0.25")
        self.assertEqual(report["positive_group_charges_usd"], "0.3")
        self.assertEqual(report["negative_group_adjustments_usd"], "-0.05")
        self.assertEqual(len(report["daily"]), 1)
        self.assertTrue(report["any_estimated"])

    def test_empty_is_not_positive(self):
        self.assertEqual(cost_summary([])["reported_unblended_usd"], "0")

    def test_currency_rejected(self):
        response = period("1")
        response["ResultsByTime"][0]["Groups"][0]["Metrics"]["UnblendedCost"]["Unit"] = "EUR"
        with self.assertRaises(ValueError):
            cost_summary([response])

    def test_pagination_preserves_query(self):
        aws = FakeAws([{**period("1"), "NextPageToken": "next"}, period("2")])
        request = {"Filter": {"Tags": {"Key": "project", "Values": ["ARC"]}}}
        result = cost_summary(pages(aws, "get-cost-and-usage", request))
        self.assertEqual(result["reported_unblended_usd"], "3")
        self.assertEqual(aws.calls[1][2], {**request, "NextPageToken": "next"})
        self.assertNotIn("NextPageToken", request)

    def test_repeated_token_fails(self):
        aws = FakeAws([{"NextPageToken": "x"}, {"NextPageToken": "x"}])
        with self.assertRaises(AwsError):
            list(pages(aws, "get-cost-and-usage", {}))

    def test_account_guard_precedes_billing(self):
        aws = FakeAws([], account="wrong")
        with self.assertRaises(ValueError):
            collect(aws, SETTINGS, TAGS, date(2026, 10, 5), NOW)
        self.assertEqual(len(aws.calls), 1)

    def test_coverage_diagnostic_is_not_added_to_project_total(self):
        aws = FakeAws([period("12"), period("10")], deny_tags=True)
        report = collect(aws, SETTINGS, TAGS, date(2026, 10, 5), NOW)
        self.assertEqual(report["project_minus_all_required_tags_usd"], "2")
        self.assertEqual(report["budget"]["reported_distance_to_budget_usd"], "1988")
        self.assertEqual(report["billing_tag_status"]["inspection"], "unavailable")
        query = report["queries"]["project"]
        self.assertEqual(query["TimePeriod"], {"Start": "2026-10-05", "End": "2026-10-06"})
        self.assertEqual(query["Filter"]["And"][0]["Dimensions"]["Values"], ["123"])
        self.assertEqual(len(report["queries"]["all_required_tags"]["Filter"]["And"]), 3)

    def test_cost_error_fails_instead_of_zero(self):
        with self.assertRaises(AwsError):
            collect(FakeAws([AwsError("denied")]), SETTINGS, TAGS, date(2026, 10, 5), NOW)

    def test_budget_boundaries(self):
        self.assertEqual(budget_status(Decimal("1500"), SETTINGS)["status"], "check_in_with_David")
        self.assertEqual(budget_status(Decimal("2000"), SETTINGS)["status"], "budget_reached")
        self.assertEqual(budget_status(Decimal("2001"), SETTINGS)["reported_distance_to_budget_usd"], "-1")

    def test_invalid_dates_make_no_requests(self):
        for through in (date(2026, 10, 4), date(2026, 10, 8)):
            aws = FakeAws([])
            with self.assertRaises(ValueError):
                collect(aws, SETTINGS, TAGS, through, NOW)
            self.assertEqual(aws.calls, [])


if __name__ == "__main__":
    unittest.main()
