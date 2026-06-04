# WIF / Federated Identity Future Considerations

> How Azure Federated Identity Credentials could enable credential-less authentication if the Devin platform adds per-session identity.

## Current State

Azure [Federated Identity Credentials](https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation) (also known as Workload Identity Federation) is the gold standard for cross-cloud and external-to-Azure authentication -- it eliminates stored credentials entirely by exchanging an external OIDC token for short-lived Azure AD tokens.

**Federated Identity is not viable for Devin today** because Devin sessions have no external identity to federate:

| Federation Identity Source | Devin Status | Why |
|---|---|---|
| Azure Managed Identity | Not available | Devin VMs are Firecracker microVMs with no Azure IMDS |
| OIDC Token | Not available | Devin platform does not issue per-session OIDC tokens |
| AWS IAM Role | Not available | Devin VMs have no AWS IAM role or instance metadata |
| GitHub Actions Token | Not available | Devin sessions are not GitHub Actions runners |

## What Would Make Federated Identity Viable

### Option 1: Per-Session OIDC Identity (Recommended)

If the Devin platform operated an OIDC-compliant identity provider and issued a signed JWT to each session, Azure Federated Identity Credentials would work:

```
Devin Session                        Azure AD (Entra ID)
------------                         -------------------
1. Session starts with a signed
   JWT from Cognition OIDC IdP
   (claims: org_id, session_id, etc.)

2. Application code sends        --> Azure AD token endpoint
   JWT as client assertion             validates against
                                       Federated Credential config
                                       (trusts Cognition OIDC issuer)

3. Receives Azure AD              <-- issues short-lived AAD token
   access token                        bound to the service principal

4. Uses AAD token to connect      --> Azure SQL Database
   (token-based auth)
```

**Customer setup would be:**

```bash
# Create app registration (if not already done)
az ad app create --display-name "devin-db-sp"

# Add federated credential trusting Cognition's OIDC issuer
az ad app federated-credential create \
  --id APP_ID \
  --parameters '{
    "name": "devin-session-identity",
    "issuer": "https://auth.devin.ai",
    "subject": "org:DEVIN_ORG_ID",
    "audiences": ["api://AzureADTokenExchange"],
    "description": "Trust Devin session OIDC tokens for this org"
  }'
```

**Devin blueprint would be:**

```yaml
maintenance: |
  # OIDC token automatically available as $DEVIN_OIDC_TOKEN or via a file
  # Exchange OIDC token for Azure AD access token
  AZURE_TOKEN=$(curl -s -X POST \
    "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
    -d "client_id=$AZURE_CLIENT_ID" \
    -d "scope=https://database.windows.net/.default" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=$DEVIN_OIDC_TOKEN" \
    -d "grant_type=client_credentials" \
    | jq -r '.access_token')
  printf '%s\n' "$AZURE_TOKEN" > /dev/shm/azure-sql-token
  chmod 600 /dev/shm/azure-sql-token
```

### Option 2: AWS IAM Identity for Devin VMs

If Devin VMs gained an AWS IAM role (even a shared one per org), the standard federation-via-AWS flow would work:
1. Devin session assumes the AWS IAM role
2. STS call to Azure AD exchanges the AWS token for an AAD token via federated credential
3. AAD token used for Azure SQL auth

However, this is architecturally harder given the Firecracker isolation model.

## Benefits of Federated Identity (When Available)

| Benefit | Detail |
|---|---|
| **No stored Azure credentials** | No client secret to generate, store, rotate, or leak |
| **Short-lived tokens** | AAD access tokens expire in ~1 hour; auto-refreshed |
| **Fine-grained attribution** | Azure AD sign-in logs show the Devin org ID / session ID |
| **Simpler onboarding** | Customer creates a federated credential once; no secrets to exchange |
| **Better for compliance** | No credential lifecycle management; tokens are ephemeral |

## Cross-Cloud Applicability

The same OIDC identity would also enable:
- **GCP Workload Identity Federation** -- authenticate to GCP as a federated workload identity (see [GCP WIF analysis](../../gcp/cloud-sql/docs/wif-future-considerations.md))
- **AWS `AssumeRoleWithWebIdentity`** -- federate into AWS IAM roles
- **HashiCorp Vault** -- authenticate via OIDC auth method
- **Any OIDC Relying Party** -- customer-operated proxies can verify Devin session identity at the network edge

## Recommendation

If the Devin platform team evaluates adding per-session identity, OIDC is the most portable standard. A single OIDC issuer would unlock credential-less authentication across Azure, GCP, AWS, and any OIDC-compatible system.

Until then, use [Option A (Customer-Hosted Private Endpoint)](option-a-customer-hosted-endpoint.md) for production or [Option B (Service Principal)](option-b-service-principal-on-devin.md) for POC.
