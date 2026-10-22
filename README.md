# ATLAS PowerShell AD Automation

**Scope: a local synthetic lab, with no separate VM required.** The deliverable is actual PowerShell execution against fixture data and simulated directory operations. All 22 local tests passed again on 17 October 2026; see the [dated test report](evidence/local-tests-20261017.json). Live AD verification is an optional future extension and is not implied by these results.

Five administration scripts for a dedicated Active Directory test OU: validate input, plan or create disabled test users, plan or create empty groups, identify inactive accounts, and export direct group membership.

**Current evidence: local execution only.** The fixture and command-double tests pass on PowerShell 7.6.5. No script has been executed against a real domain controller during this project. The existing ATLAS VMware lab was found, but no VMs were running and the host has no ActiveDirectory module. Live AD verification remains open.

This extends the [existing Windows Enterprise Lab](https://github.com/babbasassy/atlas-windows-enterprise-lab) with complete-batch CSV validation, constrained scope, explicit execution mode, collision checks, `ShouldProcess`, inactive-account classification and regression tests. Existing screenshots are not reused as evidence for these new scripts.

| Script | Default behavior | Live behavior when explicitly selected |
|---|---|---|
| `Test-LabCsv.ps1` | Validate users/groups CSV locally | No AD access |
| `New-LabUsers.ps1` | Produce an offline creation plan | Create disabled users without passwords or group assignments |
| `New-LabGroups.ps1` | Produce an offline creation plan | Create empty Global/Security groups; no ACL changes |
| `Get-InactiveLabUsers.ps1` | Classify a supplied synthetic fixture | Read users directly inside the test OU; never disable them |
| `Export-LabGroupMembers.ps1` | Export supplied synthetic membership | Read direct membership and preserve empty groups; no permission calculation |

`Lab.Common.ps1` is a shared helper, not a sixth administrative task.

## Run the local demonstration

From the repository directory, in a fresh PowerShell process:

```powershell
./scripts/Test-LabCsv.ps1 -Path ./fixtures/users.csv
./scripts/New-LabUsers.ps1 -Path ./fixtures/users.csv
./scripts/New-LabGroups.ps1 -Path ./fixtures/groups.csv
./scripts/Get-InactiveLabUsers.ps1 -FixturePath ./fixtures/inactivity.csv -Days 90 -AsOfUtc '2026-10-16T00:00:00Z'
New-Item -ItemType Directory -Path ./reports -Force
./scripts/Export-LabGroupMembers.ps1 -FixturePath ./fixtures/membership.csv -OutputPath ./reports/members.csv
pwsh -NoProfile -File ./tests/Run-Tests.ps1 -ReportPath ./evidence/local-tests.json
```

The test harness defines process-local AD command doubles; run it in a fresh process as shown, not dot-sourced into an administration session. Its report explicitly says no live AD was used. Local report export is actual file processing; fixture accounts and directory responses are simulated.

## Execution controls

- The default creation mode does not connect to AD. `-Execute` is required for directory operations; `-Execute -WhatIf` reads AD for preflight but suppresses writes.
- Only `DC01.corp.atlas.test` and `OU=AutomationLab,OU=ATLAS,DC=corp,DC=atlas,DC=test` are accepted. The server's domain and target OU are checked before operations. Name checks are guardrails, not a security boundary against a malicious administrator.
- Input names must use `lab-auto-` plus 1–11 lowercase letters/digits. All CSV rows are validated before writes; unsupported columns, duplicates, blank fields and unsafe names fail.
- Domain-wide name collisions abort preflight. Authorization/read failures propagate instead of being interpreted as missing objects.
- User creation deliberately leaves accounts disabled and does not accept passwords. Empty groups receive no members or resource permissions.
- Writes request confirmation through `ShouldProcess`. A runtime failure can leave earlier successful objects in place; there is no transaction, automatic rollback or auto-delete.
- Reports refuse to overwrite files and escape spreadsheet formula prefixes. Keep real directory exports private.

See [optional live verification procedure](docs/LIVE-VERIFICATION.md), [design and limits](docs/DESIGN.md), and the generated [local test report](evidence/local-tests.json). Live AD acceptance criteria remain unverified; they are separate from the completed local simulation tests.
