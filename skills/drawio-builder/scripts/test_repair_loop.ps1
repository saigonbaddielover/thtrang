param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$comparer = Join-Path $PSScriptRoot 'compare_drawio_reports.ps1'
$scratchBase = Join-Path $SkillPath '.tmp'
$scratch = Join-Path $scratchBase ('drawio-repair-loop-' + [guid]::NewGuid().ToString('N'))
$results = [System.Collections.Generic.List[object]]::new()

function Write-Report {
    param([string]$Path,[object[]]$Issues)
    $report = [ordered]@{
        Gates = @([ordered]@{
            Name = 'connector-geometry'
            Result = [ordered]@{ Issues = @($Issues) }
        })
    }
    [System.IO.File]::WriteAllText($Path, ($report | ConvertTo-Json -Depth 6) + "`n", [System.Text.UTF8Encoding]::new($false))
}

function New-Issue {
    param([string]$Type,[string]$Element,[string]$Severity = 'ERROR')
    [pscustomobject]@{ Severity=$Severity; Type=$Type; Element=$Element }
}

function Invoke-Compare {
    param([string]$Before,[string]$After,[string[]]$Extra = @())
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine -NoProfile -File $comparer -BeforeReportPath $Before -AfterReportPath $After @Extra 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    [pscustomobject]@{ ExitCode=$exitCode; Output=($output -join "`n") }
}

function Add-Result {
    param([string]$Name,[bool]$Passed,[string]$Detail)
    $results.Add([pscustomobject]@{ Name=$Name; Passed=$Passed; Detail=$Detail })
}

if (-not (Test-Path -LiteralPath $scratchBase)) { New-Item -ItemType Directory -Path $scratchBase | Out-Null }
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $before = Join-Path $scratch 'before.json'
    $improved = Join-Path $scratch 'improved.json'
    $regressed = Join-Path $scratch 'regressed.json'
    $swapped = Join-Path $scratch 'swapped.json'
    $warningRegression = Join-Path $scratch 'warning-regression.json'
    $unchanged = Join-Path $scratch 'unchanged.json'
    $cleanBefore = Join-Path $scratch 'clean-before.json'
    $cleanAfter = Join-Path $scratch 'clean-after.json'
    $dirtyStage = Join-Path $scratch 'dirty-stage.json'
    Write-Report $before @((New-Issue 'connector-crossing' 'e8'),(New-Issue 'source-micro-jog' 'e2'))
    Write-Report $improved @((New-Issue 'source-micro-jog' 'e2'))
    Write-Report $regressed @((New-Issue 'connector-crossing' 'e8'),(New-Issue 'source-micro-jog' 'e2'),(New-Issue 'target-direction' 'e9'))
    Write-Report $swapped @((New-Issue 'connector-crossing' 'e8'),(New-Issue 'label-node-collision' 'e4'))
    Write-Report $warningRegression @((New-Issue 'source-micro-jog' 'e2'),(New-Issue 'spacing-variance' 'node-group' 'WARNING'))
    Copy-Item -LiteralPath $before -Destination $unchanged
    Write-Report $cleanBefore @()
    Write-Report $cleanAfter @()
    Write-Report $dirtyStage @((New-Issue 'target-direction' 'e9'))

    $improvedResult = Invoke-Compare $before $improved
    $improvedData = $improvedResult.Output | ConvertFrom-Json
    Add-Result 'strict-improvement-accepted' ($improvedResult.ExitCode -eq 0 -and $improvedData.Decision -eq 'ACCEPT REPAIR' -and $improvedData.FixedCount -eq 1) $improvedResult.Output

    $regressedResult = Invoke-Compare $before $regressed
    $regressedData = $regressedResult.Output | ConvertFrom-Json
    Add-Result 'new-error-rejected' ($regressedResult.ExitCode -eq 1 -and $regressedData.Decision -eq 'REJECT REPAIR' -and $regressedData.IntroducedCount -eq 1) $regressedResult.Output

    $swappedResult = Invoke-Compare $before $swapped
    $swappedData = $swappedResult.Output | ConvertFrom-Json
    Add-Result 'issue-swap-rejected' ($swappedResult.ExitCode -eq 1 -and $swappedData.IntroducedCount -eq 1 -and $swappedData.FixedCount -eq 1) $swappedResult.Output

    $warningResult = Invoke-Compare $before $warningRegression
    $warningData = $warningResult.Output | ConvertFrom-Json
    Add-Result 'new-warning-rejected' ($warningResult.ExitCode -eq 1 -and $warningData.IntroducedCount -eq 1) $warningResult.Output

    $unchangedResult = Invoke-Compare $before $unchanged
    Add-Result 'no-op-repair-rejected' ($unchangedResult.ExitCode -eq 1) $unchangedResult.Output

    $allowedResult = Invoke-Compare $before $unchanged @('-AllowNoImprovement')
    Add-Result 'explicit-no-op-allowed' ($allowedResult.ExitCode -eq 0) $allowedResult.Output

    $cleanStageResult = Invoke-Compare $cleanBefore $cleanAfter @('-Operation','Construction')
    $cleanStageData = $cleanStageResult.Output | ConvertFrom-Json
    Add-Result 'clean-construction-stage-accepted' ($cleanStageResult.ExitCode -eq 0 -and $cleanStageData.Decision -eq 'ACCEPT STAGE') $cleanStageResult.Output

    $dirtyStageResult = Invoke-Compare $cleanBefore $dirtyStage @('-Operation','Construction')
    $dirtyStageData = $dirtyStageResult.Output | ConvertFrom-Json
    Add-Result 'dirty-construction-stage-rejected' ($dirtyStageResult.ExitCode -eq 1 -and $dirtyStageData.Decision -eq 'REJECT STAGE' -and $dirtyStageData.IntroducedCount -eq 1) $dirtyStageResult.Output

    $failed = @($results | Where-Object { -not $_.Passed })
    [pscustomobject]@{
        Engine = $engine
        Version = $PSVersionTable.PSVersion.ToString()
        TestCount = $results.Count
        FailedCount = $failed.Count
        Tests = @($results)
    } | ConvertTo-Json -Depth 6
    if ($failed.Count -gt 0) { exit 1 }
}
finally {
    $resolvedScratch = [System.IO.Path]::GetFullPath($scratch)
    $resolvedBase = [System.IO.Path]::GetFullPath($scratchBase)
    if ($resolvedScratch.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedScratch)) { [System.IO.Directory]::Delete($resolvedScratch, $true) }
}
