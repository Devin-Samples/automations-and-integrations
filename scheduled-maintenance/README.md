# Scheduled Maintenance

Proactive operations and maintenance patterns using Devin's scheduled sessions feature. These run on a recurring cadence (daily, weekly, monthly) without human initiation, handling code hygiene tasks that would otherwise accumulate as technical debt.

## Available Patterns

| Pattern | Directory | Cadence | Description |
|---------|-----------|---------|-------------|
| Dependency Updates | [`dependency-updates/`](dependency-updates/) | Weekly | Bump outdated packages, run tests, open PRs |
| Code Hygiene | [`code-hygiene/`](code-hygiene/) | Monthly | Remove dead code, clean imports, fix deprecations |
| License Compliance | [`license-compliance/`](license-compliance/) | Monthly | Audit dependencies for license policy violations |

## How Scheduled Sessions Work

1. Configure a schedule in the Devin UI or via API (cron expression or preset intervals)
2. At the scheduled time, Devin starts a session with the configured prompt and target repo
3. Devin performs the maintenance task, runs tests, and opens a PR
4. Engineers review and merge the PR if tests pass

## Configuration Tips

- **Stagger schedules** across repos to avoid CI congestion
- **Set ACU budgets** per scheduled session to control cost
- **Use playbooks** to ensure consistent methodology across repos
- **Monitor PR merge rate** — if PRs pile up unmerged, reduce frequency or simplify scope
