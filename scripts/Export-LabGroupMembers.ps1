[CmdletBinding(DefaultParameterSetName='Fixture')]
param([Parameter(Mandatory,ParameterSetName='Fixture')][string]$FixturePath,
      [Parameter(Mandatory,ParameterSetName='Live')][switch]$Live,
      [Parameter(Mandatory)][string]$OutputPath,
      [string]$Server='DC01.corp.atlas.test',
      [string]$SearchBase='OU=AutomationLab,OU=ATLAS,DC=corp,DC=atlas,DC=test')
. "$PSScriptRoot/Lab.Common.ps1"
if ($PSCmdlet.ParameterSetName -eq 'Fixture') {
    $data = @(Import-Csv -LiteralPath $FixturePath)
    $mode = 'Synthetic direct-membership fixture; no AD connection'
    $rows = @($data | Select-Object Group,Member,ObjectClass,@{n='EvidenceMode';e={$mode}})
} else {
    Connect-LabDirectory $Server $SearchBase
    $rows = @(foreach ($group in @(Get-ADGroup -Filter * -SearchBase $SearchBase -SearchScope OneLevel -Server $Server -ErrorAction Stop)) {
        $members = @(Get-ADGroupMember -Identity $group.DistinguishedName -Server $Server -ErrorAction Stop)
        if (-not $members.Count) { [pscustomobject]@{Group=$group.Name;Member='';ObjectClass='EmptyGroup';EvidenceMode='Live AD direct membership'} }
        foreach ($member in $members) { [pscustomobject]@{Group=$group.Name;Member=$member.SamAccountName;ObjectClass=$member.objectClass;EvidenceMode='Live AD direct membership'} }
    })
}
Write-LabCsv $rows $OutputPath
[pscustomobject]@{Rows=$rows.Count;OutputPath=$OutputPath;Membership='Direct only; not effective permissions'}
