# Trivy → Devin Integration

Automatically trigger Devin to remediate container image and filesystem vulnerabilities detected by [Trivy](https://trivy.dev) in your CI pipeline.

## Architecture

```
Developer pushes code / Dockerfile
        ↓
GitHub Actions runs Trivy (filesystem scan or container image scan)
        ↓
Vulnerabilities above threshold detected?
    YES → Parse Trivy JSON output → Call Devin API
        ↓
Devin upgrades base images / patches dependencies → pushes fix
        ↓
CI re-runs Trivy → vulnerabilities resolved → PR merged
```

## Loop Prevention

- The workflow skips Devin triggering if the PR author is `devin-ai-integration[bot]`
- Only one remediation session is created per scan run (deduplication via PR label)

---

## GitHub Actions Workflow — Filesystem Scanning

Scans source code and dependency manifests for known vulnerabilities.

Save as `.github/workflows/trivy-fs-devin.yml`:

```yaml
name: Trivy Filesystem Scan + Devin Remediation

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

env:
  SEVERITY_THRESHOLD: HIGH,CRITICAL

jobs:
  trivy-fs-scan:
    runs-on: ubuntu-latest

    if: github.event.pull_request.user.login != 'devin-ai-integration[bot]'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run Trivy filesystem scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: "fs"
          scan-ref: "."
          format: "json"
          output: "trivy-fs-results.json"
          severity: ${{ env.SEVERITY_THRESHOLD }}
          exit-code: "1"
        continue-on-error: true

      - name: Process findings and trigger Devin
        if: always()
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
        run: |
          python3 .github/scripts/trigger_devin_trivy.py \
            --results-file trivy-fs-results.json \
            --scan-type filesystem \
            --repo "${{ github.repository }}" \
            --branch "${{ github.head_ref }}" \
            --pr-number "${{ github.event.pull_request.number }}" \
            --severity-threshold "${{ env.SEVERITY_THRESHOLD }}"
```

---

## GitHub Actions Workflow — Container Image Scanning

Scans built Docker images for OS-level and application-level vulnerabilities.

Save as `.github/workflows/trivy-image-devin.yml`:

```yaml
name: Trivy Image Scan + Devin Remediation

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - "Dockerfile*"
      - "docker-compose*.yml"
      - ".dockerignore"

permissions:
  contents: read
  pull-requests: write
  packages: read

env:
  IMAGE_NAME: ${{ github.repository }}:${{ github.sha }}
  SEVERITY_THRESHOLD: HIGH,CRITICAL

jobs:
  trivy-image-scan:
    runs-on: ubuntu-latest

    if: github.event.pull_request.user.login != 'devin-ai-integration[bot]'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t ${{ env.IMAGE_NAME }} .

      - name: Run Trivy image scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: "image"
          image-ref: ${{ env.IMAGE_NAME }}
          format: "json"
          output: "trivy-image-results.json"
          severity: ${{ env.SEVERITY_THRESHOLD }}
          exit-code: "1"
          vuln-type: "os,library"
        continue-on-error: true

      - name: Process findings and trigger Devin
        if: always()
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
        run: |
          python3 .github/scripts/trigger_devin_trivy.py \
            --results-file trivy-image-results.json \
            --scan-type image \
            --repo "${{ github.repository }}" \
            --branch "${{ github.head_ref }}" \
            --pr-number "${{ github.event.pull_request.number }}" \
            --severity-threshold "${{ env.SEVERITY_THRESHOLD }}"
```

---

## Python Script: Parse Trivy JSON & Trigger Devin

Save as `.github/scripts/trigger_devin_trivy.py`:

```python
#!/usr/bin/env python3
"""
Parse Trivy JSON output and create a Devin session to remediate findings.

Supports both filesystem and container image scan results.

Usage:
    python trigger_devin_trivy.py \
        --results-file trivy-results.json \
        --scan-type filesystem|image \
        --repo owner/repo \
        --branch feature-branch \
        --pr-number 42 \
        --severity-threshold "HIGH,CRITICAL"
"""

import argparse
import json
import os
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError

DEVIN_API_URL = "https://api.devin.ai/v1/sessions"


def parse_trivy_results(results_path: str, severity_threshold: str) -> list[dict]:
    """Parse Trivy JSON output into a structured list of findings."""
    try:
        with open(results_path, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        return []

    allowed_severities = {s.strip().upper() for s in severity_threshold.split(",")}
    findings = []

    results = data.get("Results", [])
    for result in results:
        target = result.get("Target", "unknown")
        target_type = result.get("Type", "unknown")
        vulnerabilities = result.get("Vulnerabilities", []) or []

        for vuln in vulnerabilities:
            severity = vuln.get("Severity", "UNKNOWN").upper()
            if severity not in allowed_severities:
                continue

            findings.append({
                "target": target,
                "target_type": target_type,
                "vuln_id": vuln.get("VulnerabilityID", "unknown"),
                "pkg_name": vuln.get("PkgName", "unknown"),
                "installed_version": vuln.get("InstalledVersion", "unknown"),
                "fixed_version": vuln.get("FixedVersion", ""),
                "severity": severity,
                "title": vuln.get("Title", ""),
                "description": (vuln.get("Description", ""))[:150],
                "primary_url": vuln.get("PrimaryURL", ""),
            })

    return findings


def group_findings_by_target(findings: list[dict]) -> dict[str, list[dict]]:
    """Group findings by their target (file/image layer)."""
    groups: dict[str, list[dict]] = {}
    for f in findings:
        key = f"{f['target']} ({f['target_type']})"
        groups.setdefault(key, []).append(f)
    return groups


def build_prompt(
    findings: list[dict],
    scan_type: str,
    repo: str,
    branch: str,
    pr_number: int,
) -> str:
    """Build a structured Devin prompt from Trivy findings."""
    grouped = group_findings_by_target(findings)

    sections = []
    sections.append(f"""## Trivy Security Scan — Automated Remediation

Repository: {repo}
Branch: {branch}
Pull Request: #{pr_number}
Scan Type: {scan_type}
Total Findings: {len(findings)}
""")

    for target, target_findings in grouped.items():
        sections.append(f"### Target: `{target}`\n")
        for f in target_findings:
            fix_info = f"→ upgrade to **{f['fixed_version']}**" if f["fixed_version"] else "— no fix available yet"
            sections.append(
                f"- **[{f['severity']}]** `{f['pkg_name']}@{f['installed_version']}` {fix_info}\n"
                f"  - {f['vuln_id']}: {f['title']}\n"
                f"  - Reference: {f['primary_url']}"
            )
        sections.append("")

    if scan_type == "image":
        sections.append("""### Remediation Instructions (Container Image)

1. Clone the repository and check out branch `{branch}`
2. Review the Dockerfile(s) for the affected image
3. For OS-level vulnerabilities:
   - Update the base image to a newer tag (e.g., `node:20-alpine3.19` → `node:20-alpine3.20`)
   - Add `RUN apk upgrade --no-cache` (Alpine) or `RUN apt-get update && apt-get upgrade -y` (Debian)
4. For application-level vulnerabilities:
   - Update the affected packages in the relevant manifest (package.json, requirements.txt, etc.)
5. Rebuild the image locally to verify it still works
6. Commit with message: "fix(security): remediate Trivy image findings from PR #{pr_number}"
7. Push to branch `{branch}`
""".format(branch=branch, pr_number=pr_number))
    else:
        sections.append("""### Remediation Instructions (Filesystem)

1. Clone the repository and check out branch `{branch}`
2. For each vulnerable dependency:
   - If a fixed version exists, upgrade to it using the package manager
   - If no fix is available, evaluate whether the vulnerability is exploitable in context
   - If exploitable with no fix, consider replacing the dependency
3. Run the project's test suite after upgrades
4. Commit with message: "fix(security): remediate Trivy filesystem findings from PR #{pr_number}"
5. Push to branch `{branch}`
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
    parser = argparse.ArgumentParser(description="Trigger Devin for Trivy remediation")
    parser.add_argument("--results-file", required=True, help="Path to Trivy JSON output")
    parser.add_argument("--scan-type", required=True, choices=["filesystem", "image"],
                        help="Type of Trivy scan performed")
    parser.add_argument("--repo", required=True, help="GitHub repository (owner/repo)")
    parser.add_argument("--branch", required=True, help="Git branch to fix")
    parser.add_argument("--pr-number", required=True, type=int, help="Pull request number")
    parser.add_argument("--severity-threshold", default="HIGH,CRITICAL",
                        help="Comma-separated severity levels to include")
    args = parser.parse_args()

    findings = parse_trivy_results(args.results_file, args.severity_threshold)

    if not findings:
        print("No findings above severity threshold. Skipping Devin session.")
        sys.exit(0)

    fixable = [f for f in findings if f["fixed_version"]]
    print(f"Found {len(findings)} findings ({len(fixable)} fixable). Creating Devin session...")

    prompt = build_prompt(findings, args.scan_type, args.repo, args.branch, args.pr_number)
    result = create_devin_session(prompt)

    session_url = result.get("url", "N/A")
    session_id = result.get("session_id", "N/A")
    print(f"Devin session created: {session_url} (ID: {session_id})")


if __name__ == "__main__":
    main()
```

---

## Trivy JSON Output Examples

### Filesystem Scan Result

```json
{
  "SchemaVersion": 2,
  "CreatedAt": "2024-01-15T10:30:00Z",
  "ArtifactName": ".",
  "ArtifactType": "filesystem",
  "Results": [
    {
      "Target": "package-lock.json",
      "Class": "lang-pkgs",
      "Type": "npm",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-2024-4068",
          "PkgName": "braces",
          "InstalledVersion": "3.0.2",
          "FixedVersion": "3.0.3",
          "Severity": "HIGH",
          "Title": "braces: fails to limit the number of characters it can handle",
          "Description": "The NPM package `braces` fails to limit...",
          "PrimaryURL": "https://avd.aquasec.com/nvd/cve-2024-4068",
          "References": [
            "https://github.com/micromatch/braces/issues/35",
            "https://nvd.nist.gov/vuln/detail/CVE-2024-4068"
          ],
          "PublishedDate": "2024-05-14T15:42:48.000Z",
          "LastModifiedDate": "2024-05-14T16:17:02.000Z",
          "CVSS": {
            "nvd": {
              "V3Score": 7.5,
              "V3Vector": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H"
            }
          }
        }
      ]
    },
    {
      "Target": "requirements.txt",
      "Class": "lang-pkgs",
      "Type": "pip",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-2024-35195",
          "PkgName": "requests",
          "InstalledVersion": "2.31.0",
          "FixedVersion": "2.32.0",
          "Severity": "CRITICAL",
          "Title": "requests: authentication credentials leaked to target site on redirect",
          "Description": "Requests `Session` object does not verify...",
          "PrimaryURL": "https://avd.aquasec.com/nvd/cve-2024-35195"
        }
      ]
    }
  ]
}
```

### Container Image Scan Result

```json
{
  "SchemaVersion": 2,
  "CreatedAt": "2024-01-15T10:30:00Z",
  "ArtifactName": "my-org/my-app:latest",
  "ArtifactType": "container_image",
  "Metadata": {
    "OS": {
      "Family": "alpine",
      "Name": "3.18.6"
    },
    "ImageConfig": {
      "architecture": "amd64",
      "os": "linux"
    }
  },
  "Results": [
    {
      "Target": "my-org/my-app:latest (alpine 3.18.6)",
      "Class": "os-pkgs",
      "Type": "alpine",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-2024-0727",
          "PkgName": "libssl3",
          "InstalledVersion": "3.1.4-r2",
          "FixedVersion": "3.1.4-r5",
          "Severity": "HIGH",
          "Title": "openssl: denial of service via null dereference",
          "Description": "Processing a maliciously formatted PKCS12 file...",
          "PrimaryURL": "https://avd.aquasec.com/nvd/cve-2024-0727"
        }
      ]
    },
    {
      "Target": "app/package-lock.json",
      "Class": "lang-pkgs",
      "Type": "npm",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-2024-29041",
          "PkgName": "express",
          "InstalledVersion": "4.18.2",
          "FixedVersion": "4.19.2",
          "Severity": "HIGH",
          "Title": "express: open redirect in response.redirect()",
          "Description": "Express.js versions prior to 4.19.2 are vulnerable...",
          "PrimaryURL": "https://avd.aquasec.com/nvd/cve-2024-29041"
        }
      ]
    }
  ]
}
```

---

## Advanced: Combined Workflow (FS + Image)

Scan both the source tree and the built container in one workflow:

```yaml
name: Trivy Full Scan + Devin Remediation

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

env:
  SEVERITY_THRESHOLD: HIGH,CRITICAL

jobs:
  trivy-scan:
    runs-on: ubuntu-latest
    if: github.event.pull_request.user.login != 'devin-ai-integration[bot]'

    steps:
      - uses: actions/checkout@v4

      - name: Filesystem scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: "fs"
          scan-ref: "."
          format: "json"
          output: "trivy-fs.json"
          severity: ${{ env.SEVERITY_THRESHOLD }}
          exit-code: "0"

      - name: Build image
        run: docker build -t local-scan:${{ github.sha }} .

      - name: Image scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: "image"
          image-ref: "local-scan:${{ github.sha }}"
          format: "json"
          output: "trivy-image.json"
          severity: ${{ env.SEVERITY_THRESHOLD }}
          exit-code: "0"

      - name: Merge results and trigger Devin
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
          GH_REPO: ${{ github.repository }}
          GH_BRANCH: ${{ github.head_ref }}
          GH_PR_NUMBER: ${{ github.event.pull_request.number }}
        run: |
          python3 << 'EOF'
          import json
          import os
          import sys
          from urllib.request import Request, urlopen

          def load_findings(path, threshold_set):
              try:
                  with open(path) as f:
                      data = json.load(f)
              except (json.JSONDecodeError, FileNotFoundError):
                  return []
              findings = []
              for result in data.get("Results", []):
                  for vuln in result.get("Vulnerabilities", []) or []:
                      if vuln.get("Severity", "").upper() in threshold_set:
                          findings.append("- [{}] {}@{} in {} — fix: {}".format(
                              vuln["Severity"], vuln.get("PkgName"), vuln.get("InstalledVersion"),
                              result["Target"], vuln.get("FixedVersion", "none")))
              return findings

          repo = os.environ.get("GH_REPO", "")
          branch = os.environ.get("GH_BRANCH", "")
          pr_number = os.environ.get("GH_PR_NUMBER", "")

          threshold = set(os.environ.get("SEVERITY_THRESHOLD", "HIGH,CRITICAL").split(","))
          fs_findings = load_findings("trivy-fs.json", threshold)
          img_findings = load_findings("trivy-image.json", threshold)

          all_findings = fs_findings + img_findings
          if not all_findings:
              print("No findings. Skipping.")
              sys.exit(0)

          prompt = """## Trivy Security Scan Findings

          Repository: {repo}
          Branch: {branch}
          PR: #{pr_number}

          ### Filesystem Findings ({fs_count})
          {fs_list}

          ### Image Findings ({img_count})
          {img_list}

          Fix all findings with available patches. Push to branch {branch}.
          """.format(
              repo=repo, branch=branch, pr_number=pr_number,
              fs_count=len(fs_findings), fs_list=chr(10).join(fs_findings) or "None",
              img_count=len(img_findings), img_list=chr(10).join(img_findings) or "None",
          )

          payload = json.dumps({"prompt": prompt, "idleTTL": 60}).encode()
          req = Request("https://api.devin.ai/v1/sessions", data=payload, headers={
              "Authorization": "Bearer " + os.environ["DEVIN_API_KEY"],
              "Content-Type": "application/json",
          }, method="POST")
          with urlopen(req) as resp:
              result = json.loads(resp.read())
          print("Session: " + result.get("url", "N/A"))
          EOF
```

---

## Configuration

### Severity Threshold

The `SEVERITY_THRESHOLD` environment variable accepts a comma-separated list:

| Value | Effect |
|-------|--------|
| `CRITICAL` | Only critical vulnerabilities |
| `HIGH,CRITICAL` | High and critical (recommended) |
| `MEDIUM,HIGH,CRITICAL` | Medium and above |
| `LOW,MEDIUM,HIGH,CRITICAL` | Everything (very noisy) |

### Scan Targets

| Flag | What it scans |
|------|---------------|
| `trivy fs .` | Source code manifests (package.json, go.sum, requirements.txt, etc.) |
| `trivy image <ref>` | Container image layers (OS packages + app dependencies) |
| `trivy config .` | IaC misconfigurations (Terraform, Kubernetes, Dockerfile) |
| `trivy repo <url>` | Remote Git repository |

### Ignore Unfixed Vulnerabilities

To skip findings with no available fix:

```yaml
- uses: aquasecurity/trivy-action@0.28.0
  with:
    scan-type: "fs"
    ignore-unfixed: true   # Only report vulnerabilities with known fixes
    format: "json"
    output: "trivy-results.json"
```

### Custom Ignore File

Create `.trivyignore` in your repo root to skip specific CVEs:

```
# Known false positive in our context
CVE-2024-12345

# Accepted risk — mitigated at network layer
CVE-2024-67890
```

---

## Setup Guide

### 1. GitHub Repository Secrets

| Secret | Description |
|--------|-------------|
| `DEVIN_API_KEY` | Devin API key ([create via service user](https://docs.devin.ai/key-features/devin-api)) |

No Trivy-specific credentials are needed — Trivy uses public vulnerability databases.

### 2. Trivy Database Caching (Optional)

For faster scans, cache the Trivy vulnerability database:

```yaml
- name: Cache Trivy DB
  uses: actions/cache@v4
  with:
    path: ~/.cache/trivy
    key: trivy-db-${{ github.run_id }}
    restore-keys: trivy-db-
```

### 3. Private Registry Images

If scanning images from private registries:

```yaml
- name: Login to registry
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}

- name: Scan private image
  uses: aquasecurity/trivy-action@0.28.0
  with:
    image-ref: "ghcr.io/${{ github.repository }}:latest"
    format: "json"
    output: "trivy-results.json"
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Trivy DB download fails | Add caching or use `--skip-db-update` with a pre-downloaded DB |
| Scan finds 0 results | Verify manifest files are in the scan path; check `.trivyignore` |
| Image scan OOM | Use `--scanners vuln` to disable misconfiguration checks |
| Too many findings | Use `--ignore-unfixed` and increase severity threshold |
| Devin can't access private registry | Add registry credentials to the Devin session prompt |

## References

- [Devin API Documentation](https://docs.devin.ai/api-reference/overview)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [Trivy GitHub Action](https://github.com/aquasecurity/trivy-action)
- [Trivy JSON Schema](https://aquasecurity.github.io/trivy/latest/docs/configuration/reporting/#json)
