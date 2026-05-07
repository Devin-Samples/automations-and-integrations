# Devin Review

A full-service code review platform within the Devin webapp that turns large, complex PRs into intuitively organized diffs and precise explanations. As coding agents become more prevalent, the bottleneck shifts from writing code to reviewing it — Devin Review addresses this by making PRs faster to understand and act on.

> **Official documentation:** [docs.devin.ai/work-with-devin/devin-review](https://docs.devin.ai/work-with-devin/devin-review.md)

## Features

| Feature | Description |
|---------|-------------|
| **Logical Diff Grouping** | Groups related changes together instead of alphabetical file order |
| **Code Move Detection** | Detects copied/moved code and displays changes cleanly instead of full deletes and inserts |
| **Bug Catcher** | Analyzes PRs for bugs (severe and non-severe) and flags (investigate, informational) |
| **Codebase-Aware Chat** | Ask questions about the PR and get answers with context from the rest of the codebase |
| **Code Changes from Chat** | Ask the chat agent to make edits, review suggestions, and apply as commits without leaving Review |
| **PR Workflow Actions** | Merge, close, convert to draft, mark ready for review, and toggle auto-merge directly from Review |
| **Auto-Fix** | Automatically suggests and applies fixes for detected bugs |
| **REVIEW.md Support** | Respects instruction files (REVIEW.md, AGENTS.md, CONTRIBUTING.md, .cursorrules, etc.) for project-specific review context |

---

## Supported Git Providers

| Capability | GitHub | GitLab |
|------------|--------|--------|
| View diffs and analysis | Yes | Coming soon |
| Bug catcher | Yes | Coming soon |
| Codebase-aware chat | Yes | Coming soon |
| Code changes from chat | Yes | Coming soon |
| Comments and reviews | Yes | Coming soon |
| Merge / close / draft actions | Yes | Coming soon |
| Auto-merge | Yes | Coming soon |
| Auto-review | Yes | Coming soon |

**GitHub** includes GitHub.com, GitHub Enterprise Server, and GitHub Enterprise Cloud — all have the same capabilities.

**Write features** (comments, reviews, merge actions, code changes from chat) require a [GitHub App](https://docs.devin.ai/integrations/gh) connection installed on your GitHub organization. PAT-based connections are read-only.

---

## Getting Started

There are multiple ways to access Devin Review:

| Method | How |
|--------|-----|
| **Devin webapp** | Go to [app.devin.ai/review](https://app.devin.ai/review) to see your open PRs organized by category (assigned, authored, review requested) |
| **URL shortcut** | For any GitHub.com PR, replace `github.com` with `devinreview.com` in the URL |
| **GitHub Enterprise** | Paste the full PR URL into the Review page at [app.devin.ai/review](https://app.devin.ai/review) |
| **CLI** | Run `npx devin-review {pr-url}` from within a local clone (see [CLI](#cli) below) |
| **From Devin sessions** | When Devin makes PRs, click the orange "Review" button in the chat |

---

## Auto-Review

Devin can automatically review PRs without manual triggering. Configure auto-review in [Settings > Review](https://app.devin.ai/settings/review).

### When Does Auto-Review Run?

Auto-review triggers when:
- A PR is opened (non-draft)
- New commits are pushed to a PR
- A draft PR is marked as ready for review
- An enrolled user is added as a reviewer or assignee

Draft PRs are skipped until marked ready.

### Trigger Modes

| Mode | Behavior |
|------|----------|
| **Auto review** (default) | Reviews trigger on all events: PR opened, new commits, draft marked ready, reviewer/assignee added |
| **On PR creation** | Reviews only trigger when a PR is first opened or a draft is marked ready; subsequent pushes do not trigger |

### Self-Enrollment (All Users)

Any user with a connected GitHub account can enroll themselves — no admin permissions needed:

1. Go to [Settings > Review](https://app.devin.ai/settings/review)
2. Click "Add myself (@yourusername)" to enroll

Once enrolled, Devin automatically reviews any PR you create, are added to as a reviewer, or are assigned to.

### Admin Configuration

Admins have additional options in [Settings > Review](https://app.devin.ai/settings/review):

| Setting | Description |
|---------|-------------|
| **Repositories** | Add repositories to auto-review ALL PRs on that repo |
| **Users** | View and manage all enrolled users across the organization |
| **Insert link in PR description** | When enabled (default), Devin adds a review link in the PR description |

### Posting to GitHub

Admins can configure what Devin Review posts back to GitHub under **Post to GitHub**:

| Setting | Default | Description |
|---------|---------|-------------|
| **Post GitHub PR checks** | On | Creates a commit status check on the PR for each review |
| **Bugs** | On | Posts bugs (likely errors or incorrect behavior) as PR comments |
| **Flags (investigate)** | Off | Posts investigate flags (potential issues worth a closer look) as PR comments |
| **Flags (note)** | Off | Posts informational flags (observations that may not require action) as PR comments |

---

## Bug Catcher

The Bug Catcher analyzes PRs for potential issues and displays findings in the Analysis sidebar.

### Bugs

Actionable errors that should be fixed. Displayed with two severity levels:

| Severity | Description |
|----------|-------------|
| **Severe** | High-confidence issues that require immediate attention |
| **Non-severe** | Lower severity issues that should still be reviewed |

### Flags

Informational code annotations that may or may not require action:

| Class | Description |
|-------|-------------|
| **Investigate** | Warrants further investigation — verify whether there is an actual issue |
| **Informational** | The Bug Catcher has concluded correctness or is explaining how something works |

Findings can be marked as resolved once addressed or determined unnecessary. Resolved items are dimmed and sorted to the bottom.

---

## Auto-Fix

Devin Review can automatically suggest and apply fixes for detected bugs.

### Enabling Auto-Fix

| Method | How |
|--------|-----|
| **PR review settings** | On any Review page, click the settings icon and toggle **Enable Autofix** |
| **Embedded review** | In the embedded Review view inside a Devin session, toggle **Enable Autofix** |
| **Global settings** | [Settings > Customization](https://app.devin.ai/customization) > Pull request settings > Autofix settings |

When enabled, Devin generates suggested fixes alongside bug findings that you can review and apply as commits directly from the diff view.

---

## Permissions

Devin Review uses two permissions, found under **Devin Review permissions** in the role editor:

| Permission | Description | Default |
|-----------|-------------|---------|
| **Use Devin Review** | Required to access Devin Review and configure personal settings (e.g., self-enrollment) | All members and admins |
| **Manage Devin Review** | Required to manage auto-review settings, posting options, and admin configuration | Admins only |

---

## Instruction Files

Devin Review respects instruction files in your repository. If any of these files exist, they are used as context when analyzing PRs:

- `**/REVIEW.md` — Dedicated review instruction file
- `**/AGENTS.md`
- `**/CLAUDE.md` (case-insensitive)
- `**/CONTRIBUTING.md` (case-insensitive)
- `.cursorrules`
- `.windsurfrules`
- `.cursor/rules`
- `*.rules`
- `*.mdc`
- `.coderabbit.yaml` / `.coderabbit.yml`
- `greptile.json`

Files inside agent-like subdirectories (`.agents/`, `.devin/`, `.cursor/`, `.github/`) are scoped to the parent directory.

### Custom Review Rules

Configure additional files as review context from [Settings > Review](https://app.devin.ai/settings/review) under **Review Rules**. Add custom file glob patterns (e.g., `docs/**/*.md`) beyond the defaults.

### Example REVIEW.md

```markdown
# Review Guidelines

## Critical Areas
- All changes to `src/auth/` must be reviewed for security implications.
- Database migration files should be checked for backward compatibility.

## Conventions
- API endpoints must include input validation and proper error handling.
- All public functions require TypeScript return types — do not use `any`.

## Ignore
- Auto-generated files in `src/generated/` do not need review.
- Lock files can be skipped unless dependencies changed.

## Performance
- Flag any database queries inside loops.
- Watch for N+1 query patterns in API resolvers.
```

---

## CLI

Run code reviews from your terminal — useful for private repositories or local workflows.

### Usage

```bash
cd path/to/repo
npx devin-review https://github.com/owner/repo/pull/123
```

Must be run from within the repository being reviewed.

### How It Works

1. **Git-based diff extraction** — Uses your local git access to fetch the PR branch and compute the diff
2. **Isolated worktree checkout** — Creates a git worktree in a cached directory (your working directory stays untouched)
3. **Diff sent to Devin servers** — The computed diff and file contents are sent for analysis
4. **Local code execution** — The Bug Catcher can execute read-only operations (file reading, search, grep) scoped to the worktree for deeper analysis

### Privacy

- **Local-only access by default** — A localhost server serves a secure token; only processes on your machine can access the review page
- **Transfer to your Devin account** — Log in to a Devin account with access to the GitHub organization to share and access from other devices

---

## Commit & Comment Attribution

| Action | Attributed To |
|--------|--------------|
| Bug findings, flags, automated annotations | Devin bot |
| User comments and reviews through Devin Review | User's GitHub identity |
| Code changes from chat | Devin bot |
| GitHub Suggested Changes applied by user | User (standard GitHub behavior) |

Devin will never create commits or comments on behalf of a user without the user explicitly initiating the action.

---

## Best Practices for Rolling Out

### Phase 1: Observation (Weeks 1–2)

- Enable auto-review with default settings (bugs posted to GitHub, flags off)
- Let it run on a few pilot repositories
- Track true positive rate and team feedback
- Share examples: *"Devin Review caught X bugs this week before they reached production"*

### Phase 2: Expand (Weeks 3–4)

- Enroll more users via self-enrollment
- Add more repositories to auto-review
- Enable **investigate** flag posting if the team wants more signal
- Create `REVIEW.md` files in key repos to customize review focus

### Phase 3: Integrate (Month 2+)

- Add Devin Review as a GitHub required status check for critical repositories
- Enable Auto-Fix for Devin-authored PRs
- Establish team norm: review Devin Review findings before requesting human review

---

## Reference

- [Official Devin Review documentation](https://docs.devin.ai/work-with-devin/devin-review.md)
- [GitHub App integration guide](https://docs.devin.ai/integrations/gh)
- [Devin API reference](https://docs.devin.ai/api-reference/overview)
