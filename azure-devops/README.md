# Azure DevOps Integration for Devin

Webhook receivers and pipeline templates for integrating Devin with Azure DevOps.

## Planned Components

| Component | Description | Status |
|---|---|---|
| `webhook-receiver/` | HTTP endpoint that receives Azure DevOps service hook events and triggers Devin sessions | Planned |
| `pipeline-templates/` | Reusable Azure Pipelines YAML templates for invoking Devin | Planned |

## Use Cases

- Trigger a Devin session when a work item transitions (e.g., "Ready for Development")
- Kick off Devin-powered code review when a pull request is created
- Run Devin for automated release notes generation on pipeline completion

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [Azure DevOps Service Hooks](https://learn.microsoft.com/en-us/azure/devops/service-hooks/overview)
- [Azure Pipelines YAML schema](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema)
