[CmdletBinding(DefaultParameterSetName='Fixture')]
param([Parameter(Mandatory,ParameterSetName='Fixture')][string]$FixturePath,
      [Parameter(Mandatory,ParameterSetName='Live')][switch]$Live,
      [ValidateRange(1,3650)][int]$Days=90,
      [DateTimeOffset]$AsOfUtc=[DateTimeOffset]::UtcNow,
      [string]$Server='DC01.corp.atlas.test',
      [string]$SearchBase='OU=AutomationLab,OU=ATLAS,DC=corp,DC=atlas,DC=test',
      [string]$OutputPath)
. "$PSScriptRoot/Lab.Common.ps1"
if ($PSCmdlet.ParameterSetName -eq 'Fixture') {
    $rows = @(Import-Csv -LiteralPath $FixturePath)
    $mode = 'Synthetic fixture; no AD connection'
} else {
    Connect-LabDirectory $Server $SearchBase
    $rows = @(Get-ADUser -Filter * -SearchBase $SearchBase -SearchScope OneLevel -Server $Server -Properties Enabled,whenCreated,LastLogonDate -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{SamAccountName=$_.SamAccountName;Enabled=$_.Enabled;CreatedUtc=$_.whenCreated.ToUniversalTime().ToString('o');LastLogonUtc=$(if($_.LastLogonDate){$_.LastLogonDate.ToUniversalTime().ToString('o')}else{''})}
    })
    $mode = 'Live AD snapshot; replicated logon timestamp is approximate'
}
$result = @(Get-LabInactiveResult $rows $AsOfUtc $Days $mode)
if ($OutputPath) { Write-LabCsv $result $OutputPath }
$result
