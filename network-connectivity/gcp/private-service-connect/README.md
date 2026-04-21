# GCP Private Service Connect

> Planned — not yet implemented.

Private IP connectivity to Google APIs and your own services without exposing traffic to the public internet.

## When to Use

- Devin needs to access a **Google managed service** (Cloud SQL, GCS, etc.) over a private IP
- You want to consume a third-party service published via Private Service Connect
- You need to keep all traffic on Google's network backbone

## Planned Components

- Terraform module for Private Service Connect endpoints
- VPC and DNS configuration
- Devin environment integration

## Reference

- [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect)
- [Accessing Google APIs through PSC](https://cloud.google.com/vpc/docs/configure-private-service-connect-apis)
