# automations-and-integrations

> **Reference Only / Community-Maintained** — This repository is not an official Cognition AI product. It is a community-contributed collection of sample automations and integration patterns maintained by the [Devin-Samples](https://github.com/Devin-Samples) organization. It is not supported, endorsed, or guaranteed by Cognition AI's core engineering team.

Sample GitHub Actions, webhook receivers, pipeline templates, and deployable infrastructure for integrating [Devin](https://devin.ai) into your software development lifecycle (SDLC).

---

## Disclaimer

**This repository contains reference implementations provided "as is".** These samples are intended as starting points — not production-ready solutions. Specifically:

- **No stability guarantees.** Samples may change without notice as the Devin API evolves.
- **No official support.** For issues with these samples, please [open a GitHub issue](https://github.com/Devin-Samples/automations-and-integrations/issues). For issues with the Devin API itself, contact [support@cognition.ai](mailto:support@cognition.ai).
- **Not production-hardened.** If you deploy these integrations, you do so at your own risk. Thoroughly test, review, and validate for your environment before use.
- **Security is your responsibility.** These samples demonstrate patterns — you must implement proper secret management, access controls, and input validation for your deployment.

## Repository Structure

```
automations-and-integrations/
│
├── github-actions/              # GitHub Actions workflows for Devin
│   └── examples/                #   Sample .yml workflow files
│
├── azure-devops/                # Azure DevOps integration
│   ├── webhook-receiver/        #   Service hook event receiver (Azure Function)
│   └── mcp-setup/               #   MCP server setup guide for querying ADO
│
├── jira/                        # Jira webhook integration (planned)
│   └── webhook-receiver/
│
├── slack/                       # Slack bot / slash commands (planned)
│   └── bot/
│
├── jenkins/                     # Jenkins pipeline plugin (planned)
│   └── pipeline-plugin/
│
├── gitlab-ci/                   # GitLab CI/CD templates (planned)
│   └── templates/
│
├── bitbucket/                   # Bitbucket Pipelines integration (planned)
│   └── pipelines/
│
├── observability/               # Alert-driven Devin sessions (planned)
│   ├── datadog/
│   └── newrelic/
│
├── incident-response/           # Incident auto-triage (planned)
│   ├── pagerduty/
│   └── opsgenie/
│
├── issue-trackers/              # Issue tracker integrations (planned)
│   ├── linear/
│   └── servicenow/
│
├── infrastructure/              # Deployable IaC for hosting integrations
│   ├── terraform/               #   Terraform modules
│   └── cloudformation/          #   AWS CloudFormation templates
│
├── docs/
│   ├── setup-guide/             # Step-by-step configuration guides
│   └── architecture/            # Reference architecture diagrams
│
├── LICENSE
├── NOTICE
└── README.md
```

## Integrations Roadmap

| Integration | Directory | Description | Status |
|---|---|---|---|
| **GitHub Actions** | [`github-actions/`](github-actions/) | Trigger Devin sessions from PR events, issue comments, scheduled workflows | Available |
| **Azure DevOps** | [`azure-devops/`](azure-devops/) | Webhook receiver for work item tag events, MCP server setup for querying ADO | Available |
| **Jira** | [`jira/`](jira/) | Trigger Devin sessions from Jira issue transitions and webhooks | Planned |
| **Slack** | [`slack/`](slack/) | Slash commands and bot integration to create/monitor Devin sessions | Planned |
| **Jenkins** | [`jenkins/`](jenkins/) | Pipeline steps and webhook-based triggers for Devin | Planned |
| **GitLab CI/CD** | [`gitlab-ci/`](gitlab-ci/) | `.gitlab-ci.yml` templates and webhook integrations | Planned |
| **Bitbucket Pipelines** | [`bitbucket/`](bitbucket/) | Pipe and webhook integration for Devin session management | Planned |
| **Datadog / New Relic** | [`observability/`](observability/) | Alert-driven Devin sessions for automated log analysis and remediation | Planned |
| **PagerDuty / Opsgenie** | [`incident-response/`](incident-response/) | Auto-triage incidents by spawning Devin sessions for investigation | Planned |
| **Linear / ServiceNow** | [`issue-trackers/`](issue-trackers/) | Trigger Devin sessions from issue tracker transitions | Planned |
| **Terraform / CloudFormation** | [`infrastructure/`](infrastructure/) | Deployable IaC for hosting webhook receivers and supporting infra | Planned |

## Getting Started

### Prerequisites

- A Devin account with API access ([Teams quickstart](https://docs.devin.ai/api-reference/getting-started/teams-quickstart) or [Enterprise quickstart](https://docs.devin.ai/api-reference/getting-started/enterprise-quickstart))
- A Devin API key (created via a service user in your organization settings)

### Quick Start

1. Browse the integration directory you're interested in
2. Follow the README in that directory for setup instructions
3. Configure your Devin API key as a secret in your CI/CD platform
4. Customize the sample to fit your workflow

For infrastructure deployment, see the [`infrastructure/`](infrastructure/) directory and the [setup guide](docs/setup-guide/).

## Contributing

Contributions are welcome! Please see the org-wide [contributing guidelines](https://github.com/Devin-Samples/.github/blob/main/CONTRIBUTING.md) before submitting a pull request.

If you find a bug or have a feature request, please [open an issue](https://github.com/Devin-Samples/automations-and-integrations/issues).

## Security

If you discover a security vulnerability, please do **not** open a public GitHub issue. Instead, email [brian.smitches@cognition.ai](mailto:brian.smitches@cognition.ai).

## License

This project is licensed under the [MIT No Attribution (MIT-0)](LICENSE) license.

## Notice

This project is part of [Devin-Samples](https://github.com/Devin-Samples) — example code that demonstrates practical implementations of Devin for specific use cases and scenarios. These application solutions are not supported products in their own right, but educational examples to help customers and partners use Devin for their applications. Any applications you integrate these examples into should be thoroughly tested, secured, and optimized according to your business's security standards and policies before deploying to production or handling production workloads.
