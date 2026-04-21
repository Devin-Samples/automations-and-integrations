# CI/CD Integrations

Trigger and manage Devin sessions from your CI/CD pipelines. Each subdirectory contains platform-specific workflows, templates, or webhook receivers.

## Platforms

| Platform | Directory | Description | Status |
|---|---|---|---|
| **GitHub Actions** | [`github-actions/`](github-actions/) | Workflow files that trigger Devin sessions from PR events, issue comments, and schedules | Available |
| **Azure DevOps** | [`azure-devops/`](azure-devops/) | Webhook receiver for work item tag events, MCP server setup for querying ADO | Available |
| **GitLab CI/CD** | [`gitlab-ci/`](gitlab-ci/) | `.gitlab-ci.yml` job templates and webhook integrations | Planned |
| **Jenkins** | [`jenkins/`](jenkins/) | Shared library pipeline steps for calling the Devin API from Jenkinsfiles | Planned |
| **Bitbucket Pipelines** | [`bitbucket/`](bitbucket/) | Bitbucket Pipe and `bitbucket-pipelines.yml` snippets | Planned |

## Common Use Cases

- Trigger a Devin session when a pull request / merge request is opened for automated review
- Start Devin from issue comments using a `/devin <prompt>` command
- Run Devin on a cron schedule for recurring tasks (dependency updates, audits, documentation)
- Kick off Devin-powered release notes generation on pipeline completion

## Getting Started

1. Add your Devin API key as a secret in your CI/CD platform
2. Browse the platform directory for your CI/CD system
3. Copy and customize the sample for your workflow

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
