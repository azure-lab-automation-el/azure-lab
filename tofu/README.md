# tofu/ - portable lab layer (multi-cloud)

One target config file = one deployment target. The existing bash/azure-cli engine
(stays the Azure fast path) keeps doing post-config (DC promo, domain join, SQL/SSRS/SCOM);
this layer provisions network + VMs + media cache on any cloud.

## Layout
- `modules/azure-lab` - reference module, mirrors the live lab 1:1 (hub VNet 10.77, spoke 10.78,
  DC B2ats_v2, Esther B2as_v2 64GB Premium, Ubuntu B2ats_v2, media storage account)
- `modules/aws-lab`   - same lab on EC2/VPC/S3 (PLAN-ONLY until spend is approved)
- `modules/gcp-lab`   - same lab on GCE/VPC/GCS (PLAN-ONLY until spend is approved)
- `stacks/<cloud>`    - root module per cloud; `targets/*.tfvars.example` = one file per target

## Rules
- No subscription/tenant/project/account IDs, passwords or keys in this tree - providers read
  credentials from env/OIDC at apply time. State never enters git (see .gitignore).
- AWS/GCP are plan-only: `tofu init -backend=false && tofu validate` (+ plan with placeholders).
  Nothing applies without his explicit approval and a cost number first.
- Azure apply is NOT wired into CI yet; the approved path today is still the bash engine.

## Validate
    cd tofu/stacks/azure && tofu init -backend=false && tofu validate
