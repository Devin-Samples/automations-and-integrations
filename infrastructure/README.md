# Infrastructure as Code

Deployable infrastructure templates for hosting Devin integration services (webhook receivers, API gateways, etc.).

## Directories

| Directory | Description | Status |
|---|---|---|
| `terraform/` | Terraform modules for deploying webhook receivers and supporting infrastructure | Planned |
| `cloudformation/` | AWS CloudFormation templates for serverless webhook endpoints (Lambda + API Gateway) | Planned |

## Planned Resources

- **Webhook receiver** — Serverless function (Lambda / Azure Function / Cloud Run) to receive CI/CD events and call the Devin API
- **API Gateway** — Managed HTTP endpoint with authentication and rate limiting
- **Secrets management** — Secure storage for Devin API keys (AWS Secrets Manager, Azure Key Vault, etc.)
- **Logging and monitoring** — CloudWatch / Azure Monitor integration for observability

## Reference

- [Terraform documentation](https://developer.hashicorp.com/terraform/docs)
- [AWS CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
- [Devin API documentation](https://docs.devin.ai/api-reference/overview)
