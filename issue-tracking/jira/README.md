# Jira Integration for Devin

> Planned — not yet implemented.

Trigger Devin sessions from Jira issue transitions and webhooks.

## Planned Components

| Component | Description | Status |
|---|---|---|
| `webhook-receiver/` | HTTP endpoint that receives Jira webhooks and triggers Devin sessions | Planned |

## Use Cases

- Trigger a Devin session when a Jira issue moves to "In Development"
- Auto-generate implementation plans from Jira story descriptions
- Create Devin sessions for bug investigation when issues are filed

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [Jira Webhooks](https://developer.atlassian.com/server/jira/platform/webhooks/)
