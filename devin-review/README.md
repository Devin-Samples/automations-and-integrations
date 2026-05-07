# Devin Review

Devin Review is a proactive code review capability that analyzes new pull requests for bugs, security issues, quality problems, and style inconsistencies. It runs automatically on PRs and posts findings as review comments — catching issues that traditional linters and CI checks miss.

## Capabilities

| Feature | Description |
|---------|-------------|
| **Bug Detection** | Logic errors, null pointer risks, race conditions, off-by-one errors, edge cases |
| **Security Analysis** | Hardcoded secrets, injection vulnerabilities, insecure defaults, auth bypass patterns |
| **PR Summarization** | Readable overviews of large diffs highlighting key changes, risks, and architectural impact |
| **Proactive Remediation** | Automatically opens fix PRs for discovered issues (optional) |
| **Custom Rules** | Configure focus areas and sensitivity per repository |
| **Style & Consistency** | Naming conventions, code organization, API design consistency |

---

## Setup Walkthrough

### Step 1: Access Devin Review Settings

1. Log in to your Devin organization at [app.devin.ai](https://app.devin.ai)
2. Click the **gear icon** in the left sidebar to open **Settings**
3. Select **Devin Review** from the settings menu

You'll see the Devin Review configuration panel with a list of connected repositories and global settings.

### Step 2: Connect Your Git Provider

If not already connected, link your GitHub/GitLab/Azure DevOps organization:

1. In **Settings > Git Connections**, click **Add Connection**
2. Select your provider (GitHub, GitLab, or Azure DevOps)
3. Authorize the Devin GitHub App (or equivalent) with access to the repositories you want reviewed
4. Once connected, your repositories appear in the Devin Review configuration panel

### Step 3: Enable Devin Review for Repositories

You can enable Devin Review at two levels:

**Organization-wide (recommended for rollout):**
1. In **Settings > Devin Review**, toggle **Enable for all repositories**
2. This applies Devin Review to every repository in the connected organization
3. Individual repos can be excluded via the repo-level override (see below)

**Per-repository:**
1. In **Settings > Devin Review**, find the repository list
2. Toggle the switch next to each repository you want reviewed
3. Click the repository name to access per-repo configuration

### Step 4: Configure Review Behavior

For each enabled repository (or at the org level), configure:

| Setting | Options | Recommended Default |
|---------|---------|-------------------|
| **Review mode** | `comment` (post findings as PR comments) or `review` (submit as a GitHub review) | `review` |
| **Auto-remediation** | `off`, `suggest` (post fix as comment), `auto-pr` (open fix PR automatically) | `suggest` |
| **Sensitivity** | `low`, `medium`, `high` | `medium` |
| **Focus areas** | Bugs, Security, Style, Performance, Documentation (multi-select) | Bugs + Security |
| **File filters** | Glob patterns to include/exclude (e.g., `!*.test.ts`, `!vendor/**`) | Exclude tests and generated code |
| **PR size threshold** | Minimum diff size to trigger review (e.g., skip single-line typo fixes) | 5 lines |

### Step 5: Verify the Integration

1. Open a test PR in one of the enabled repositories
2. Within a few minutes, Devin Review should post findings as review comments
3. Check the PR's **Checks** tab — you should see a "Devin Review" status check
4. If no findings are posted, verify the repository is enabled and the PR meets the size threshold

---

## Configuration Options

### Per-Repository vs Organization-Wide

| Scope | Best For | How to Configure |
|-------|----------|-----------------|
| **Organization-wide** | Consistent review standards across all repos | Settings > Devin Review > Enable for all repositories |
| **Per-repository** | Different sensitivity/rules for different projects | Settings > Devin Review > Click repo name > Override settings |

Per-repo settings **override** org-wide settings. This lets you set a baseline at the org level and customize for specific repos (e.g., higher sensitivity for security-critical services, lower for internal tools).

### Sensitivity Levels

| Level | Behavior | Use Case |
|-------|----------|----------|
| **Low** | Only flags high-confidence issues: confirmed bugs, definite security vulnerabilities, clear logic errors | Legacy codebases, high-churn repos where false positives cause friction |
| **Medium** | Flags likely issues: probable bugs, security concerns, significant style deviations | Most production repositories (recommended default) |
| **High** | Flags potential issues: possible edge cases, minor style inconsistencies, documentation gaps | Security-critical services, regulated codebases, greenfield projects |

### Auto-Remediation Toggle

Auto-remediation controls whether Devin Review goes beyond identifying issues to actually fixing them:

| Mode | Behavior |
|------|----------|
| **Off** | Devin Review only posts findings as comments. No fix suggestions. |
| **Suggest** | Devin Review posts a suggested code fix inline with the finding comment. The developer applies it manually. |
| **Auto-PR** | Devin Review opens a separate fix PR targeting the original PR's branch. The developer reviews and merges the fix. |

**Recommendation:** Start with `suggest` mode. This lets the team see fix quality before trusting auto-PRs. Escalate to `auto-pr` for high-confidence finding types (e.g., unused imports, missing null checks) once the team is comfortable.

---

## Example Findings

### Bug Detection

```
📋 Devin Review — Bug: Potential null pointer dereference

In `src/services/user.ts`, line 42:

    const email = user.profile.email.toLowerCase();

`user.profile` may be null if the user hasn't completed onboarding.
This will throw a TypeError at runtime.

Suggested fix:
    const email = user.profile?.email?.toLowerCase() ?? '';
```

### Security Issue

```
📋 Devin Review — Security: SQL injection vulnerability

In `src/api/routes/search.ts`, line 87:

    const query = `SELECT * FROM products WHERE name LIKE '%${req.query.term}%'`;

User input is interpolated directly into an SQL query string. This is
vulnerable to SQL injection.

Suggested fix: Use parameterized queries:
    const query = `SELECT * FROM products WHERE name LIKE $1`;
    const params = [`%${req.query.term}%`];
    const result = await db.query(query, params);
```

### Style Inconsistency

```
📋 Devin Review — Style: Inconsistent error handling pattern

In `src/services/payment.ts`, lines 23-31:

This function uses try/catch with console.error, but all other service
functions in this codebase use the centralized `logger.error()` utility
and re-throw wrapped errors via `AppError`.

Suggested fix: Align with the project's error handling convention:
    } catch (error) {
      logger.error('Payment processing failed', { error, paymentId });
      throw new AppError('PAYMENT_FAILED', 'Payment processing failed', error);
    }
```

### Performance

```
📋 Devin Review — Performance: N+1 query detected

In `src/api/routes/orders.ts`, lines 15-22:

    const orders = await Order.findAll();
    for (const order of orders) {
      order.items = await OrderItem.findAll({ where: { orderId: order.id } });
    }

This executes N+1 database queries (1 for orders + 1 per order for items).
For 100 orders, this means 101 queries.

Suggested fix: Use eager loading:
    const orders = await Order.findAll({
      include: [{ model: OrderItem, as: 'items' }]
    });
```

---

## Integration with Required Status Checks

Devin Review can be configured as a **required status check** for merge protection — meaning PRs cannot be merged until Devin Review has run and (optionally) until all findings are addressed.

### Setting Up as a Required Check

1. **In GitHub:**
   - Go to **Settings > Branches > Branch protection rules**
   - Edit (or create) the rule for your default branch (e.g., `main`)
   - Under **Require status checks to pass before merging**, search for `Devin Review`
   - Check the box to require it
   - Click **Save changes**

2. **In GitLab:**
   - Go to **Settings > Merge Requests > Merge checks**
   - Enable **Pipelines must succeed**
   - Devin Review posts its status as a pipeline external check

3. **In Azure DevOps:**
   - Go to **Repos > Branches > Branch policies** for your target branch
   - Under **Status checks**, add `Devin Review` as a required check

### Merge Blocking Behavior

| Configuration | Merge Behavior |
|--------------|----------------|
| Devin Review as **optional** check | Review runs and posts findings, but PR can merge regardless |
| Devin Review as **required** check | PR cannot merge until Devin Review completes |
| Required + **no unresolved findings** | PR cannot merge until all Devin Review findings are resolved or dismissed |

**Recommendation:** Start with Devin Review as an **optional** check. Once the team trusts the signal quality (low false positive rate), promote it to **required**.

---

## Best Practices for Rolling Out Devin Review

### Phase 1: Observation Mode (Weeks 1–2)

**Goal:** Build team trust and calibrate settings.

- Enable Devin Review with **medium sensitivity** and **auto-remediation off**
- Set it as an **optional** (non-blocking) status check
- Let it run on all PRs for 1–2 weeks
- Track metrics:
  - How many findings per PR?
  - What percentage are true positives vs false positives?
  - Which finding categories are most valuable?
- Share a summary with the team: *"Devin Review found X bugs and Y security issues this week that made it to production. Here are some examples."*

### Phase 2: Calibration (Weeks 3–4)

**Goal:** Reduce noise and increase signal.

- Review false positives from Phase 1 and adjust:
  - Lower sensitivity for noisy categories
  - Add file exclusion filters for generated code, vendored deps, test files (if desired)
  - Disable finding types that consistently produce low-value results
- Enable **suggest** auto-remediation for high-confidence finding types
- Continue as optional check

### Phase 3: Promotion (Month 2+)

**Goal:** Make Devin Review a standard part of the review process.

- Promote Devin Review to a **required** status check
- Enable **auto-pr** remediation for well-understood finding types (e.g., security fixes, unused imports)
- Establish a team norm: "Address or dismiss all Devin Review findings before requesting human review"
- Monitor merge velocity — if Devin Review is blocking too many PRs, revisit sensitivity settings

### Phase 4: Expansion (Ongoing)

**Goal:** Extend coverage and customize.

- Roll out to additional repositories
- Create repo-specific rules for different project types (e.g., stricter security for backend APIs, stricter style for shared libraries)
- Integrate with team retrospectives: use Devin Review findings data to identify recurring quality issues and invest in systemic fixes
- Set up Slack/Teams notifications for critical findings (severity: high, category: security)

---

## Frequently Asked Questions

**Q: Does Devin Review work with monorepos?**
A: Yes. Use file filters to scope reviews to specific packages or directories. Devin Review analyzes the diff, so it only reviews changed files regardless of repo structure.

**Q: How long does a review take?**
A: Most reviews complete in 1–3 minutes for typical PRs (under 500 lines changed). Very large PRs (1000+ lines) may take longer.

**Q: Can I configure different rules for different directories?**
A: Use file filters at the repo level. For more granular control, create a `.devin-review.yml` configuration file in the repo root to define per-path rules.

**Q: Does Devin Review consume ACUs?**
A: Devin Review is included with your Devin subscription and runs separately from session-based ACU usage. Check your plan details for specific limits.

**Q: Can I disable Devin Review for specific PRs?**
A: Add the label `skip-devin-review` to a PR to bypass Devin Review for that PR. This is useful for automated PRs (e.g., dependency bumps from Dependabot) or trivial changes.

**Q: How do I dismiss a finding?**
A: Reply to the Devin Review comment with a reason for dismissal. Devin Review tracks dismissals and learns from them to reduce similar false positives in the future.

---

## Reference

- [Devin Review documentation](https://docs.devin.ai)
- [Configuring review rules](https://docs.devin.ai)
- [Devin API reference](https://docs.devin.ai/api-reference/overview)
