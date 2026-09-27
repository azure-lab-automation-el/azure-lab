# SCOM live configuration export (ESTHER-MG)
Unsealed management packs exported from the live management group with `esther-linux-sweden` stage `scom-inventory`
(scripts/scom/inventory.ps1, SHA256-verified transfer). Re-import with `Import-SCOMManagementPack` after a rebuild.
`inventory.txt` = the live inventory at export time. SecureReferenceOverride holds Run As account *associations* only (no passwords;
the Run As credentials live in repo secrets / the vault and must be recreated first).
