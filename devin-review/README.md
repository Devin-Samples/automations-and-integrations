# Devin Review

Devin Review is a proactive code review capability that analyzes new pull requests for bugs, security issues, quality problems, and style inconsistencies. It runs automatically on PRs and posts findings as review comments.

## Capabilities

| Feature | Description |
|---------|-------------|
| **Bug Detection** | Logic errors, null pointer risks, race conditions, edge cases |
| **Security Analysis** | Hardcoded secrets, injection vulnerabilities, insecure defaults |
| **PR Summarization** | Readable overviews of large diffs highlighting key changes and risks |
| **Proactive Remediation** | Automatically opens fix PRs for discovered issues (optional) |
| **Custom Rules** | Configure focus areas and sensitivity per repository |

## Setup

Devin Review is configured at the organization level in the Devin UI:

1. Navigate to **Settings > Devin Review** in your Devin organization
2. Enable Devin Review for your repositories
3. Configure review rules and sensitivity levels
4. (Optional) Enable auto-remediation for specific finding types

## How It Works

```
Developer opens PR
        ↓
Devin Review analyzes the diff
        ↓
Findings? → Posts review comments on the PR
        ↓
(Optional) Auto-remediation → Opens a fix PR
        ↓
Developer addresses findings → Merge
```

## Best Practices

- **Start with observation mode** — Enable Devin Review comments without blocking merges. Let the team calibrate trust before making it a required check
- **Customize sensitivity** — Reduce false positives by configuring which patterns and severities to flag
- **Combine with CI** — Devin Review catches logic and design issues; CI catches build/test failures. They complement each other
- **Use as a learning tool** — Devin Review findings help junior developers learn patterns and anti-patterns from every PR

## Reference

- [Devin Review documentation](https://docs.devin.ai)
- [Configuring review rules](https://docs.devin.ai)
