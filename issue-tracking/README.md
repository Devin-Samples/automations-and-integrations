# Issue Tracking Integrations

Trigger Devin sessions from issue tracker transitions, events, and webhooks. Each subdirectory contains platform-specific webhook receivers or automation scripts.

## Platforms

| Platform | Directory | Description | Status |
|---|---|---|---|
| **Jira** | [`jira/`](jira/) | Webhook receiver that triggers Devin on issue transitions | Planned |
| **Linear** | `linear/` | Webhook integration for Devin on issue state changes | Planned |
| **ServiceNow** | `servicenow/` | Webhook integration for change requests and incidents | Planned |

## Common Use Cases

- Trigger a Devin session when an issue moves to "In Development" or "In Progress"
- Auto-generate implementation plans from story descriptions
- Create Devin sessions for bug investigation when issues are filed
- Automated implementation from ServiceNow change requests

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [Jira Webhooks](https://developer.atlassian.com/server/jira/platform/webhooks/)
- [Linear Webhooks](https://developers.linear.app/docs/graphql/webhooks)
- [ServiceNow REST API](https://developer.servicenow.com/dev.do#!/reference/api/latest/rest)
