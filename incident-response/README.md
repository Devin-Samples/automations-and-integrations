# Incident Response Integrations for Devin

> Planned — not yet implemented.

Auto-triage incidents by spawning Devin sessions for investigation and remediation.

## Directories

| Directory | Description | Status |
|---|---|---|
| `pagerduty/` | PagerDuty webhook integration to trigger Devin on incidents | Planned |
| `opsgenie/` | Opsgenie webhook integration to trigger Devin on alerts | Planned |

## Use Cases

- Automatically create a Devin session when a P1/P2 incident is triggered
- Feed incident context (runbook, service map, recent changes) to Devin for initial triage
- Post investigation summaries back to the incident timeline

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [PagerDuty Webhooks](https://developer.pagerduty.com/docs/db0fa8c8984fc-overview)
- [Opsgenie Webhook Integration](https://support.atlassian.com/opsgenie/docs/integrate-opsgenie-with-webhook/)
