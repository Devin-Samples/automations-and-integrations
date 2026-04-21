# Jenkins Integration for Devin

> Planned — not yet implemented.

Pipeline steps and webhook-based triggers for invoking Devin from Jenkins.

## Planned Components

| Component | Description | Status |
|---|---|---|
| `pipeline-plugin/` | Shared library or pipeline step for calling the Devin API from Jenkinsfiles | Planned |

## Use Cases

- Add a `devinSession()` step to Jenkins pipelines to trigger Devin for code review or testing
- Trigger Devin sessions from Jenkins webhook notifications
- Post-build actions that send results to Devin for analysis

## Reference

- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
- [Jenkins Shared Libraries](https://www.jenkins.io/doc/book/pipeline/shared-libraries/)
