# Messaging Integrations

Create and monitor Devin sessions from team messaging platforms. Each subdirectory contains platform-specific bots, slash commands, or webhook handlers.

## Platforms

| Platform | Directory | Description | Status |
|---|---|---|---|
| **Slack** | [`slack/`](slack/) | Bot and slash commands for creating and monitoring Devin sessions | Planned |
| **Microsoft Teams** | `teams/` | Teams bot integration for Devin session management | Planned |

## Common Use Cases

- `/devin <prompt>` slash command to create a session from any channel
- Post Devin session status updates to a designated channel
- Interactive session management via message buttons and modals
- Route Devin results (PRs, reports) back to the requesting channel

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [Slack API — Bolt framework](https://slack.dev/bolt-js/concepts)
- [Microsoft Teams Bot Framework](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/what-are-bots)
