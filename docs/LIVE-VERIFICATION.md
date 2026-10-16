# Pending live AD verification

**This checklist has not been executed.** The existing lab README identifies DC01 in `corp.atlas.test`. Read-only host checks found the ATLAS-DC01 VMware configuration and no running VMware VMs. The host is not domain joined, and the ActiveDirectory module was not available in the current PowerShell session. Do not install AD DS or change host security settings to make these scripts run.

## Preconditions

1. Start and sign in to the existing isolated ATLAS domain controller through an authorized lab session. Do not send passwords through chat or put them in files/command lines.
2. Confirm the live server identity, domain, disposable scope, evaluation-license validity and an appropriate recovery point before writes. Record the actual PowerShell and ActiveDirectory module versions.
3. Create or confirm a dedicated empty `AutomationLab` OU directly under the existing `ATLAS` OU with explicit lab authorization. This package does not create the OU automatically or touch department OUs.
4. Copy the reviewed scripts and synthetic fixtures into the VM through an approved transfer path. Run the local tests in a separate process first. Never reuse the mock-test process for live administration.

## Planned acceptance checks

- Default user/group commands produce plans and create zero objects.
- `-Execute -WhatIf` completes the real domain/OU/collision preflight and creates zero objects.
- A valid user batch creates exactly three disabled `lab-auto-00x` accounts. Verify the real object GUIDs, location, disabled state and lack of new group grants.
- The group batch creates exactly two empty global security groups. Verify scope, category and direct member count.
- Repeating either creation batch fails on collision without additional objects.
- An invalid row fails before any creation; use only local input mutation, not changes to existing users.
- Run both live reports. Newly created disabled users should not appear as inactive candidates; fixture tests separately cover stale-account cases. The empty groups should appear explicitly in the direct-membership report.
- Capture sanitized actual outputs, then remove only the exact objects created by this exercise after checking their GUIDs, description and OU. Remove the test OU only if this exercise created it and it is empty. Preserve existing ATLAS users, groups and other VMs.

Publish live results only after these checks actually succeed. If authentication, module loading, OU access or cleanup is blocked, retain the local test evidence and mark live criteria pending.
