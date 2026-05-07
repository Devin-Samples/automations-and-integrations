# Security Scanning Integrations

Automated pipelines that connect SAST/SCA scanning tools to Devin for closed-loop remediation. When a scan detects findings above a configurable severity threshold, Devin is triggered to read the report, remediate the issues, and push a fix — which the scanner then re-verifies.

## Pattern

```
[SAST/SCA Tool] scans code
        ↓
Findings above threshold?
    YES → Webhook / CI step calls Devin API
        ↓
Devin reads scan report, remediates findings, pushes fix
        ↓
CI re-runs scan → findings resolved? → PR unblocked
```

## Available Integrations

| Tool | Directory | Status | Integration Method |
|------|-----------|--------|-------------------|
| SonarQube / SonarCloud | [`sonarqube/`](sonarqube/) | Available | Webhook on Quality Gate failure |
| Snyk | [`snyk/`](snyk/) | Available | Webhook on new vulnerability |
| Checkmarx | [`checkmarx/`](checkmarx/) | Planned | Webhook on scan completion |
| Trivy | [`trivy/`](trivy/) | Available | CI pipeline step with JSON output |

## Key Design Decisions

- **Loop prevention**: Filter out PRs authored by `devin-ai-integration[bot]` to prevent Devin from remediating its own scan results in an infinite loop
- **Severity threshold**: Configure which finding severities trigger remediation (recommended: HIGH and CRITICAL only)
- **One-time attempt**: Limit Devin to one remediation attempt per finding to prevent runaway sessions
- **Report format**: Pass the scan report as a structured artifact (JSON, XML) so Devin can parse findings programmatically
