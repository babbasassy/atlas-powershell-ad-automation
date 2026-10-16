[CmdletBinding()]
param([string]$ReportPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$scripts=Join-Path $root 'scripts'
$fixtures=Join-Path $root 'fixtures'
$temp=Join-Path $PSScriptRoot ('.run-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$results=[Collections.Generic.List[object]]::new()
function Assert-True($Condition,$Message) { if(-not $Condition){throw $Message} }
function Expect-Throw([scriptblock]$Body,[string]$Pattern) {
    try { & $Body | Out-Null } catch { if($_.Exception.Message -match $Pattern){return}; throw }
    throw "Expected exception matching $Pattern"
}
function Case([string]$Name,[scriptblock]$Body) {
    try { & $Body | Out-Null; $results.Add([pscustomobject]@{Name=$Name;Passed=$true}) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message}) }
}
function Csv([string]$Name,[string]$Text) { $path=Join-Path $temp $Name; [IO.File]::WriteAllText($path,$Text); return $path }

Case 'all scripts parse' {
    foreach($file in Get-ChildItem $scripts -Filter '*.ps1') {
        $tokens=$null; $errors=$null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) "$($file.Name) failed parsing"
    }
}
Case 'valid users CSV' { $r=& "$scripts/Test-LabCsv.ps1" -Path "$fixtures/users.csv"; Assert-True ($r.Valid -and $r.Rows -eq 3) 'Expected three users' }
Case 'valid groups CSV' { $r=& "$scripts/Test-LabCsv.ps1" -Kind Groups -Path "$fixtures/groups.csv"; Assert-True ($r.Rows -eq 2) 'Expected two groups' }
Case 'missing columns rejected' { $p=Csv missing.csv "SamAccountName,GivenName`nlab-auto-a,Ada"; Expect-Throw { & "$scripts/Test-LabCsv.ps1" -Path $p } 'Expected columns' }
Case 'secret column rejected' { $p=Csv extra.csv "SamAccountName,GivenName,Surname,Password`nlab-auto-a,Ada,Example,not-a-secret"; Expect-Throw { & "$scripts/Test-LabCsv.ps1" -Path $p } 'Expected columns' }
Case 'duplicate names rejected' { $p=Csv duplicate.csv "SamAccountName,GivenName,Surname`nlab-auto-a,Ada,Example`nlab-auto-a,Lin,Example"; Expect-Throw { & "$scripts/Test-LabCsv.ps1" -Path $p } 'Duplicate' }
Case 'LDAP injection name rejected' { $p=Csv injection.csv "SamAccountName,GivenName,Surname`nlab-auto-*)(uid=*),Ada,Example"; Expect-Throw { & "$scripts/Test-LabCsv.ps1" -Path $p } 'Invalid lab name' }
Case 'blank field rejected' { $p=Csv blank.csv "SamAccountName,GivenName,Surname`nlab-auto-a,,Example"; Expect-Throw { & "$scripts/Test-LabCsv.ps1" -Path $p } 'Blank' }
Case 'empty CSV rejected' { $p=Csv empty.csv 'SamAccountName,GivenName,Surname'; Expect-Throw { & "$scripts/Test-LabCsv.ps1" -Path $p } 'at least one' }
Case 'default user operation is offline plan' { $r=@(& "$scripts/New-LabUsers.ps1" -Path "$fixtures/users.csv"); Assert-True ($r.Count -eq 3 -and $r[0].Action -eq 'PlanCreateDisabledUser') 'Unexpected plan' }
Case 'default group operation is offline plan' { $r=@(& "$scripts/New-LabGroups.ps1" -Path "$fixtures/groups.csv"); Assert-True ($r.Count -eq 2 -and $r[0].Action -eq 'PlanCreateEmptyGroup') 'Unexpected plan' }
Case 'nonlab server rejected before connection' { Expect-Throw { & "$scripts/New-LabUsers.ps1" -Path "$fixtures/users.csv" -Server 'production.example.com' -Execute } 'Only DC01' }
Case 'outside OU rejected before connection' { Expect-Throw { & "$scripts/New-LabGroups.ps1" -Path "$fixtures/groups.csv" -SearchBase 'CN=Users,DC=corp,DC=atlas,DC=test' -Execute } 'dedicated' }
Case 'inactive boundary, never-logon, recent and disabled policy' {
    $r=@(& "$scripts/Get-InactiveLabUsers.ps1" -FixturePath "$fixtures/inactivity.csv" -AsOfUtc '2026-10-16T00:00:00Z' -Days 90)
    Assert-True (($r.SamAccountName -join ',') -eq 'lab-auto-old,lab-auto-edge,lab-auto-never') 'Wrong inactive selection'
    Assert-True ($r[2].Reason -eq 'NeverLoggedOnAndOld') 'Wrong never-logon reason'
}
Case 'future timestamp rejected' { $p=Csv future.csv "SamAccountName,Enabled,CreatedUtc,LastLogonUtc`nlab-auto-a,True,2026-01-01T00:00:00Z,2099-01-01T00:00:00Z"; Expect-Throw { & "$scripts/Get-InactiveLabUsers.ps1" -FixturePath $p -AsOfUtc '2026-10-16T00:00:00Z' } 'Inconsistent' }
Case 'timestamp without zone rejected' { $p=Csv zone.csv "SamAccountName,Enabled,CreatedUtc,LastLogonUtc`nlab-auto-a,True,2026-01-01T00:00:00,"; Expect-Throw { & "$scripts/Get-InactiveLabUsers.ps1" -FixturePath $p } 'UTC offset' }
Case 'direct membership and empty group preserved' {
    $out=Join-Path $temp 'members.csv'
    & "$scripts/Export-LabGroupMembers.ps1" -FixturePath "$fixtures/membership.csv" -OutputPath $out | Out-Null
    $r=@(Import-Csv $out)
    Assert-True ($r.Count -eq 4 -and $r[2].ObjectClass -eq 'group' -and $r[3].ObjectClass -eq 'EmptyGroup') 'Unexpected membership expansion'
    Expect-Throw { & "$scripts/Export-LabGroupMembers.ps1" -FixturePath "$fixtures/membership.csv" -OutputPath $out } 'already exists'
}
Case 'spreadsheet formula escaped' {
    $p=Csv formula.csv "Group,Member,ObjectClass`nlab-auto-a,=1+1,user"
    $out=Join-Path $temp 'safe.csv'
    & "$scripts/Export-LabGroupMembers.ps1" -FixturePath $p -OutputPath $out | Out-Null
    Assert-True ((Import-Csv $out).Member -eq "'=1+1") 'Unsafe spreadsheet cell'
}

# Command doubles below are process-local contract tests, not an AD server.
function Import-Module { [CmdletBinding()]param($Name) if($Name -ne 'ActiveDirectory'){throw 'Unexpected module'} }
function Get-ADDomain { [CmdletBinding()]param($Server) [pscustomobject]@{DNSRoot='corp.atlas.test'} }
function Get-ADOrganizationalUnit { [CmdletBinding()]param($Identity,$Server) [pscustomobject]@{DistinguishedName=$Identity} }
$global:AtlasTestCollision=$false; $global:AtlasTestDenyRead=$false
$global:AtlasTestWrites=[Collections.Generic.List[object]]::new()
function Get-ADObject { [CmdletBinding()]param($LDAPFilter,$Server,$SearchBase) if($global:AtlasTestDenyRead){throw 'MockAccessDenied'}; if($global:AtlasTestCollision){[pscustomobject]@{Name='collision'}} }
function New-ADUser {
    [CmdletBinding()]param($Name,$SamAccountName,$GivenName,$Surname,$UserPrincipalName,$Path,$Server,[bool]$Enabled,$Description,[switch]$PassThru)
    $global:AtlasTestWrites.Add([pscustomobject]@{Type='User';Enabled=$Enabled;Path=$Path})
    [pscustomobject]@{SamAccountName=$SamAccountName;ObjectGUID=[guid]::Empty}
}
function New-ADGroup {
    [CmdletBinding()]param($Name,$SamAccountName,$GroupCategory,$GroupScope,$Description,$Path,$Server,[switch]$PassThru)
    $global:AtlasTestWrites.Add([pscustomobject]@{Type='Group';Category=$GroupCategory;Scope=$GroupScope;Path=$Path})
    [pscustomobject]@{Name=$Name;ObjectGUID=[guid]::Empty}
}
Case 'mock: WhatIf performs no writes' {
    $global:AtlasTestWrites.Clear()
    & "$scripts/New-LabUsers.ps1" -Path "$fixtures/users.csv" -Execute -WhatIf | Out-Null
    & "$scripts/New-LabGroups.ps1" -Path "$fixtures/groups.csv" -Execute -WhatIf | Out-Null
    Assert-True ($global:AtlasTestWrites.Count -eq 0) 'WhatIf wrote to adapter'
}
Case 'mock: created users disabled, empty groups global/security' {
    & "$scripts/New-LabUsers.ps1" -Path "$fixtures/users.csv" -Execute -Confirm:$false | Out-Null
    & "$scripts/New-LabGroups.ps1" -Path "$fixtures/groups.csv" -Execute -Confirm:$false | Out-Null
    Assert-True ($global:AtlasTestWrites.Count -eq 5) 'Wrong write count'
    Assert-True (@($global:AtlasTestWrites | Where-Object {$_.Type -eq 'User' -and $_.Enabled}).Count -eq 0) 'User was enabled'
    Assert-True ($global:AtlasTestWrites[3].Category -eq 'Security' -and $global:AtlasTestWrites[3].Scope -eq 'Global') 'Unexpected group type'
}
Case 'mock: collision aborts entire batch' {
    $global:AtlasTestWrites.Clear(); $global:AtlasTestCollision=$true
    try { Expect-Throw { & "$scripts/New-LabUsers.ps1" -Path "$fixtures/users.csv" -Execute -Confirm:$false } 'Collision'; Assert-True ($global:AtlasTestWrites.Count -eq 0) 'Collision led to write' } finally {$global:AtlasTestCollision=$false}
}
Case 'mock: read access failure does not mean object absent' {
    $global:AtlasTestDenyRead=$true
    try { Expect-Throw { & "$scripts/New-LabGroups.ps1" -Path "$fixtures/groups.csv" -Execute -Confirm:$false } 'MockAccessDenied'; Assert-True ($global:AtlasTestWrites.Count -eq 0) 'Read failure led to write' } finally {$global:AtlasTestDenyRead=$false}
}
$failed=@($results | Where-Object {-not $_.Passed})
$report=[ordered]@{GeneratedAtUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Mode='Local fixtures and process-local command doubles; no live AD';Passed=$results.Count-$failed.Count;Failed=$failed.Count;Tests=@($results.ToArray())}
if($ReportPath){ $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
$report | ConvertTo-Json -Depth 8
if($failed.Count){exit 1}
