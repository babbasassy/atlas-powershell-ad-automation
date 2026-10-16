[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param([Parameter(Mandatory)][string]$Path,
      [string]$Server='DC01.corp.atlas.test',
      [string]$SearchBase='OU=AutomationLab,OU=ATLAS,DC=corp,DC=atlas,DC=test',
      [switch]$Execute)
. "$PSScriptRoot/Lab.Common.ps1"
Assert-LabScope $Server $SearchBase
$rows = @(Read-LabCsv $Path Users)
if (-not $Execute) {
    foreach ($row in $rows) { [pscustomobject]@{Action='PlanCreateDisabledUser';SamAccountName=$row.SamAccountName;Path=$SearchBase;EvidenceMode='Offline plan; no AD connection'} }
    return
}
Connect-LabDirectory $Server $SearchBase
# Fail before the first write if any name already exists anywhere in the domain.
foreach ($row in $rows) {
    $sam = $row.SamAccountName
    $existing = @(Get-ADObject -LDAPFilter "(sAMAccountName=$sam)" -Server $Server -SearchBase 'DC=corp,DC=atlas,DC=test' -ErrorAction Stop)
    if ($existing.Count) { throw "Collision: $sam. No users were created by this invocation." }
}
foreach ($row in $rows) {
    if ($PSCmdlet.ShouldProcess("$($row.SamAccountName) in $SearchBase",'Create disabled lab user')) {
        $created = New-ADUser -Name $row.SamAccountName -SamAccountName $row.SamAccountName -GivenName $row.GivenName -Surname $row.Surname -UserPrincipalName "$($row.SamAccountName)@corp.atlas.test" -Path $SearchBase -Server $Server -Enabled $false -Description 'ATLAS-Automation disposable lab user' -PassThru -ErrorAction Stop
        [pscustomobject]@{Action='CreatedDisabledUser';SamAccountName=$created.SamAccountName;ObjectGuid=[string]$created.ObjectGUID;EvidenceMode='Live AD command result'}
    }
}
