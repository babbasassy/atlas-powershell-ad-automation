Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-LabCsv {
    param([string]$Path, [ValidateSet('Users','Groups')][string]$Kind)
    $rows = @(Import-Csv -LiteralPath $Path -Encoding UTF8)
    if ($rows.Count -eq 0) { throw 'CSV must contain at least one data row.' }
    $required = if ($Kind -eq 'Users') { @('SamAccountName','GivenName','Surname') } else { @('Name','Description') }
    $headers = @($rows[0].PSObject.Properties.Name)
    if (@(Compare-Object $required $headers).Count -ne 0) { throw "Expected columns: $($required -join ','). No additional columns allowed." }
    $seen = @{}
    foreach ($row in $rows) {
        foreach ($column in $required) {
            $value = [string]$row.$column
            if ([string]::IsNullOrWhiteSpace($value) -or $value -ne $value.Trim()) { throw "Blank or padded field: $column" }
        }
        $name = if ($Kind -eq 'Users') { $row.SamAccountName } else { $row.Name }
        if ($name -cnotmatch '^lab-auto-[a-z0-9]{1,11}$') { throw "Invalid lab name: $name" }
        if ($seen.ContainsKey($name)) { throw "Duplicate lab name: $name" }
        $seen[$name] = $true
        if ($Kind -eq 'Users') {
            foreach ($field in @('GivenName','Surname')) {
                if ($row.$field -notmatch '^[A-Za-z][A-Za-z -]{0,39}$') { throw "Invalid synthetic name: $field" }
            }
        } elseif ($row.Description -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,79}$') { throw 'Invalid group description.' }
    }
    # Validate the complete batch before returning anything to a caller.
    return $rows
}

function Assert-LabScope {
    param([string]$Server, [string]$SearchBase)
    if ($Server -ine 'DC01.corp.atlas.test') { throw 'Only DC01.corp.atlas.test is permitted.' }
    if ($SearchBase -ine 'OU=AutomationLab,OU=ATLAS,DC=corp,DC=atlas,DC=test') { throw 'Only the dedicated AutomationLab OU is permitted.' }
}

function Connect-LabDirectory {
    param([string]$Server, [string]$SearchBase)
    Assert-LabScope $Server $SearchBase
    Import-Module ActiveDirectory -ErrorAction Stop
    $domain = Get-ADDomain -Server $Server -ErrorAction Stop
    if ($domain.DNSRoot -ine 'corp.atlas.test') { throw 'Connected domain does not match the lab.' }
    $ou = Get-ADOrganizationalUnit -Identity $SearchBase -Server $Server -ErrorAction Stop
    if ($ou.DistinguishedName -ine $SearchBase) { throw 'Target OU verification failed.' }
}

function Convert-LabUtc {
    param([string]$Value)
    if ($Value -notmatch '(Z|[+-]\d{2}:\d{2})$') { throw 'Timestamp must include a UTC offset.' }
    return [DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
}

function Get-LabInactiveResult {
    param([object[]]$Rows, [DateTimeOffset]$AsOfUtc, [int]$Days, [string]$EvidenceMode)
    $cutoff = $AsOfUtc.AddDays(-$Days)
    foreach ($row in $Rows) {
        $enabled = [bool]::Parse([string]$row.Enabled)
        if (-not $enabled) { continue }
        $created = Convert-LabUtc ([string]$row.CreatedUtc)
        $hasLogon = -not [string]::IsNullOrWhiteSpace([string]$row.LastLogonUtc)
        $last = if ($hasLogon) { Convert-LabUtc ([string]$row.LastLogonUtc) } else { $created }
        if ($created -gt $AsOfUtc -or $last -gt $AsOfUtc -or $last -lt $created) { throw "Inconsistent dates for $($row.SamAccountName)" }
        if ($last -le $cutoff) {
            [pscustomobject]@{ SamAccountName=$row.SamAccountName; Reason=$(if($hasLogon){'LastLogonBeforeCutoff'}else{'NeverLoggedOnAndOld'}); ReferenceUtc=$last.ToString('o'); CutoffUtc=$cutoff.ToString('o'); EvidenceMode=$EvidenceMode }
        }
    }
}

function Write-LabCsv {
    param([object[]]$Rows, [string]$Path)
    # Do not overwrite earlier evidence; quoting alone does not prevent spreadsheet formulas.
    if (Test-Path -LiteralPath $Path) { throw 'Output already exists; choose a new report path.' }
    $safe = foreach ($row in $Rows) {
        $copy = [ordered]@{}
        foreach ($property in $row.PSObject.Properties) {
            $value = [string]$property.Value
            if ($value -match '^[\s]*[=+@-]') { $value = "'" + $value }
            $copy[$property.Name] = $value
        }
        [pscustomobject]$copy
    }
    if (@($Rows).Count -eq 0) { throw 'No rows to export; no output file written.' }
    $safe | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -NoClobber
}
