# Azure DevOps MCP Server for Devin

Give Devin the ability to **query and interact with Azure DevOps** — work items, boards, repos, pipelines, and more — by setting up a custom MCP (Model Context Protocol) server.

While the [webhook receiver](../webhook-receiver/) pushes events _from_ Azure DevOps _to_ Devin, this MCP integration lets Devin _pull_ information from Azure DevOps on demand during sessions.

## Why Use an MCP Server?

Devin's [native Azure DevOps integration](https://docs.devin.ai/enterprise/integrations/azure-devops) is scoped to **Git operations only** (clone, push, create PRs). It does not cover:

- Work items and boards
- Pipelines and builds
- Test plans
- Wiki pages
- Service connections

An MCP server bridges this gap by exposing the Azure DevOps REST API to Devin as callable tools.

## Setup: Microsoft MCP Server

Use the official [`@azure-devops/mcp`](https://github.com/microsoft/azure-devops-mcp) server from Microsoft, which wraps the Azure DevOps REST API as MCP tools.

> **Note:** Microsoft also offers a [Remote MCP Server](https://learn.microsoft.com/en-us/azure/devops/mcp-server/remote-mcp-server) (public preview) that requires no local installation. See the Microsoft repo for details.

### Setup in Devin

1. Navigate to **Settings > MCP Marketplace** in the Devin UI
2. Click **"Add Your Own"** at the top
3. Fill in:
   - **Server Name:** `Azure DevOps`
   - **Short Description:** `Query and manage Azure DevOps work items, boards, repos, and pipelines`
   - **Transport:** `STDIO`
4. Configure the STDIO fields:
   - **Command:** `npx`
   - **Arguments:** `-y @azure-devops/mcp YourOrgName`
   - **Environment Variables:**
     | Key | Value |
     |---|---|
     | `AZURE_DEVOPS_ORG_URL` | `https://dev.azure.com/YourOrg` |
     | `AZURE_DEVOPS_AUTH_TYPE` | `pat` |
     | `AZURE_DEVOPS_PAT` | Your Azure DevOps Personal Access Token |
5. Click **Save**, then **Test listing tools** to verify the connection

### Available Tools

Once connected, Devin can use tools like:

| Tool | Description |
|---|---|
| `get_work_item` | Fetch a work item by ID |
| `list_work_items` | Query work items with WIQL |
| `create_work_item` | Create a new work item |
| `update_work_item` | Update fields on a work item |
| `list_projects` | List all projects in the org |
| `get_pipeline` | Get pipeline details |
| `list_pipelines` | List pipelines in a project |

The exact tool list depends on the MCP server version. Click **Test listing tools** in the Devin UI to see the full set.

## Creating the PAT

The MCP server authenticates to Azure DevOps using a Personal Access Token. Create one with minimal scopes:

1. Go to `https://dev.azure.com/{YourOrg}/_usersSettings/tokens`
2. Click **New Token**
3. Set the following scopes based on what you need:

| Scope | When Needed |
|---|---|
| **Work Items** (Read) | Querying work items and boards |
| **Work Items** (Read & Write) | Creating/updating work items |
| **Project and Team** (Read) | Listing projects |
| **Build** (Read) | Querying pipelines and builds |
| **Code** (Read) | Browsing repo contents |

4. Copy the token and use it as the `AZURE_DEVOPS_PAT` environment variable

## Usage in a Devin Session

Once the MCP server is set up, Devin can use it in any session. Examples:

> "Look up work item #42 in the DevinIntegration project and summarize what needs to be done"

> "Query all work items tagged 'Devin:Discovery' in MyProject that are in the 'New' state"

> "List all pipelines in the Platform project and check if any failed in the last 24 hours"

## Security Considerations

- **Use a dedicated service account** for the PAT rather than a personal account
- **Scope the PAT** to the minimum permissions needed (read-only where possible)
- **Store the PAT as a Devin secret** — never hardcode it in configuration

## Reference

- [Devin MCP Documentation](https://docs.devin.ai/work-with-devin/mcp)
- [Azure DevOps REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [`@azure-devops/mcp` (Microsoft)](https://github.com/microsoft/azure-devops-mcp)
