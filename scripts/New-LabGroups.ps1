[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param([Parameter(Mandatory)][string]$Path,
      [string]$Server='DC01.corp.atlas.test',
      [string]$SearchBase='OU=AutomationLab,OU=ATLAS,DC=corp,DC=atlas,DC=test',
      [switch]$Execute)
. "$PSScriptRoot/Lab.Common.ps1"
Assert-LabScope $Server $SearchBase
$rows = @(Read-LabCsv $Path Groups)
if (-not $Execute) {
    foreach ($row in $rows) { [pscustomobject]@{Action='PlanCreateEmptyGroup';Name=$row.Name;Path=$SearchBase;EvidenceMode='Offline plan; no AD connection'} }
    return
}
Connect-LabDirectory $Server $SearchBase
foreach ($row in $rows) {
    $name = $row.Name
    $existing = @(Get-ADObject -LDAPFilter "(sAMAccountName=$name)" -Server $Server -SearchBase 'DC=corp,DC=atlas,DC=test' -ErrorAction Stop)
    if ($existing.Count) { throw "Collision: $name. No groups were created by this invocation." }
}
foreach ($row in $rows) {
    if ($PSCmdlet.ShouldProcess("$($row.Name) in $SearchBase",'Create empty lab security group')) {
        $created = New-ADGroup -Name $row.Name -SamAccountName $row.Name -GroupCategory Security -GroupScope Global -Description $row.Description -Path $SearchBase -Server $Server -PassThru -ErrorAction Stop
        [pscustomobject]@{Action='CreatedEmptyGroup';Name=$created.Name;ObjectGuid=[string]$created.ObjectGUID;EvidenceMode='Live AD command result'}
    }
}
