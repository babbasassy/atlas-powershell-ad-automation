[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path, [ValidateSet('Users','Groups')][string]$Kind='Users')
. "$PSScriptRoot/Lab.Common.ps1"
$rows = @(Read-LabCsv $Path $Kind)
[pscustomobject]@{ Valid=$true; Kind=$Kind; Rows=$rows.Count; EvidenceMode='Local CSV validation; no AD connection' }
