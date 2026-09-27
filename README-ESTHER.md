# Esther Cloud Admin (v0.2)

Cloud-only, Adaxes-style user management for the Esther Hospital lab tenant. No DC, no Adaxes, no Graph secrets in the portal.

Live: https://agreeable-smoke-09274440f.5.azurestaticapps.net (Azure Static Web Apps, Free, rg-esther-portal, eastus2)

## How it works
- Sign-in: SWA built-in Microsoft sign-in. Access = config/portal-roles.json (approvers, admins).
- Reads: api/inventory.json, a snapshot exported by esther-apply right after each readback, bundled at deploy.
- Actions: create user, edit title/department, change manager, add/remove group, disable/enable. Password reset is shown but not enabled yet.
- Every action becomes a change-request PR (requests/<id>.json).
  - standard (config/approval-policy.json) or filed by an approver: merged at once.
  - special by another admin: waits in Requests; an approver who is not the requester approves (merge) or rejects (close).
- Merge to main -> esther-apply (write app via OIDC, main only): fold requests -> plan -> guard -> apply -> readback (retries) -> new inventory -> fold commit -> esther-swa-deploy.
- Guard: a staged plan must match desired-state/reviewed-plan.json exactly; request runs may only touch users named in the requests. Otherwise apply refuses.
- Audit: PRs, audit/requests/, workflow artifacts (plan, apply-log, readback).

## Identities
- esther-graph-read (User/Group.Read.All), OIDC on pull_request: esther-plan.
- esther-graph-write (User/Group.ReadWrite.All), OIDC on main: esther-apply.
- azure-lab-automation: RG work + Cost Management Reader (subscription), OIDC on main: esther-costs-read.
- API request token (secret ESTHER_REQUEST_TOKEN): fine-grained, this repo only, contents + pull requests. Not set = preview mode.
