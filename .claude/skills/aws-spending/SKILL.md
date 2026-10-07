---
name: aws-spending
description: Check cumulative AWS spending for the Musashi ARC-C007-HC project using its required resource tags, report service and daily costs, and flag the USD 1,500 check-in and USD 2,000 budget thresholds. Use when asked about AWS spend, cloud budget remaining, cost tracking, or deployment burn rate.
---

# AWS spending

Use the read-only helper to check Amazon Web Services (AWS) Cost Explorer. This is an on-demand check, not a scheduled monitor or an automatic spending cap.

## Scope and execution

1. Read the cloud-budget paragraph in the repository's `AGENTS.md`. The initial authorization is **USD 2,000 cumulative**, with a check-in with David at **USD 1,500**, starting October 5, 2026. Confirm that `settings.json` still matches that authorization; do not reset the budget at a month boundary or silently extend it.
2. Read `arc-leios-ha/baselining/terraform/required-tags.json`, the canonical tag set. The helper reads this file directly; do not maintain a second copy. It verifies account `381492303550` using the `arc-leios-ha` profile before querying costs. It filters to that linked account, all regions, and all services.
3. From the repository root, run:

   ```sh
   python3 .claude/skills/aws-spending/scripts/check_spending.py --save-report
   ```

   Requires the AWS command-line interface and Python 3's standard library. Credentials stay in the normal AWS credential chain; never print or copy them. Reports are timestamped JSON evidence in the skill's gitignored `reports/` directory. `--through YYYY-MM-DD` includes that UTC billing date and produces a historical cumulative report. `--profile NAME` selects another authorized profile, but does not bypass account verification. Run tests with:

   ```sh
   python3 -m unittest discover -s .claude/skills/aws-spending/scripts -p 'test_*.py'
   ```

4. If cost access fails, report the error, not zero spending. Listing billing-tag activation is optional: a linked account may lack access even when cost queries work. Do not activate tags, alter permissions, create budgets/alerts, contact David, or change running infrastructure without separate authorization.

## Interpretation and reporting

- Lead with the **reported project-tagged cumulative UnblendedCost**, date range, query time, and whether AWS marks any periods estimated. Billing dates are UTC; conversational dates are Mountain time per `AGENTS.md`. The current UTC day is partial, and earlier days may still lag.
- Show a short service breakdown and recent daily costs. Count all reported services, including storage, requests, public addresses, and transfer, not just compute. Preserve the JSON report's precision but round displayed currency sensibly.
- Compare the `project`-tag total with the **all-five-tags subset**. These overlap: never add them. A difference is a billing-tag coverage discrepancy, not proof of incorrectly tagged live resources. A zero difference also does not prove full coverage. The script retains signed adjustments and positive service/record-type/day group costs separately. Threshold warnings conservatively use the positive-group total; this is not gross invoice line-item spending or a commitment-aware cost model.
- Report distance to the check-in and budget thresholds as **provisional**, based on reported positive-group charges. At USD 1,500, tell Brian to check in with David; at USD 2,000, flag the budget as reached and request direction before further spending commitments. Never claim that this report enforces a cap or accounts for unreported usage.
- Always flag billing lag and unallocated costs. Missing/inactive billing tags, costs before activation/backfill, shared services, taxes, support, discounts, and Cost Explorer query charges may not be attributed to the project. Do not label a zero result “free,” or allocate account-wide untagged charges to this project without evidence. Activation inspection denied or missing tags means coverage is unknown, not inactive. A missing project tag is invisible to both queries.
- For a burn-rate/runway request, separate observed billing from a current-inventory estimate. Check deployed regions and resources, including volumes, addresses, snapshots, archive storage/requests, and cross-region transfer. Use current prices and label estimates ❓🤖 **SCRUTINY**. Do not extrapolate a partial day or a pre-expansion fleet into a reliable forecast. Ask for billing-owner reconciliation if attribution gaps matter to the decision.
- Retain prior reports when tracking changes. Historical AWS totals can be revised: differences between snapshots are not necessarily newly incurred usage. Share only project-scoped summaries, not credentials or unrelated account costs. This helper makes two paginated cost queries plus identity and tag-status checks; avoid rapid polling because the Cost Explorer application programming interface (API) is metered.

## Sources

- [Project authorization — repository charter](../../../AGENTS.md)
- [Required resource tags — Terraform deployment](../../../arc-leios-ha/baselining/terraform/required-tags.json)
- [GetCostAndUsage: filters, metrics, grouping, and exclusive end dates — AWS](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_GetCostAndUsage.html)
- [Cost Explorer data refresh and API charges — AWS](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html)
- [Cost allocation tag activation — AWS](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html)
- [Cost Explorer API pricing — AWS](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/)
