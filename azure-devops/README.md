# Azure DevOps Integration for Devin

Two complementary patterns for integrating [Devin](https://devin.ai) with [Azure DevOps](https://dev.azure.com):

| Component | Direction | Description |
|---|---|---|
| [`webhook-receiver/`](webhook-receiver/) | **ADO -> Devin** | Azure Function that receives service hook events and creates Devin sessions when work items are tagged |
| [`mcp-setup/`](mcp-setup/) | **Devin -> ADO** | Guide for setting up a custom MCP server so Devin can query work items, boards, pipelines, and more |

## How They Work Together

```
                    ┌─────────────────────┐
                    │   Azure DevOps      │
                    │   (Work Items,      │
                    │    Boards, Repos)   │
                    └──────┬──────▲───────┘
                           │      │
              Tag triggers │      │ Devin queries
              service hook │      │ via MCP tools
                           │      │
                    ┌──────▼──────┴───────┐
                    │      Devin          │
                    │   (AI Agent)        │
                    └─────────────────────┘
```

- **Webhook Receiver (push):** When a work item is tagged with `Devin:Discovery`, Azure DevOps fires a service hook that triggers the webhook receiver, which creates a new Devin session with the work item details as the prompt.

- **MCP Server (pull):** During any session, Devin can query Azure DevOps on demand — fetching work item details, running WIQL queries, listing pipelines, etc. — using MCP tools.

## Getting Started

- To trigger Devin sessions from work item tags, start with the [**webhook receiver**](webhook-receiver/)
- To let Devin query Azure DevOps data during sessions, start with the [**MCP setup guide**](mcp-setup/)
- For maximum capability, set up both

## Use Cases

- Trigger a Devin session when a work item is tagged (e.g., `Devin:Discovery`)
- Let Devin query work item details, board state, and pipeline status during sessions
- Kick off Devin-powered code review when a pull request is created
- Run Devin for automated release notes generation on pipeline completion

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [Devin MCP documentation](https://docs.devin.ai/work-with-devin/mcp)
- [Azure DevOps Service Hooks](https://learn.microsoft.com/en-us/azure/devops/service-hooks/overview)
- [Azure DevOps REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/)
