param(
    [Parameter(Mandatory = $true)]
    [string]$BeforeReportPath,

    [Parameter(Mandatory = $true)]
    [string]$AfterReportPath,

    [ValidateSet('Repair','Construction')]
    [string]$Operation = 'Repair',

    [switch]$ErrorsOnly,
    [switch]$AllowNoImprovement
)

$ErrorActionPreference = 'Stop'

function Get-IssueInventory {
    param(
        [string]$Path,
        [bool]$IncludeWarningRows
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Validation report not found: $Path" }
    $report = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $rows = [System.Collections.Generic.List[object]]::new()
    if ($report.PSObject.Properties.Name -contains 'Gates') {
        foreach ($gate in @($report.Gates)) {
            foreach ($issue in @($gate.Result.Issues)) {
                if (-not $issue) { continue }
                $rows.Add([pscustomobject]@{
                    Gate = [string]$gate.Name
                    Severity = [string]$issue.Severity
                    Type = [string]$issue.Type
                    Element = [string]$issue.Element
                })
            }
        }
    }
    else {
        foreach ($issue in @($report.Issues)) {
            if (-not $issue) { continue }
            $rows.Add([pscustomobject]@{
                Gate = 'direct-audit'
                Severity = [string]$issue.Severity
                Type = [string]$issue.Type
                Element = [string]$issue.Element
            })
        }
    }

    $inventory = @{}
    foreach ($row in $rows) {
        if ($row.Severity -ne 'ERROR' -and -not ($IncludeWarningRows -and $row.Severity -eq 'WARNING')) { continue }
        $key = "$($row.Severity)|$($row.Gate)|$($row.Type)|$($row.Element)"
        if (-not $inventory.ContainsKey($key)) { $inventory[$key] = 0 }
        $inventory[$key]++
    }
    $inventory
}

function Get-InventoryDelta {
    param(
        [hashtable]$Left,
        [hashtable]$Right
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($Left.Keys + $Right.Keys | Sort-Object -Unique)) {
        $leftCount = if ($Left.ContainsKey($key)) { [int]$Left[$key] } else { 0 }
        $rightCount = if ($Right.ContainsKey($key)) { [int]$Right[$key] } else { 0 }
        if ($rightCount -le $leftCount) { continue }
        $parts = $key.Split('|', 4)
        $rows.Add([pscustomobject]@{
            Severity = $parts[0]
            Gate = $parts[1]
            Type = $parts[2]
            Element = $parts[3]
            Count = $rightCount - $leftCount
        })
    }
    @($rows)
}

$includeWarnings = -not [bool]$ErrorsOnly
$before = Get-IssueInventory $BeforeReportPath $includeWarnings
$after = Get-IssueInventory $AfterReportPath $includeWarnings
$introduced = @(Get-InventoryDelta $before $after)
$fixed = @(Get-InventoryDelta $after $before)
$beforeCount = @($before.Values | Measure-Object -Sum).Sum
$afterCount = @($after.Values | Measure-Object -Sum).Sum
$introducedCount = @($introduced | Measure-Object Count -Sum).Sum
$fixedCount = @($fixed | Measure-Object Count -Sum).Sum
if ($null -eq $beforeCount) { $beforeCount = 0 }
if ($null -eq $afterCount) { $afterCount = 0 }
if ($null -eq $introducedCount) { $introducedCount = 0 }
if ($null -eq $fixedCount) { $fixedCount = 0 }
$improved = $afterCount -lt $beforeCount
$passed = if ($Operation -eq 'Construction') {
    $beforeCount -eq 0 -and $afterCount -eq 0 -and $introduced.Count -eq 0
}
else {
    $introduced.Count -eq 0 -and ($improved -or $AllowNoImprovement)
}
$decision = if ($passed -and $Operation -eq 'Construction') { 'ACCEPT STAGE' } elseif ($passed) { 'ACCEPT REPAIR' } elseif ($Operation -eq 'Construction') { 'REJECT STAGE' } else { 'REJECT REPAIR' }

$result = [pscustomobject]@{
    BeforeReport = (Resolve-Path -LiteralPath $BeforeReportPath).Path
    AfterReport = (Resolve-Path -LiteralPath $AfterReportPath).Path
    Operation = $Operation
    ErrorsOnly = [bool]$ErrorsOnly
    BeforeIssueCount = [int]$beforeCount
    AfterIssueCount = [int]$afterCount
    Improved = $improved
    IntroducedCount = [int]$introducedCount
    FixedCount = [int]$fixedCount
    Introduced = $introduced
    Fixed = $fixed
    Decision = $decision
}
$result | ConvertTo-Json -Depth 6
if (-not $passed) { exit 1 }
