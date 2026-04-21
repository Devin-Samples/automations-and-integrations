# Observability Integrations for Devin

> Planned — not yet implemented.

Alert-driven Devin sessions for automated log analysis, incident investigation, and remediation.

## Directories

| Directory | Description | Status |
|---|---|---|
| `datadog/` | Datadog webhook integration to trigger Devin on monitor alerts | Planned |
| `newrelic/` | New Relic webhook integration to trigger Devin on alert conditions | Planned |

## Use Cases

- Automatically spawn a Devin session when a Datadog monitor fires to investigate root cause
- Trigger Devin for log analysis when New Relic detects anomalies
- Post-incident analysis — feed Devin the alert context and relevant logs

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [Datadog Webhooks](https://docs.datadoghq.com/integrations/webhooks/)
- [New Relic Webhook Notifications](https://docs.newrelic.com/docs/alerts-applied-intelligence/notifications/notification-integrations/#webhook)
