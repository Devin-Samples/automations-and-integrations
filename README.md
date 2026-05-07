# automations-and-integrations

> **Reference Only / Community-Maintained** — This repository is not an official Cognition AI product. It is a community-contributed collection of sample automations and integration patterns maintained by the [Devin-Samples](https://github.com/Devin-Samples) organization. It is not supported, endorsed, or guaranteed by Cognition AI's core engineering team.

Sample workflows, webhook receivers, pipeline templates, network connectivity patterns, and deployable infrastructure for integrating [Devin](https://devin.ai) into your software development lifecycle (SDLC).

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
├── ci-cd/                             # CI/CD pipeline integrations
│   ├── github-actions/                #   GitHub Actions workflows (available)
│   ├── azure-devops/                  #   Azure DevOps webhooks + pipelines (available)
│   ├── gitlab-ci/                     #   GitLab CI/CD templates (planned)
│   ├── jenkins/                       #   Jenkins pipeline steps (planned)
│   └── bitbucket/                     #   Bitbucket Pipelines (planned)
│
├── network-connectivity/              # Private network access patterns
│   ├── aws/                           #   AWS connectivity patterns
│   │   ├── ssm-port-forwarding/       #     SSM tunnel to private VPC resources (available)
│   │   ├── client-vpn/                #     Full subnet VPN access (planned)
│   │   └── privatelink/               #     Service-to-service connectivity (planned)
│   ├── azure/                         #   Azure connectivity patterns
│   │   ├── bastion-tunneling/         #     Azure Bastion native tunneling (planned)
│   │   ├── private-endpoints/         #     Private IP for PaaS services (planned)
│   │   └── vpn-gateway/               #     Point-to-site / site-to-site VPN (planned)
│   └── gcp/                           #   GCP connectivity patterns
│       ├── iap-tunneling/             #     IAP TCP forwarding (planned)
│       └── private-service-connect/   #     Private IP for Google APIs (planned)
│
├── issue-tracking/                    # Issue tracker integrations
│   └── jira/                          #   Jira webhook receiver (planned)
│                                      #   Linear, ServiceNow (planned)
│
├── messaging/                         # Team messaging integrations
│   └── slack/                         #   Slack bot and slash commands (planned)
│                                      #   Microsoft Teams (planned)
│
├── observability/                     # Alert-driven Devin sessions
│   ├── datadog/                       #   Datadog webhook integration (planned)
│   └── newrelic/                      #   New Relic webhook integration (planned)
│
├── incident-response/                 # Incident auto-triage
│   ├── pagerduty/                     #   PagerDuty webhook integration (planned)
│   └── opsgenie/                      #   Opsgenie webhook integration (planned)
│
├── security-scanning/                 # SAST/SCA → Devin remediation
│   ├── sonarqube/                     #   SonarQube/SonarCloud webhook (available)
│   ├── snyk/                          #   Snyk webhook integration (available)
│   ├── checkmarx/                     #   Checkmarx webhook integration (planned)
│   └── trivy/                         #   Trivy CI pipeline integration (available)
│
├── scheduled-maintenance/             # Proactive O&M via scheduled sessions
│   ├── dependency-updates/            #   Automated version bumps (available)
│   ├── code-hygiene/                  #   Dead code, import cleanup (available)
│   └── license-compliance/            #   License audit automation (available)
│
├── devin-review/                      # Devin Review configuration & patterns
│
├── docs/
│   ├── setup-guide/                   #   Step-by-step configuration guides
│   └── architecture/                  #   Reference architecture diagrams
│
├── LICENSE
├── NOTICE
└── README.md
```

## Integration Categories

| Category | Directory | Description | Status |
|---|---|---|---|
| **CI/CD** | [`ci-cd/`](ci-cd/) | Trigger Devin from pull requests, issue comments, schedules, and pipeline events | GitHub Actions & Azure DevOps available; others planned |
| **Network Connectivity** | [`network-connectivity/`](network-connectivity/) | Connect Devin to private resources in AWS, Azure, and GCP VPCs | AWS SSM port-forwarding available; others planned |
| **Issue Tracking** | [`issue-tracking/`](issue-tracking/) | Trigger Devin from issue transitions in Jira, Linear, ServiceNow | Planned |
| **Messaging** | [`messaging/`](messaging/) | Slash commands and bots for Slack, Microsoft Teams | Planned |
| **Observability** | [`observability/`](observability/) | Alert-driven Devin sessions from Datadog, New Relic | Planned |
| **Incident Response** | [`incident-response/`](incident-response/) | Auto-triage incidents from PagerDuty, Opsgenie | Planned |
| **Security Scanning** | [`security-scanning/`](security-scanning/) | SAST/SCA finding → Devin remediation pipeline | SonarQube, Snyk & Trivy available; others planned |
| **Scheduled Maintenance** | [`scheduled-maintenance/`](scheduled-maintenance/) | Proactive O&M via Devin scheduled sessions | Available |
| **Devin Review** | [`devin-review/`](devin-review/) | Devin Review setup, configuration, and best practices | Available |

## Getting Started

### Prerequisites

- A Devin account with API access ([Teams quickstart](https://docs.devin.ai/api-reference/getting-started/teams-quickstart) or [Enterprise quickstart](https://docs.devin.ai/api-reference/getting-started/enterprise-quickstart))
- A Devin API key (created via a service user in your organization settings)

### Quick Start

1. Browse the category directory for the integration you need
2. Follow the README in the specific platform directory for setup instructions
3. Configure your Devin API key and any required credentials
4. Customize the sample to fit your workflow

**New to private network access?** Start with the [Network Connectivity decision guide](network-connectivity/) to find the right pattern for your cloud provider and use case.

## Contributing

Contributions are welcome! Please see the org-wide [contributing guidelines](https://github.com/Devin-Samples/.github/blob/main/CONTRIBUTING.md) before submitting a pull request.

If you find a bug or have a feature request, please [open an issue](https://github.com/Devin-Samples/automations-and-integrations/issues).

## Security

If you discover a security vulnerability, please do **not** open a public GitHub issue. Instead, email [brian.smitches@cognition.ai](mailto:brian.smitches@cognition.ai).

## License

This project is licensed under the [MIT No Attribution (MIT-0)](LICENSE) license.

## Notice

This project is part of [Devin-Samples](https://github.com/Devin-Samples) — example code that demonstrates practical implementations of Devin for specific use cases and scenarios. These application solutions are not supported products in their own right, but educational examples to help customers and partners use Devin for their applications. Any applications you integrate these examples into should be thoroughly tested, secured, and optimized according to your business's security standards and policies before deploying to production or handling production workloads.
