# Automated Dependency Updates

Scheduled Devin sessions that check for outdated packages, bump versions, run tests, and open PRs — on a recurring cadence, across any package ecosystem.

## Overview

Dependency drift is one of the most common sources of security vulnerabilities and compatibility breakage. This pattern uses Devin's scheduled sessions to automate the entire update cycle:

1. **Detect** outdated dependencies
2. **Bump** versions according to your policy (patch, minor, or major)
3. **Run** tests to verify compatibility
4. **Open a PR** with a clear summary of what changed and why

## Devin Scheduled Session Configuration

### Using the Devin UI

1. Navigate to **Schedules** in your Devin organization
2. Click **Create Schedule**
3. Configure:
   - **Repository**: Select the target repo
   - **Cron expression**: `0 9 * * 1` (every Monday at 09:00 UTC)
   - **Prompt**: See [example prompts](#example-prompts) below
   - **Playbook** (optional): Attach a playbook for consistent methodology
   - **ACU budget**: Recommend 50–100 ACUs per run depending on repo size

### Using the Devin API

```bash
curl -s -X POST "https://api.devin.ai/v1/schedules" \
  -H "Authorization: Bearer $DEVIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "cron": "0 9 * * 1",
    "title": "Weekly dependency updates — my-app",
    "prompt": "You are maintaining the repository. Check for outdated dependencies, bump versions (minor and patch only), run the full test suite, and open a PR with a summary of all changes. Do not bump major versions unless the changelog indicates no breaking changes for our usage.",
    "repos": [
      { "url": "https://github.com/my-org/my-app" }
    ]
  }'
```

> **Tip:** Use `"cron": "0 9 * * 1"` for weekly Monday runs. Stagger across repos to avoid CI congestion (e.g., repo A at 09:00, repo B at 09:30).

---

## Example Prompts

### General-Purpose (Any Ecosystem)

```text
You are maintaining the repository. Perform the following steps:

1. Identify all outdated dependencies using the project's native tooling.
2. Bump PATCH and MINOR versions for all outdated packages.
3. For MAJOR version bumps, only proceed if the package's changelog or migration guide
   confirms no breaking changes affecting this project. Otherwise, list them in the PR
   description as "skipped major updates" with a brief reason.
4. Run the full test suite. If any tests fail after a bump, revert that specific bump
   and note it in the PR description.
5. Run the linter / formatter if configured.
6. Open a single PR titled "chore(deps): weekly dependency updates" with:
   - A table of all bumped packages (old version → new version)
   - A section listing any skipped major updates and why
   - A section listing any reverted bumps due to test failures
```

### npm / Yarn

```text
You are maintaining a Node.js repository.

1. Run `npm outdated --json` (or `yarn outdated --json`) to identify stale packages.
2. For each outdated package:
   - If a PATCH or MINOR update is available, bump it.
   - If a MAJOR update is available, check the package's CHANGELOG.md or release notes.
     Only bump if there are no breaking changes for our usage.
3. Run `npm install` (or `yarn install`) to regenerate the lockfile.
4. Run `npm test` (or `yarn test`). If tests fail, revert the problematic bump.
5. Run `npm run lint` if available.
6. Open a PR with the title "chore(deps): weekly npm dependency updates".

Include in the PR body:
- Table: package name | old version | new version | update type (patch/minor/major)
- Any skipped or reverted updates with reasons
```

### pip / Poetry (Python)

```text
You are maintaining a Python repository.

1. If using Poetry: run `poetry show --outdated` to list stale packages.
   If using pip: run `pip list --outdated --format=json`.
2. Bump PATCH and MINOR versions:
   - Poetry: `poetry update <package>` or edit pyproject.toml constraints.
   - pip: Update version pins in requirements.txt or pyproject.toml.
3. For MAJOR bumps, review the changelog. Only proceed if safe.
4. Regenerate the lockfile (`poetry lock` or `pip-compile`).
5. Run the test suite (`pytest` or the project's configured test command).
6. Run linting (`ruff check .` or `flake8`) if configured.
7. Open a PR titled "chore(deps): weekly Python dependency updates".
```

### Maven / Gradle (Java/Kotlin)

```text
You are maintaining a Java/Kotlin repository.

1. Check for outdated dependencies:
   - Maven: `mvn versions:display-dependency-updates`
   - Gradle: `./gradlew dependencyUpdates` (requires the versions plugin)
2. Bump PATCH and MINOR versions in pom.xml or build.gradle(.kts).
3. For MAJOR bumps, check the release notes. Only bump if migration is trivial.
4. Run the build and test suite:
   - Maven: `mvn clean verify`
   - Gradle: `./gradlew clean build`
5. Open a PR titled "chore(deps): weekly Java dependency updates" with a table of changes.
```

### NuGet (.NET)

```text
You are maintaining a .NET repository.

1. Run `dotnet list package --outdated --format json` to find stale packages.
2. Bump PATCH and MINOR versions using `dotnet add package <name> --version <new>`.
3. For MAJOR bumps, review the release notes and only proceed if migration is safe.
4. Run `dotnet build` and `dotnet test` to verify.
5. Open a PR titled "chore(deps): weekly NuGet dependency updates".
```

### Go Modules

```text
You are maintaining a Go repository.

1. Run `go list -m -u all` to find available updates.
2. For each outdated module:
   - PATCH/MINOR: run `go get <module>@latest` (or the specific version).
   - MAJOR: check the module's changelog. Only bump if no breaking changes affect us.
     Note that Go major versions often change import paths (e.g., v1 → v2).
3. Run `go mod tidy` to clean up go.sum.
4. Run `go test ./...` to verify.
5. Run `go vet ./...` and the project's linter if configured.
6. Open a PR titled "chore(deps): weekly Go module updates".
```

### Cargo (Rust)

```text
You are maintaining a Rust repository.

1. Run `cargo outdated` (requires cargo-outdated) to list stale crates.
   Alternatively, review Cargo.toml and compare with crates.io.
2. Bump PATCH and MINOR versions in Cargo.toml.
3. For MAJOR bumps, review the crate's changelog and migration guide.
4. Run `cargo update` to regenerate Cargo.lock.
5. Run `cargo build` and `cargo test` to verify.
6. Run `cargo clippy` for lint checks.
7. Open a PR titled "chore(deps): weekly Cargo dependency updates".
```

---

## Handling Major vs Minor vs Patch Updates

Different update types carry different risk levels. Here's a recommended strategy:

| Update Type | Risk | Recommended Policy |
|-------------|------|-------------------|
| **Patch** (e.g., 1.2.3 → 1.2.4) | Low — bug fixes only | Auto-bump, auto-merge if tests pass |
| **Minor** (e.g., 1.2.3 → 1.3.0) | Medium — new features, possible deprecations | Auto-bump, require human review before merge |
| **Major** (e.g., 1.2.3 → 2.0.0) | High — breaking changes likely | Only bump if changelog confirms safety; otherwise skip and flag for human action |

### Configuring Different Cadences by Update Type

You can create separate schedules for different update types:

```bash
# Weekly: patch + minor updates (lower risk, higher frequency)
curl -s -X POST "https://api.devin.ai/v1/schedules" \
  -H "Authorization: Bearer $DEVIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "cron": "0 9 * * 1",
    "title": "Weekly patch+minor dependency updates — my-app",
    "prompt": "Check for outdated dependencies. Only bump PATCH and MINOR versions. Run tests and open a PR.",
    "repos": [
      { "url": "https://github.com/my-org/my-app" }
    ]
  }'

# Monthly: major version assessment (higher risk, lower frequency)
curl -s -X POST "https://api.devin.ai/v1/schedules" \
  -H "Authorization: Bearer $DEVIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "cron": "0 9 1 * *",
    "title": "Monthly major version assessment — my-app",
    "prompt": "Check for MAJOR version updates in all dependencies. For each, review the changelog and migration guide. If the upgrade is safe, bump the version, run tests, and include migration notes in the PR. If migration is complex, create a GitHub issue describing the required changes instead of bumping.",
    "repos": [
      { "url": "https://github.com/my-org/my-app" }
    ]
  }'
```

---

## Triggering via GitHub Actions (Alternative)

Instead of using Devin's native scheduler, you can trigger dependency update sessions from a GitHub Actions cron workflow:

```yaml
# .github/workflows/devin-dependency-updates.yml
name: Devin Dependency Updates

on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 09:00 UTC
  workflow_dispatch:

jobs:
  update-deps:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Devin session
        run: |
          curl -s -X POST "https://api.devin.ai/v1/sessions" \
            -H "Authorization: Bearer ${{ secrets.DEVIN_API_KEY }}" \
            -H "Content-Type: application/json" \
            -d '{
              "prompt": "Check for outdated dependencies in ${{ github.repository }}. Bump patch and minor versions, run the test suite, and open a PR with a summary of all changes. Skip major version bumps unless the changelog confirms no breaking changes."
            }'
```

This approach gives you GitHub Actions audit logs and the ability to gate runs on branch protection rules.

---

## Tips

- **Lockfile hygiene**: Always regenerate lockfiles (`package-lock.json`, `poetry.lock`, `Cargo.lock`, etc.) after bumping versions. Never edit lockfiles manually.
- **Monorepo support**: For monorepos, instruct Devin to update dependencies workspace-by-workspace and run tests for each affected workspace.
- **Private registries**: If your project uses private npm/PyPI/Maven registries, ensure Devin has the credentials configured via organization secrets or environment setup.
- **Security-only updates**: Consider a separate schedule that specifically targets packages with known CVEs using tools like `npm audit`, `pip-audit`, or `cargo audit`.
- **PR merge strategy**: Teams that trust their test suites can enable auto-merge for patch-only update PRs to keep the feedback loop tight.
