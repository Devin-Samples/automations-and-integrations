# SonarQube / SonarCloud → Devin Integration

Automatically trigger Devin to remediate code quality and security findings when a SonarQube/SonarCloud Quality Gate fails.

## Architecture

```
Developer pushes code
        ↓
GitHub Actions runs SonarQube scan
        ↓
Quality Gate check fails?
    YES → Workflow calls Devin API with scan findings
        ↓
Devin reads findings, creates remediation PR
        ↓
CI re-runs scan on remediation PR → Quality Gate passes → PR unblocked
```

## Loop Prevention

To prevent infinite remediation loops (Devin fixes → scan triggers → Devin fixes again…):

- The workflow checks the PR author — if it's `devin-ai-integration[bot]`, the scan runs but Devin is **not** re-triggered
- A `devin-attempt` label is applied to PRs remediated by Devin; the workflow skips triggering if the label is already present

---

## GitHub Actions Workflow

Save as `.github/workflows/sonarqube-devin.yml`:

```yaml
name: SonarQube Scan + Devin Remediation

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

jobs:
  sonarqube-scan:
    runs-on: ubuntu-latest

    # Skip triggering Devin for PRs authored by the bot itself
    if: github.event.pull_request.user.login != 'devin-ai-integration[bot]'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history needed for SonarQube analysis

      - name: SonarQube Scan
        uses: SonarSource/sonarqube-scan-action@v3
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}  # Omit for SonarCloud

      - name: Check Quality Gate
        id: quality_gate
        uses: SonarSource/sonarqube-quality-gate-action@v1
        continue-on-error: true
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}

      - name: Fetch SonarQube findings
        if: steps.quality_gate.outputs.quality-gate-status == 'FAILED'
        id: findings
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
          PROJECT_KEY: ${{ vars.SONAR_PROJECT_KEY }}
        run: |
          # Fetch issues from SonarQube API (new issues on this PR)
          FINDINGS=$(curl -s -u "${SONAR_TOKEN}:" \
            "${SONAR_HOST_URL}/api/issues/search?componentKeys=${PROJECT_KEY}&pullRequest=${{ github.event.pull_request.number }}&statuses=OPEN&types=BUG,VULNERABILITY,CODE_SMELL&ps=50" \
          )
          echo "$FINDINGS" > /tmp/sonar_findings.json
          echo "findings_path=/tmp/sonar_findings.json" >> "$GITHUB_OUTPUT"

      - name: Trigger Devin remediation
        if: steps.quality_gate.outputs.quality-gate-status == 'FAILED'
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
        run: |
          python3 .github/scripts/trigger_devin_sonar.py \
            --findings-file /tmp/sonar_findings.json \
            --repo "${{ github.repository }}" \
            --branch "${{ github.head_ref }}" \
            --pr-number "${{ github.event.pull_request.number }}"
```

---

## Python Script: Parse Findings & Trigger Devin

Save as `.github/scripts/trigger_devin_sonar.py`:

```python
#!/usr/bin/env python3
"""
Parse SonarQube findings and create a Devin session to remediate them.

Usage:
    python trigger_devin_sonar.py \
        --findings-file /tmp/sonar_findings.json \
        --repo owner/repo \
        --branch feature-branch \
        --pr-number 42
"""

import argparse
import json
import os
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError

DEVIN_API_URL = "https://api.devin.ai/v1/sessions"


def parse_findings(findings_path: str) -> list[dict]:
    """Extract actionable findings from SonarQube API response."""
    with open(findings_path, "r") as f:
        data = json.load(f)

    issues = data.get("issues", [])
    parsed = []
    for issue in issues:
        parsed.append({
            "key": issue.get("key"),
            "rule": issue.get("rule"),
            "severity": issue.get("severity"),
            "type": issue.get("type"),
            "message": issue.get("message"),
            "component": issue.get("component", "").split(":")[-1],
            "line": issue.get("line"),
            "effort": issue.get("effort"),
        })
    return parsed


def build_prompt(findings: list[dict], repo: str, branch: str, pr_number: int) -> str:
    """Build a structured prompt for Devin with remediation instructions."""
    findings_summary = []
    for f in findings:
        location = f"{f['component']}:{f['line']}" if f.get("line") else f["component"]
        findings_summary.append(
            f"- [{f['severity']}] {f['type']} in `{location}`: {f['message']} (rule: {f['rule']})"
        )

    findings_text = "\n".join(findings_summary)

    prompt = f"""## SonarQube Quality Gate Failure — Automated Remediation

Repository: {repo}
Branch: {branch}
Pull Request: #{pr_number}

The SonarQube Quality Gate has failed. Please fix the following findings:

### Findings ({len(findings)} total)

{findings_text}

### Instructions

1. Clone the repository and check out branch `{branch}`
2. For each finding, apply the minimal fix that resolves the issue
3. Follow existing code style and conventions
4. Do NOT suppress warnings or add NOSONAR comments unless the finding is a confirmed false positive
5. Commit fixes with message: "fix: resolve SonarQube findings from PR #{pr_number}"
6. Push to the same branch `{branch}` so the PR is updated
7. The scan will re-run automatically to verify the fixes

### Priority Order
Fix BLOCKER and CRITICAL severity issues first, then MAJOR.
"""
    return prompt


def create_devin_session(prompt: str, repo: str) -> dict:
    """Call the Devin API to create a new session."""
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
    parser = argparse.ArgumentParser(description="Trigger Devin for SonarQube remediation")
    parser.add_argument("--findings-file", required=True, help="Path to SonarQube findings JSON")
    parser.add_argument("--repo", required=True, help="GitHub repository (owner/repo)")
    parser.add_argument("--branch", required=True, help="Git branch to fix")
    parser.add_argument("--pr-number", required=True, type=int, help="Pull request number")
    args = parser.parse_args()

    findings = parse_findings(args.findings_file)

    if not findings:
        print("No actionable findings found. Skipping Devin session.")
        sys.exit(0)

    print(f"Found {len(findings)} findings. Creating Devin session...")

    prompt = build_prompt(findings, args.repo, args.branch, args.pr_number)
    result = create_devin_session(prompt, args.repo)

    session_url = result.get("url", "N/A")
    session_id = result.get("session_id", "N/A")
    print(f"Devin session created: {session_url} (ID: {session_id})")


if __name__ == "__main__":
    main()
```

---

## SonarQube Webhook Payload Example

When using SonarQube's native webhook (instead of polling from CI), the payload looks like this:

```json
{
  "serverUrl": "https://sonarqube.example.com",
  "taskId": "AXouyxDpizdp4B1K",
  "status": "SUCCESS",
  "analysedAt": "2024-01-15T10:30:00+0000",
  "revision": "ab12cd34ef56",
  "changedAt": "2024-01-15T10:30:00+0000",
  "project": {
    "key": "my-org_my-repo",
    "name": "My Repository",
    "url": "https://sonarqube.example.com/dashboard?id=my-org_my-repo"
  },
  "branch": {
    "name": "feature/new-endpoint",
    "type": "BRANCH",
    "isMain": false,
    "url": "https://sonarqube.example.com/dashboard?id=my-org_my-repo&branch=feature%2Fnew-endpoint"
  },
  "qualityGate": {
    "name": "Sonar way",
    "status": "ERROR",
    "conditions": [
      {
        "metric": "new_reliability_rating",
        "operator": "GREATER_THAN",
        "value": "3",
        "status": "ERROR",
        "errorThreshold": "1"
      },
      {
        "metric": "new_security_rating",
        "operator": "GREATER_THAN",
        "value": "2",
        "status": "ERROR",
        "errorThreshold": "1"
      },
      {
        "metric": "new_coverage",
        "operator": "LESS_THAN",
        "value": "72.5",
        "status": "OK",
        "errorThreshold": "80"
      }
    ]
  },
  "properties": {
    "sonar.analysis.detectedscm": "git",
    "sonar.analysis.detectedci": "GitHub Actions"
  }
}
```

### Webhook Receiver (Alternative to CI-based approach)

If you prefer to use SonarQube's native webhook rather than polling from CI, you can deploy a lightweight receiver:

```python
#!/usr/bin/env python3
"""
SonarQube webhook receiver that triggers Devin on Quality Gate failure.

Deploy as a Flask/FastAPI service or AWS Lambda behind API Gateway.
"""

import hashlib
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import Request, urlopen

DEVIN_API_URL = "https://api.devin.ai/v1/sessions"
WEBHOOK_SECRET = os.environ.get("SONAR_WEBHOOK_SECRET", "")


def verify_signature(payload: bytes, signature: str) -> bool:
    """Verify SonarQube webhook signature (if secret is configured)."""
    if not WEBHOOK_SECRET:
        return True  # No secret configured, skip verification
    expected = hmac.new(
        WEBHOOK_SECRET.encode(), payload, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        payload = self.rfile.read(content_length)

        # Verify webhook signature
        signature = self.headers.get("X-Sonar-Webhook-HMAC-SHA256", "")
        if not verify_signature(payload, signature):
            self.send_response(401)
            self.end_headers()
            return

        data = json.loads(payload)

        # Only act on Quality Gate failures
        quality_gate = data.get("qualityGate", {})
        if quality_gate.get("status") != "ERROR":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"action": "skipped", "reason": "quality gate passed"}')
            return

        project_key = data.get("project", {}).get("key", "unknown")
        branch_name = data.get("branch", {}).get("name", "main")

        # Build Devin prompt
        failed_conditions = [
            c for c in quality_gate.get("conditions", [])
            if c.get("status") == "ERROR"
        ]
        conditions_text = "\n".join(
            f"- {c['metric']}: value={c['value']} (threshold: {c['errorThreshold']})"
            for c in failed_conditions
        )

        prompt = f"""## SonarQube Quality Gate Failure

Project: {project_key}
Branch: {branch_name}

The following Quality Gate conditions failed:
{conditions_text}

Please investigate and fix the issues causing these metrics to fail.
Check out branch `{branch_name}`, review the SonarQube findings, and push fixes.
"""

        # Trigger Devin
        api_key = os.environ["DEVIN_API_KEY"]
        req = Request(
            DEVIN_API_URL,
            data=json.dumps({"prompt": prompt}).encode(),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urlopen(req) as resp:
            result = json.loads(resp.read())

        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps({
            "action": "triggered",
            "session_id": result.get("session_id"),
        }).encode())


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), WebhookHandler)
    print("SonarQube webhook receiver listening on :8080")
    server.serve_forever()
```

---

## Configuration Guide

### 1. SonarQube/SonarCloud Project Setup

**For SonarCloud:**
1. Go to [sonarcloud.io](https://sonarcloud.io) → Your Organization → Your Project
2. Navigate to **Administration → Analysis Method**
3. Enable **GitHub Actions** as the analysis method
4. Note your `SONAR_TOKEN` and project key

**For Self-Hosted SonarQube:**
1. Navigate to **Administration → Configuration → Webhooks**
2. Click **Create** and configure:
   - **Name**: `Devin Remediation`
   - **URL**: Your webhook receiver endpoint
   - **Secret**: A shared secret for HMAC verification
3. Generate a token at **My Account → Security → Generate Tokens**

### 2. GitHub Repository Secrets

Add the following secrets to your repository (Settings → Secrets and variables → Actions):

| Secret | Description |
|--------|-------------|
| `SONAR_TOKEN` | SonarQube/SonarCloud authentication token |
| `SONAR_HOST_URL` | SonarQube server URL (omit for SonarCloud) |
| `DEVIN_API_KEY` | Devin API key ([create via service user](https://docs.devin.ai/key-features/devin-api)) |

### 3. Repository Variables

| Variable | Description |
|----------|-------------|
| `SONAR_PROJECT_KEY` | Your SonarQube project key (e.g., `my-org_my-repo`) |

### 4. Devin API Key

1. Go to your Devin organization settings
2. Create a **Service User** (recommended) or use your personal account
3. Generate an API key for the service user
4. Add it as `DEVIN_API_KEY` in your GitHub repository secrets

### 5. SonarQube Project Configuration

Create a `sonar-project.properties` file in your repository root:

```properties
sonar.projectKey=my-org_my-repo
sonar.organization=my-org

# Source directories
sonar.sources=src
sonar.tests=tests

# Exclusions (optional)
sonar.exclusions=**/node_modules/**,**/dist/**,**/*.test.ts

# Coverage reports (optional)
sonar.javascript.lcov.reportPaths=coverage/lcov.info
```

---

## Variants

### SonarCloud with GitHub Checks API

If using SonarCloud's native GitHub integration (Automatic Analysis), you can listen for the `check_run` event instead:

```yaml
on:
  check_run:
    types: [completed]

jobs:
  handle-sonar-check:
    if: |
      github.event.check_run.app.slug == 'sonarcloud' &&
      github.event.check_run.conclusion == 'failure' &&
      github.event.check_run.pull_requests[0].head.ref != '' &&
      github.actor != 'devin-ai-integration[bot]'
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Devin for SonarCloud failure
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
        run: |
          PR_BRANCH="${{ github.event.check_run.pull_requests[0].head.ref }}"
          PR_NUMBER="${{ github.event.check_run.pull_requests[0].number }}"
          DETAILS_URL="${{ github.event.check_run.details_url }}"

          curl -s -X POST "https://api.devin.ai/v1/sessions" \
            -H "Authorization: Bearer ${DEVIN_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "{
              \"prompt\": \"SonarCloud Quality Gate failed for PR #${PR_NUMBER} on branch ${PR_BRANCH}. Review the findings at ${DETAILS_URL} and fix the issues. Push fixes to branch ${PR_BRANCH}.\",
              \"idleTTL\": 60
            }"
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Webhook not received | Check SonarQube → Administration → Webhooks → Recent Deliveries for errors |
| Quality Gate always passes | Verify your Quality Gate conditions are correctly configured in SonarQube |
| Devin session not created | Check `DEVIN_API_KEY` is valid; verify API response in workflow logs |
| Infinite loop | Ensure the `if` condition checks for `devin-ai-integration[bot]` author |
| Findings not found via API | Confirm `PROJECT_KEY` matches and the branch/PR analysis completed |

## References

- [Devin API Documentation](https://docs.devin.ai/api-reference/overview)
- [SonarQube Web API — Issues Search](https://docs.sonarqube.org/latest/extension-guide/web-api/)
- [SonarQube Webhooks](https://docs.sonarqube.org/latest/project-administration/webhooks/)
- [SonarSource GitHub Actions](https://github.com/SonarSource/sonarqube-scan-action)
