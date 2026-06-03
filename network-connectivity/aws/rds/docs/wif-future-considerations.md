# WIF / IAM Role Future Considerations

> How IAM role assumption or OIDC federation could enable credential-less authentication if the Devin platform adds per-session identity.

## Current State

AWS [IAM Roles Anywhere](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html) and [Web Identity Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html) are the gold standard for cross-environment authentication — they eliminate stored access keys entirely by exchanging an external identity for short-lived AWS credentials.

**IAM role assumption is not viable for Devin today** because Devin sessions have no external identity to federate:

| Identity Source | Devin Status | Why |
|---|---|---|
| AWS IAM Role / Instance Profile | Not available | Devin VMs are Firecracker microVMs with no IAM role or instance metadata service |
| OIDC Token | Not available | Devin platform does not issue per-session OIDC tokens |
| X.509 Certificate (Roles Anywhere) | Not available | No per-session certificate is provisioned |
| SAML Assertion | Not available | No SAML IdP issues assertions for Devin sessions |

## What Would Make IAM Role Assumption Viable

### Option 1: Per-Session OIDC Identity (Recommended)

If the Devin platform operated an OIDC-compliant identity provider and issued a signed JWT to each session, `AssumeRoleWithWebIdentity` would work:

```
Devin Session                        AWS
────────────                         ───
1. Session starts with a signed
   JWT from Cognition OIDC IdP
   (claims: org_id, session_id, etc.)

2. aws sts assume-role-with    ───► AWS STS
   -web-identity sends JWT           validates against OIDC provider config
                                     (trusts Cognition OIDC issuer)

3. Receives temporary AWS      ◄─── issues short-lived credentials
   credentials (access key,          bound to the target IAM role
   secret key, session token)

4. aws rds generate-db-auth-token
   uses temporary credentials  ────► RDS (IAM DB auth)
```

**Customer setup would be:**

```bash
# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url "https://auth.devin.ai" \
  --client-id-list "CUSTOMER_ACCOUNT_ID" \
  --thumbprint-list "OIDC_THUMBPRINT"

# Create IAM role with web identity trust
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/auth.devin.ai"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "auth.devin.ai:sub": "DEVIN_ORG_ID"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name devin-rds-role \
  --assume-role-policy-document file://trust-policy.json

# Attach RDS permissions
aws iam attach-role-policy \
  --role-name devin-rds-role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/DevinRDSAccess
```

**Devin blueprint would be:**

```yaml
maintenance: |
  # OIDC token automatically available as $DEVIN_OIDC_TOKEN or via a file
  aws sts assume-role-with-web-identity \
    --role-arn arn:aws:iam::ACCOUNT_ID:role/devin-rds-role \
    --role-session-name devin-session \
    --web-identity-token "$DEVIN_OIDC_TOKEN" \
    > /dev/shm/aws-credentials.json
  export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' /dev/shm/aws-credentials.json)
  export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' /dev/shm/aws-credentials.json)
  export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' /dev/shm/aws-credentials.json)
```

### Option 2: IAM Roles Anywhere (X.509 Certificates)

If the Devin platform provisioned per-session X.509 certificates, [IAM Roles Anywhere](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html) could exchange them for short-lived credentials without any OIDC infrastructure.

### Option 3: AWS IAM Identity for Devin VMs

If Devin VMs gained an AWS IAM role (even a shared one per org), the standard instance profile flow would work without any Devin platform changes. However, this is architecturally harder given the Firecracker isolation model — the microVMs intentionally lack access to the EC2 metadata service.

## Benefits of IAM Role Assumption (When Available)

| Benefit | Detail |
|---|---|
| **No stored AWS credentials** | No access key to generate, store, rotate, or leak |
| **Short-lived credentials** | STS session tokens expire in 1–12 hours; auto-refreshable |
| **Fine-grained attribution** | CloudTrail shows the Devin org ID / session ID via role session name, not just an access key ID |
| **Simpler onboarding** | Customer creates an OIDC provider once; adding new permissions is a policy update, not a new key |
| **Better for compliance** | No credential lifecycle management; tokens are ephemeral |

## Cross-Cloud Applicability

The same OIDC identity would also enable:
- **GCP Workload Identity Federation** — exchange JWT for short-lived GCP access tokens (see the [GCP Cloud SQL WIF analysis](../../../gcp/cloud-sql/docs/wif-future-considerations.md))
- **Azure Federated Credentials** — authenticate to Azure AD as a federated workload identity
- **Any OIDC Relying Party** — HashiCorp Vault, Kubernetes, etc.
- **Customer-operated OIDC-aware proxies** — verify Devin session identity at the network edge

## Recommendation

If the Devin platform team evaluates adding per-session identity, OIDC is the most portable standard. A single OIDC issuer would unlock credential-less authentication across AWS, GCP, Azure, and any OIDC-compatible system.

Until then, use [Option A (Customer-Hosted Proxy)](option-a-customer-hosted-proxy.md) for production or [Option B (IAM Credentials)](option-b-iam-credentials-on-devin.md) for POC.
