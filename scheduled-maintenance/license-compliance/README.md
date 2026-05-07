# License Compliance — Dependency License Auditing

Scheduled Devin sessions that audit all project dependencies against an approved license policy, flag violations, and open PRs or issues for resolution — ensuring your project stays compliant with organizational and legal requirements.

## Overview

Every dependency your project uses comes with a software license. Some licenses (e.g., MIT, Apache-2.0) are permissive and safe for commercial use. Others (e.g., GPL-3.0, AGPL-3.0) have copyleft requirements that may conflict with your distribution model. License compliance auditing ensures:

1. **No unapproved licenses** enter your dependency tree
2. **New dependencies** are checked against your policy before they become entrenched
3. **Transitive dependencies** (dependencies of dependencies) are also audited
4. **Audit trail** exists for legal and compliance teams

---

## Devin Scheduled Session Configuration

### Recommended Cadence

**Quarterly** — License violations are rare in stable projects. Quarterly audits catch new dependencies introduced during feature development without generating excessive noise.

For projects with frequent dependency churn, consider monthly.

```
Cron expression: 0 9 1 */3 *    (1st day of every 3rd month at 09:00 UTC)
```

### Using the Devin API

```bash
curl -s -X POST "https://api.devin.ai/v1/schedules" \
  -H "Authorization: Bearer $DEVIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "cron": "0 9 1 */3 *",
    "title": "Quarterly license compliance audit — my-app",
    "prompt": "You are performing a scheduled license compliance audit on this repository. Audit all direct and transitive dependencies against the approved license policy. Flag any dependencies using unapproved or unknown licenses. Open a PR or issue with the full audit report. See the LICENSE-POLICY.md file in the repo root for the approved and denied license lists.",
    "repos": [
      { "url": "https://github.com/my-org/my-app" }
    ]
  }'
```

---

## Example Prompt

```text
You are performing a scheduled license compliance audit on this repository.

1. AUDIT PHASE — Scan all dependencies (direct and transitive):
   - Use the appropriate tool for this ecosystem:
     - npm/yarn: `npx license-checker --json --production`
     - pip/Poetry: `pip-licenses --format=json --with-urls` or `poetry run pip-licenses`
     - Maven: `mvn license:aggregate-third-party-report`
     - Gradle: `./gradlew generateLicenseReport` (with the license-report plugin)
     - Go: `go-licenses report ./...` or `golicense`
     - Cargo: `cargo license --json`
     - NuGet: `dotnet-project-licenses --json -i .`

2. POLICY CHECK — Compare each dependency's license against this policy:

   APPROVED licenses (safe for any use):
   - MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0, Unlicense, CC0-1.0,
     0BSD, BlueOak-1.0.0, CC-BY-4.0, Zlib, PSF-2.0, Python-2.0

   REVIEW REQUIRED (may be acceptable depending on usage):
   - MPL-2.0, LGPL-2.1, LGPL-3.0, EPL-1.0, EPL-2.0, CDDL-1.0, Artistic-2.0

   DENIED (not approved for use):
   - GPL-2.0, GPL-3.0, AGPL-3.0, SSPL-1.0, EUPL-1.1, OSL-3.0, CC-BY-SA-4.0,
     CC-BY-NC-4.0, BSL-1.1 (non-permissive clause)

   UNKNOWN — If a dependency's license cannot be determined, flag it for manual review.

3. REPORT — Open a PR titled "chore: quarterly license compliance audit" containing:
   - Summary: total dependencies scanned, approved count, flagged count
   - Table of ALL flagged dependencies: package | version | detected license | status
   - For each DENIED dependency: suggest an approved alternative if one exists
   - For each REVIEW REQUIRED dependency: note how it is used (direct vs transitive,
     runtime vs dev-only) to help the legal team assess risk
   - For each UNKNOWN license: link to the package's repository for manual inspection
   - If all dependencies are compliant, still open the PR as a clean audit record

4. If any DENIED licenses are found in production (non-dev) dependencies, also open a
   GitHub issue titled "LICENSE VIOLATION: <package-name> uses <license>" for tracking.
```

---

## Defining Your License Policy

### Option 1: Policy in the Repository

Create a `LICENSE-POLICY.md` or `.license-policy.json` file in your repository root:

```json
{
  "approved": [
    "MIT", "ISC", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0",
    "Unlicense", "CC0-1.0", "0BSD", "BlueOak-1.0.0", "Zlib",
    "PSF-2.0", "Python-2.0"
  ],
  "review_required": [
    "MPL-2.0", "LGPL-2.1", "LGPL-3.0", "EPL-1.0", "EPL-2.0",
    "CDDL-1.0", "Artistic-2.0"
  ],
  "denied": [
    "GPL-2.0", "GPL-3.0", "AGPL-3.0", "SSPL-1.0", "EUPL-1.1",
    "OSL-3.0", "CC-BY-SA-4.0", "CC-BY-NC-4.0", "BSL-1.1"
  ]
}
```

Reference this file in your Devin prompt: *"Read the license policy from `.license-policy.json` in the repo root."*

### Option 2: Policy in a Devin Playbook

Store the license policy in a Devin playbook so it applies consistently across all repos:

```markdown
## License Compliance Playbook

### Approved Licenses
MIT, ISC, BSD-2-Clause, BSD-3-Clause, Apache-2.0, Unlicense, CC0-1.0

### Denied Licenses
GPL-2.0, GPL-3.0, AGPL-3.0, SSPL-1.0

### Audit Steps
1. Run the ecosystem's license checker tool
2. Compare results against the policy above
3. Flag violations and suggest alternatives
```

### Option 3: Policy in Devin Knowledge

Add the license policy as a Devin knowledge note scoped to your organization. This makes it automatically available to all Devin sessions without needing to repeat it in every prompt.

---

## Tooling by Ecosystem

### npm / Yarn — `license-checker`

```bash
# Install
npm install -g license-checker

# Run audit (production dependencies only)
npx license-checker --production --json > licenses.json

# Check against a deny list
npx license-checker --production --failOn "GPL-2.0;GPL-3.0;AGPL-3.0"

# Include transitive dependency details
npx license-checker --production --json --customPath customFormat.json
```

**Alternative:** `license-checker-rspack2` for faster scanning in large monorepos.

### pip / Poetry — `pip-licenses`

```bash
# Install
pip install pip-licenses

# Run audit
pip-licenses --format=json --with-urls --with-description > licenses.json

# With Poetry
poetry run pip-licenses --format=json --with-urls

# Check against an allow list
pip-licenses --allow-only="MIT;BSD License;Apache Software License;ISC License"

# Include transitive dependencies
pip-licenses --with-system --format=json
```

**Alternative:** `liccheck` for policy-as-code enforcement in CI.

### Maven — `license-maven-plugin`

Add to your `pom.xml`:

```xml
<plugin>
  <groupId>org.codehaus.mojo</groupId>
  <artifactId>license-maven-plugin</artifactId>
  <version>2.4.0</version>
  <configuration>
    <includedLicenses>
      <includedLicense>MIT</includedLicense>
      <includedLicense>Apache-2.0</includedLicense>
      <includedLicense>BSD-2-Clause</includedLicense>
      <includedLicense>BSD-3-Clause</includedLicense>
    </includedLicenses>
    <failOnMissing>true</failOnMissing>
    <failOnBlacklist>true</failOnBlacklist>
  </configuration>
</plugin>
```

Run the audit:

```bash
mvn license:aggregate-third-party-report
# Report generated at target/site/aggregate-third-party-report.html
```

### Gradle — `license-report` Plugin

```kotlin
// build.gradle.kts
plugins {
    id("com.github.jk1.dependency-license-report") version "2.8"
}

licenseReport {
    outputDir = "$buildDir/reports/licenses"
    renderers = arrayOf(JsonReportRenderer("licenses.json"))
    allowedLicensesFile = file("$projectDir/allowed-licenses.json")
}
```

```bash
./gradlew generateLicenseReport
```

### Go — `go-licenses`

```bash
# Install
go install github.com/google/go-licenses@latest

# Run audit
go-licenses report ./... --template=csv > licenses.csv

# Check for disallowed licenses
go-licenses check ./... --disallowed_types=restricted
```

### Cargo (Rust) — `cargo-license`

```bash
# Install
cargo install cargo-license

# Run audit
cargo license --json > licenses.json

# Alternative with more detail
cargo install cargo-deny
cargo deny check licenses
```

### NuGet (.NET) — `dotnet-project-licenses`

```bash
# Install
dotnet tool install --global dotnet-project-licenses

# Run audit
dotnet-project-licenses --json -i . > licenses.json
```

---

## Example Audit Report

### PR Title
```
chore: quarterly license compliance audit — Q1 2025
```

### PR Body
```markdown
## License Compliance Audit — Q1 2025

### Summary

| Metric | Count |
|--------|:-----:|
| Total dependencies scanned | 187 |
| Approved | 183 |
| Review required | 2 |
| Denied | 1 |
| Unknown | 1 |

### Flagged Dependencies

| Package | Version | License | Status | Notes |
|---------|---------|---------|--------|-------|
| `chardet` | 5.2.0 | LGPL-2.1 | Review Required | Transitive via `requests`. Dev-only. |
| `mysql-connector` | 8.0.33 | GPL-2.0 (with FOSS exception) | Review Required | Direct dependency. FOSS exception may apply. |
| `json-schema-lib` | 1.0.3 | GPL-3.0 | **DENIED** | Direct prod dependency. Alternative: `ajv` (MIT) |
| `obscure-util` | 0.2.1 | Unknown | Unknown | No LICENSE file in repo. See: github.com/author/obscure-util |

### Recommended Actions

1. **`json-schema-lib`**: Replace with `ajv` (MIT licensed). Both implement JSON Schema Draft-07.
2. **`mysql-connector`**: Review the Oracle FOSS License Exception — if your project qualifies, document the exception in LICENSE-POLICY.md.
3. **`chardet`**: LGPL-2.1 is acceptable for dev-only transitive dependencies per our policy. No action needed.
4. **`obscure-util`**: Contact the maintainer to add a LICENSE file, or vendor the code under a compatible license.

### Verification

All 187 dependencies scanned. Full audit output attached as `licenses.json` in this PR.
```

---

## Tips

- **Dev vs production**: Distinguish between development and production dependencies. A GPL-licensed test utility used only in dev may be acceptable; a GPL-licensed runtime library likely is not.
- **Transitive depth**: Don't just audit direct dependencies. Transitive dependencies (deps of deps) carry the same license obligations. Use tools that resolve the full dependency tree.
- **License exceptions**: Some packages (e.g., MySQL Connector) have license exceptions for FOSS projects. Document these exceptions in your policy file.
- **SPDX identifiers**: Standardize on [SPDX license identifiers](https://spdx.org/licenses/) for consistency. Tools may report the same license differently (e.g., "BSD" vs "BSD-3-Clause").
- **Dual-licensed packages**: Some packages offer multiple licenses (e.g., "MIT OR Apache-2.0"). As long as one option is approved, the dependency is compliant.
- **Integrate with CI**: For high-compliance environments, add license checking as a CI gate so violations are caught at PR time, not just during quarterly audits.
