# AWS PrivateLink

> Planned — not yet implemented.

Private connectivity to AWS services or your own services via VPC endpoints, without exposing traffic to the public internet.

## When to Use

- Devin needs to access a **managed AWS service** (RDS, ElastiCache, S3, etc.) over a private IP
- You want to expose an internal service to Devin without VPC peering
- You need service-to-service connectivity with no internet transit

## Planned Components

- CloudFormation template for Interface VPC Endpoints
- Network Load Balancer configuration for custom services
- Security group and IAM policy configuration
- Devin environment integration

## Reference

- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
- [VPC Endpoint Services](https://docs.aws.amazon.com/vpc/latest/privatelink/endpoint-service-overview.html)
