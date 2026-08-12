param(
    [Parameter(Mandatory = $true)]
    [string]$BeforeReportPath,

    [Parameter(Mandatory = $true)]
    [string]$AfterReportPath,

    [ValidateSet('Repair','Construction','Optimization')]
    [string]$Operation = 'Repair',

    [switch]$ErrorsOnly,
    [switch]$AllowNoImprovement,
    [string]$QualityProfilePath
)

$ErrorActionPreference = 'Stop'
if (-not $QualityProfilePath) { $QualityProfilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\quality-profile.json' }

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

function Get-OptimizationMetrics {
    param([string]$Path)
    $report = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $composition = @($report.Gates | Where-Object { [string]$_.Name -eq 'composition-word-fit' } | Select-Object -First 1)
    $routing = @($report.Gates | Where-Object { [string]$_.Name -eq 'route-efficiency' } | Select-Object -First 1)
    if ($composition.Count -ne 1 -or $routing.Count -ne 1) { throw 'Optimization requires composition-word-fit and route-efficiency gates in both reports' }
    [ordered]@{
        EffectiveMinimumFontPoints = [double]$composition[0].Result.Word.EffectiveMinimumFontPoints
        CropArea = [double]$composition[0].Result.Crop.Width * [double]$composition[0].Result.Crop.Height
        TotalBends = [double]$routing[0].Result.TotalBends
        TotalLength = [double]$routing[0].Result.TotalLength
        Routes = @($routing[0].Result.Metrics | ForEach-Object {
            [pscustomobject]@{ Element=[string]$_.Element; BendCount=[int]$_.BendCount }
        })
    }
}

function Compare-RouteBends {
    param(
        [object[]]$BeforeRoutes,
        [object[]]$AfterRoutes
    )

    $beforeMap = @{}
    $afterMap = @{}
    foreach ($route in $BeforeRoutes) {
        if (-not $route.Element -or $beforeMap.ContainsKey($route.Element)) { throw 'Optimization requires unique nonempty route element IDs in the before report' }
        $beforeMap[$route.Element] = [int]$route.BendCount
    }
    foreach ($route in $AfterRoutes) {
        if (-not $route.Element -or $afterMap.ContainsKey($route.Element)) { throw 'Optimization requires unique nonempty route element IDs in the after report' }
        $afterMap[$route.Element] = [int]$route.BendCount
    }

    $added = @($afterMap.Keys | Where-Object { -not $beforeMap.ContainsKey($_) } | Sort-Object)
    $removed = @($beforeMap.Keys | Where-Object { -not $afterMap.ContainsKey($_) } | Sort-Object)
    $regressions = [System.Collections.Generic.List[object]]::new()
    foreach ($element in @($beforeMap.Keys | Where-Object { $afterMap.ContainsKey($_) } | Sort-Object)) {
        if ($afterMap[$element] -le $beforeMap[$element]) { continue }
        $regressions.Add([pscustomobject]@{
            Element = $element
            Before = $beforeMap[$element]
            After = $afterMap[$element]
            AddedBends = $afterMap[$element] - $beforeMap[$element]
        })
    }
    [ordered]@{ Added=$added; Removed=$removed; Regressions=@($regressions) }
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
$metricRows = @()
$metricImproved = $false
$metricRegressed = $false
$routeComparison = [ordered]@{ Added=@(); Removed=@(); Regressions=@() }
if ($Operation -eq 'Optimization') {
    $quality = Get-Content -LiteralPath $QualityProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tolerance = [double]$quality.composition.optimizationRegressionTolerance
    $beforeMetrics = Get-OptimizationMetrics $BeforeReportPath
    $afterMetrics = Get-OptimizationMetrics $AfterReportPath
    $metricRows = @(
        [pscustomobject]@{ Name='EffectiveMinimumFontPoints'; Direction='higher'; Before=$beforeMetrics.EffectiveMinimumFontPoints; After=$afterMetrics.EffectiveMinimumFontPoints },
        [pscustomobject]@{ Name='CropArea'; Direction='lower'; Before=$beforeMetrics.CropArea; After=$afterMetrics.CropArea },
        [pscustomobject]@{ Name='TotalBends'; Direction='lower'; Before=$beforeMetrics.TotalBends; After=$afterMetrics.TotalBends },
        [pscustomobject]@{ Name='TotalLength'; Direction='lower'; Before=$beforeMetrics.TotalLength; After=$afterMetrics.TotalLength }
    )
    foreach ($metric in $metricRows) {
        $baseline = [math]::Max([math]::Abs([double]$metric.Before),0.000001)
        $relative = ([double]$metric.After-[double]$metric.Before)/$baseline
        $metric | Add-Member -NotePropertyName RelativeChange -NotePropertyValue $relative
        $improvement = if ($metric.Direction -eq 'higher') { $relative } else { -$relative }
        $metric | Add-Member -NotePropertyName Improved -NotePropertyValue ($improvement -gt $tolerance)
        $metric | Add-Member -NotePropertyName Regressed -NotePropertyValue ($improvement -lt -$tolerance)
    }
    $routeComparison = Compare-RouteBends $beforeMetrics.Routes $afterMetrics.Routes
    $metricImproved = @($metricRows | Where-Object { $_.Improved }).Count -gt 0
    $metricRegressed = @($metricRows | Where-Object { $_.Regressed }).Count -gt 0 -or $routeComparison.Added.Count -gt 0 -or $routeComparison.Removed.Count -gt 0 -or $routeComparison.Regressions.Count -gt 0
}
$passed = if ($Operation -eq 'Construction') {
    $beforeCount -eq 0 -and $afterCount -eq 0 -and $introduced.Count -eq 0
}
elseif ($Operation -eq 'Optimization') {
    $introduced.Count -eq 0 -and -not $metricRegressed -and ($metricImproved -or $AllowNoImprovement)
}
else {
    $introduced.Count -eq 0 -and ($improved -or $AllowNoImprovement)
}
$decision = if ($passed -and $Operation -eq 'Construction') { 'ACCEPT STAGE' } elseif ($passed -and $Operation -eq 'Optimization') { 'ACCEPT OPTIMIZATION' } elseif ($passed) { 'ACCEPT REPAIR' } elseif ($Operation -eq 'Construction') { 'REJECT STAGE' } elseif ($Operation -eq 'Optimization') { 'REJECT OPTIMIZATION' } else { 'REJECT REPAIR' }

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
    MetricImproved = $metricImproved
    MetricRegressed = $metricRegressed
    Metrics = $metricRows
    RouteIdentityAdded = @($routeComparison.Added)
    RouteIdentityRemoved = @($routeComparison.Removed)
    RouteBendRegressions = @($routeComparison.Regressions)
    Decision = $decision
}
$result | ConvertTo-Json -Depth 6
if (-not $passed) { exit 1 }
