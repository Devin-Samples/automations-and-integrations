# Snyk → Devin Integration

Automatically trigger Devin to remediate vulnerabilities when Snyk detects HIGH or CRITICAL severity findings in your dependencies or source code.

## Architecture

```
Developer pushes code
        ↓
GitHub Actions runs `snyk test` (SCA) or `snyk code test` (SAST)
        ↓
HIGH/CRITICAL vulnerabilities found?
    YES → Parse JSON output → Call Devin API with structured findings
        ↓
Devin upgrades dependencies / patches code → pushes fix
        ↓
CI re-runs Snyk scan → vulnerabilities resolved → PR unblocked
```

## Loop Prevention

- The workflow checks `github.event.pull_request.user.login` — if the author is `devin-ai-integration[bot]`, Devin is **not** re-triggered
- A configurable `SNYK_DEVIN_ATTEMPT` label prevents multiple remediation attempts on the same PR

---

## GitHub Actions Workflow

Save as `.github/workflows/snyk-devin.yml`:

```yaml
name: Snyk Security Scan + Devin Remediation

on:
  pull_request:
    types: [opened, synchronize, reopened]
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

env:
  SEVERITY_THRESHOLD: high  # Trigger Devin for "high" and "critical" only

jobs:
  snyk-scan:
    runs-on: ubuntu-latest

    # Loop prevention: skip Devin-authored PRs
    if: github.event.pull_request.user.login != 'devin-ai-integration[bot]'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install dependencies
        run: npm ci

      - name: Install Snyk CLI
        run: npm install -g snyk

      - name: Authenticate Snyk
        run: snyk auth ${{ secrets.SNYK_TOKEN }}

      - name: Run Snyk test (SCA)
        id: snyk_sca
        continue-on-error: true
        run: |
          snyk test \
            --json \
            --severity-threshold=${{ env.SEVERITY_THRESHOLD }} \
            > /tmp/snyk_sca_results.json 2>&1 || true

      - name: Run Snyk Code test (SAST)
        id: snyk_sast
        continue-on-error: true
        run: |
          snyk code test \
            --json \
            --severity-threshold=${{ env.SEVERITY_THRESHOLD }} \
            > /tmp/snyk_sast_results.json 2>&1 || true

      - name: Process findings and trigger Devin
        if: github.event_name == 'pull_request'
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
          SEVERITY_THRESHOLD: ${{ env.SEVERITY_THRESHOLD }}
        run: |
          python3 .github/scripts/trigger_devin_snyk.py \
            --sca-results /tmp/snyk_sca_results.json \
            --sast-results /tmp/snyk_sast_results.json \
            --repo "${{ github.repository }}" \
            --branch "${{ github.head_ref }}" \
            --pr-number "${{ github.event.pull_request.number }}" \
            --severity-threshold "${{ env.SEVERITY_THRESHOLD }}"
```

---

## Python Script: Parse Snyk Findings & Trigger Devin

Save as `.github/scripts/trigger_devin_snyk.py`:

```python
#!/usr/bin/env python3
"""
Parse Snyk JSON output and create a Devin session to remediate findings.

Supports both SCA (snyk test) and SAST (snyk code test) results.

Usage:
    python trigger_devin_snyk.py \
        --sca-results /tmp/snyk_sca_results.json \
        --sast-results /tmp/snyk_sast_results.json \
        --repo owner/repo \
        --branch feature-branch \
        --pr-number 42 \
        --severity-threshold high
"""

import argparse
import json
import os
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError

DEVIN_API_URL = "https://api.devin.ai/v1/sessions"

SEVERITY_ORDER = ["low", "medium", "high", "critical"]


def severity_meets_threshold(severity: str, threshold: str) -> bool:
    """Check if a finding's severity meets or exceeds the threshold."""
    sev_idx = SEVERITY_ORDER.index(severity.lower()) if severity.lower() in SEVERITY_ORDER else -1
    thr_idx = SEVERITY_ORDER.index(threshold.lower()) if threshold.lower() in SEVERITY_ORDER else 0
    return sev_idx >= thr_idx


def parse_sca_results(results_path: str, threshold: str) -> list[dict]:
    """Parse Snyk SCA (open source) test results."""
    try:
        with open(results_path, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        return []

    vulnerabilities = data.get("vulnerabilities", [])
    findings = []

    seen_ids = set()
    for vuln in vulnerabilities:
        vuln_id = vuln.get("id", "")
        severity = vuln.get("severity", "low")

        if vuln_id in seen_ids:
            continue
        if not severity_meets_threshold(severity, threshold):
            continue

        seen_ids.add(vuln_id)
        findings.append({
            "type": "SCA",
            "id": vuln_id,
            "title": vuln.get("title", "Unknown"),
            "severity": severity.upper(),
            "package": vuln.get("packageName", "unknown"),
            "version": vuln.get("version", "unknown"),
            "fixed_in": ", ".join(vuln.get("fixedIn", [])) or "No fix available",
            "path": " > ".join(vuln.get("from", [])),
            "description": vuln.get("description", "")[:200],
        })

    return findings


def parse_sast_results(results_path: str, threshold: str) -> list[dict]:
    """Parse Snyk Code (SAST) test results."""
    try:
        with open(results_path, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        return []

    runs = data.get("runs", [{}])
    if not runs:
        return []

    results = runs[0].get("results", [])
    findings = []

    for result in results:
        severity_level = result.get("level", "note")
        severity_map = {"error": "high", "warning": "medium", "note": "low"}
        severity = severity_map.get(severity_level, "low")

        if not severity_meets_threshold(severity, threshold):
            continue

        locations = result.get("locations", [{}])
        file_path = ""
        line = 0
        if locations:
            physical = locations[0].get("physicalLocation", {})
            file_path = physical.get("artifactLocation", {}).get("uri", "")
            line = physical.get("region", {}).get("startLine", 0)

        findings.append({
            "type": "SAST",
            "id": result.get("ruleId", "unknown"),
            "title": result.get("message", {}).get("text", "Unknown issue"),
            "severity": severity.upper(),
            "file": file_path,
            "line": line,
            "description": result.get("message", {}).get("text", ""),
        })

    return findings


def build_prompt(
    sca_findings: list[dict],
    sast_findings: list[dict],
    repo: str,
    branch: str,
    pr_number: int,
) -> str:
    """Build a structured prompt for Devin."""
    sections = []

    sections.append(f"""## Snyk Security Findings — Automated Remediation

Repository: {repo}
Branch: {branch}
Pull Request: #{pr_number}
""")

    if sca_findings:
        sections.append(f"### Dependency Vulnerabilities ({len(sca_findings)} findings)\n")
        for f in sca_findings:
            sections.append(
                f"- **[{f['severity']}]** {f['title']} in `{f['package']}@{f['version']}`\n"
                f"  - ID: {f['id']}\n"
                f"  - Fix: upgrade to {f['fixed_in']}\n"
                f"  - Path: {f['path']}"
            )
        sections.append("")

    if sast_findings:
        sections.append(f"### Code Vulnerabilities ({len(sast_findings)} findings)\n")
        for f in sast_findings:
            location = f"`{f['file']}:{f['line']}`" if f.get("line") else f"`{f['file']}`"
            sections.append(
                f"- **[{f['severity']}]** {f['title']} at {location}\n"
                f"  - Rule: {f['id']}"
            )
        sections.append("")

    sections.append("""### Instructions

1. Clone the repository and check out branch `{branch}`
2. For dependency vulnerabilities: upgrade the affected packages to the fixed versions
   - Use the package manager's update commands (npm update, pip install --upgrade, etc.)
   - If a major version bump is required, check for breaking changes
3. For code vulnerabilities: apply the minimal secure fix
   - Do NOT just suppress the finding
4. Run the project's test suite to verify nothing breaks
5. Commit with message: "fix(security): remediate Snyk findings from PR #{pr_number}"
6. Push to branch `{branch}`
""".format(branch=branch, pr_number=pr_number))

    return "\n".join(sections)


def create_devin_session(prompt: str) -> dict:
    """Call the Devin API to create a remediation session."""
    api_key = os.environ.get("DEVIN_API_KEY")
    if not api_key:
        print("ERROR: DEVIN_API_KEY environment variable is not set")
        sys.exit(1)

    payload = json.dumps({
        "prompt": prompt,
        "idleTTL": 60,
    }).encode("utf-8")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    req = Request(DEVIN_API_URL, data=payload, headers=headers, method="POST")

    try:
        with urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except HTTPError as e:
        body = e.read().decode("utf-8")
        print(f"ERROR: Devin API returned {e.code}: {body}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Trigger Devin for Snyk remediation")
    parser.add_argument("--sca-results", required=True, help="Path to Snyk SCA JSON results")
    parser.add_argument("--sast-results", required=True, help="Path to Snyk Code JSON results")
    parser.add_argument("--repo", required=True, help="GitHub repository (owner/repo)")
    parser.add_argument("--branch", required=True, help="Git branch to fix")
    parser.add_argument("--pr-number", required=True, type=int, help="Pull request number")
    parser.add_argument("--severity-threshold", default="high", help="Minimum severity to trigger")
    args = parser.parse_args()

    sca_findings = parse_sca_results(args.sca_results, args.severity_threshold)
    sast_findings = parse_sast_results(args.sast_results, args.severity_threshold)

    total = len(sca_findings) + len(sast_findings)
    if total == 0:
        print("No findings above severity threshold. Skipping Devin session.")
        sys.exit(0)

    print(f"Found {len(sca_findings)} SCA + {len(sast_findings)} SAST findings. Creating Devin session...")

    prompt = build_prompt(sca_findings, sast_findings, args.repo, args.branch, args.pr_number)
    result = create_devin_session(prompt)

    session_url = result.get("url", "N/A")
    session_id = result.get("session_id", "N/A")
    print(f"Devin session created: {session_url} (ID: {session_id})")


if __name__ == "__main__":
    main()
```

---

## Snyk Webhook Payload Example

When using Snyk's native webhook integration (Organization Settings → Integrations → Webhooks), the payload for a new vulnerability looks like:

```json
{
  "project": {
    "id": "6d5813be-7e6d-4ab8-80c2-1e3f720085a5",
    "name": "my-org/my-repo",
    "url": "https://app.snyk.io/org/my-org/project/6d5813be-7e6d-4ab8-80c2-1e3f720085a5",
    "source": "github",
    "branch": "main",
    "created": "2024-01-01T00:00:00.000Z"
  },
  "org": {
    "id": "a04d9cbd-ae6e-44af-b573-0556b0ad4bd2",
    "name": "my-org",
    "url": "https://app.snyk.io/org/my-org"
  },
  "group": {
    "id": "b03a9cbd-ce6e-44af-a573-1556b0ad4bd2",
    "name": "my-group"
  },
  "newIssues": [
    {
      "id": "SNYK-JS-LODASH-590103",
      "issueType": "vuln",
      "pkgName": "lodash",
      "pkgVersions": ["4.17.15"],
      "issueData": {
        "id": "SNYK-JS-LODASH-590103",
        "title": "Prototype Pollution",
        "severity": "high",
        "url": "https://security.snyk.io/vuln/SNYK-JS-LODASH-590103",
        "description": "lodash before 4.17.21 is vulnerable to...",
        "identifiers": {
          "CVE": ["CVE-2021-23337"],
          "CWE": ["CWE-1321"]
        },
        "credit": ["Security Researcher"],
        "exploitMaturity": "proof-of-concept",
        "semver": {
          "vulnerable": ["<4.17.21"]
        },
        "publicationTime": "2021-02-15T11:00:00Z",
        "fixedIn": ["4.17.21"]
      },
      "introducedThrough": [
        {
          "kind": "direct",
          "data": {}
        }
      ],
      "isFixed": false,
      "isPatched": false,
      "priority": {
        "score": 714,
        "factors": [
          { "name": "isFixable", "description": "Has a fix available" },
          { "name": "exploitMaturity", "description": "Proof of Concept" }
        ]
      }
    }
  ],
  "removedIssues": []
}
```

---

## Severity Threshold Configuration

Control which severity levels trigger Devin remediation via the `SEVERITY_THRESHOLD` environment variable:

| Threshold | Triggers On |
|-----------|-------------|
| `critical` | Only CRITICAL findings |
| `high` | HIGH and CRITICAL (recommended) |
| `medium` | MEDIUM, HIGH, and CRITICAL |
| `low` | All findings (not recommended — too noisy) |

### Per-Repository Override

Set the threshold as a GitHub Actions variable:

```yaml
# In your workflow
env:
  SEVERITY_THRESHOLD: ${{ vars.SNYK_SEVERITY_THRESHOLD || 'high' }}
```

Then configure per-repo at **Settings → Variables → Actions**:
- Variable name: `SNYK_SEVERITY_THRESHOLD`
- Value: `critical`, `high`, `medium`, or `low`

---

## Setup Guide

### 1. Snyk Account & Token

1. Sign up at [snyk.io](https://snyk.io) (free tier available)
2. Go to **Account Settings → General → Auth Token**
3. Copy your API token

### 2. GitHub Repository Secrets

| Secret | Description |
|--------|-------------|
| `SNYK_TOKEN` | Snyk API/Auth token |
| `DEVIN_API_KEY` | Devin API key ([create via service user](https://docs.devin.ai/key-features/devin-api)) |

### 3. Snyk Project Import

Ensure your repository is imported into Snyk:
1. Go to [app.snyk.io](https://app.snyk.io) → Projects → Add Project
2. Select **GitHub** and import your repository
3. Snyk will detect the manifest files (package.json, requirements.txt, etc.)

### 4. Snyk Native Webhook (Optional)

To use Snyk's webhook instead of (or in addition to) CI-based scanning:

1. Go to **Organization Settings → Integrations → Webhooks**
2. Add a webhook URL pointing to your receiver service
3. Select events: `project_snapshot/push`, `project_snapshot/recurring_test`
4. The webhook fires when Snyk detects new vulnerabilities in monitored projects

---

## Variants

### Monitor Mode (Scheduled Scanning)

Instead of scanning on every PR, run Snyk monitoring on a schedule to catch newly disclosed vulnerabilities:

```yaml
name: Snyk Monitor + Devin Remediation

on:
  schedule:
    - cron: "0 8 * * 1"  # Every Monday at 8 AM UTC

jobs:
  snyk-monitor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install and authenticate Snyk
        run: |
          npm install -g snyk
          snyk auth ${{ secrets.SNYK_TOKEN }}

      - name: Run Snyk monitor
        run: snyk monitor --json > /tmp/snyk_monitor.json || true

      - name: Check for new critical vulnerabilities
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
        run: |
          # Parse and trigger if needed
          python3 .github/scripts/trigger_devin_snyk.py \
            --sca-results /tmp/snyk_monitor.json \
            --sast-results /dev/null \
            --repo "${{ github.repository }}" \
            --branch "main" \
            --pr-number 0 \
            --severity-threshold "critical"
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `snyk test` exits with code 1 | This is expected — exit code 1 means vulnerabilities found. Use `continue-on-error: true` |
| Empty JSON output | Ensure dependencies are installed before scanning (`npm ci`, `pip install`, etc.) |
| Devin fixes wrong packages | Verify the `--from` path in findings points to the correct manifest |
| Too many findings | Increase `SEVERITY_THRESHOLD` to `critical` to reduce noise |
| SAST results empty | `snyk code test` requires the Snyk Code feature to be enabled for your org |

## References

- [Devin API Documentation](https://docs.devin.ai/api-reference/overview)
- [Snyk CLI Reference](https://docs.snyk.io/snyk-cli/cli-reference)
- [Snyk Webhooks](https://docs.snyk.io/snyk-api/snyk-webhooks)
- [Snyk GitHub Actions](https://github.com/snyk/actions)
