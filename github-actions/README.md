# GitHub Actions for Devin

Sample GitHub Actions workflows for triggering and managing Devin sessions.

## Examples

| Workflow | Description |
|---|---|
| [`trigger-on-issue-comment.yml`](examples/trigger-on-issue-comment.yml) | Start a Devin session when a specific comment (e.g. `/devin`) is posted on an issue |
| [`trigger-on-pr.yml`](examples/trigger-on-pr.yml) | Trigger a Devin session on pull request events (opened, review requested) |
| [`scheduled-maintenance.yml`](examples/scheduled-maintenance.yml) | Run Devin on a cron schedule for recurring tasks (dependency updates, audits) |

## Setup

1. Add your Devin API key as a repository secret named `DEVIN_API_KEY`
2. Copy the desired workflow file into your repo's `.github/workflows/` directory
3. Customize the workflow triggers and Devin session parameters for your use case

## Reference

- [Devin API — Create Session](https://docs.devin.ai/api-reference/overview)
- [GitHub Actions documentation](https://docs.github.com/en/actions)
