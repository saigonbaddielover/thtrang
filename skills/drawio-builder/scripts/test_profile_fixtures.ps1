param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot),
    [string]$DrawioExecutable,
    [string]$ScratchDirectory
)

$ErrorActionPreference = 'Stop'
$SkillPath = (Resolve-Path -LiteralPath $SkillPath).Path
$engine = (Get-Process -Id $PID).Path
$scriptsPath = Join-Path $SkillPath 'scripts'
$fixtureRoot = Join-Path (Join-Path $scriptsPath 'fixtures') 'profiles'
$index = Get-Content -LiteralPath (Join-Path $fixtureRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$observations = [System.Collections.Generic.List[object]]::new()
$createdScratch = $false

if (-not $ScratchDirectory) {
    $scratchBase = Join-Path (Get-Location).Path '.tmp'
    if (-not (Test-Path -LiteralPath $scratchBase)) { New-Item -ItemType Directory -Path $scratchBase -Force | Out-Null }
    $ScratchDirectory = Join-Path $scratchBase ('drawio-profile-fixtures-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $ScratchDirectory | Out-Null
    $createdScratch = $true
}
else {
    if (-not (Test-Path -LiteralPath $ScratchDirectory -PathType Container)) { New-Item -ItemType Directory -Path $ScratchDirectory -Force | Out-Null }
    $ScratchDirectory = (Resolve-Path -LiteralPath $ScratchDirectory).Path
}

function Invoke-Script {
    param([string]$Path,[string[]]$Arguments)
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine -NoProfile -File $Path @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prior }
    [pscustomobject]@{ ExitCode=$exitCode; Output=($output -join "`n") }
}

try {
    if ([int]$index.schemaVersion -ne 1 -or @($index.fixtures).Count -lt 16) { $failures.Add('index:contract') }
    Import-Module (Join-Path (Join-Path $scriptsPath 'lib') 'Drawio.Contract.psm1')
    $matcherWithoutNoneOf = [pscustomobject]@{ allOf=@('shape=process') }
    $matcherWithNoneOf = [pscustomobject]@{ allOf=@('shape=process'); noneOf=@('html=1') }
    if (-not (Test-StyleMatcher @('shape=process','html=1') $matcherWithoutNoneOf) -or (Test-StyleMatcher @('shape=process','html=1') $matcherWithNoneOf)) { $failures.Add('style-matcher:truth-table') }
    foreach ($fixture in @($index.fixtures)) {
        $xmlPath = Join-Path $fixtureRoot ([string]$fixture.xml)
        $manifestPath = Join-Path $fixtureRoot ([string]$fixture.manifest)
        $profilePath = Join-Path $SkillPath ([string]$fixture.profile)
        $preflight = Invoke-Script (Join-Path $scriptsPath 'preflight_drawio.ps1') @('-SourcePath', $xmlPath)
        if ($preflight.ExitCode -ne 0) { $failures.Add("$($fixture.id):preflight") }
        $contract = Invoke-DrawioContractAudit -SourcePath $xmlPath -Family ([string]$fixture.family) -SemanticManifestPath $manifestPath -NotationProfilePath $profilePath
        $expectedStatus = if ($fixture.PSObject.Properties['expectedContractStatus']) { [string]$fixture.expectedContractStatus } else { [string]$fixture.expectedContractOutcome }
        if ([string]$contract.OverallStatus -ne $expectedStatus) { $failures.Add("$($fixture.id):expected-$($expectedStatus.ToLowerInvariant())") }
        $observedReasonTypes = @($contract.Issues.Type) + @($contract.Reasons.Type)
        if ($fixture.PSObject.Properties['expectedIssueType'] -and [string]$fixture.expectedIssueType -notin $observedReasonTypes) { $failures.Add("$($fixture.id):expected-issue") }
        if ($fixture.PSObject.Properties['minimumUnresolvedManualRuleCount'] -and [int]$contract.UnresolvedManualRuleCount -lt [int]$fixture.minimumUnresolvedManualRuleCount) { $failures.Add("$($fixture.id):manual-rules") }
        $notationIssues = @($contract.Issues | Where-Object { [string]$_.Type -like 'notation-*' })
        $observedMapping = if (@($notationIssues | Where-Object Type -eq 'notation-mapping-unresolved').Count -gt 0) { 'UNKNOWN' } elseif ($notationIssues.Count -gt 0) { 'FAIL' } else { 'PASS' }
        if ($fixture.PSObject.Properties['expectedAutomatedMapping'] -and [string]$fixture.expectedAutomatedMapping -ne $observedMapping) { $failures.Add("$($fixture.id):automated-mapping") }
        $renderSmoke = if ($fixture.PSObject.Properties['renderSmoke']) { [bool]$fixture.renderSmoke } else { $expectedStatus -eq 'PASS' }
        if ($DrawioExecutable -and $renderSmoke) {
            $wrapperPath = Join-Path $ScratchDirectory ("profile-$($fixture.id).drawio")
            $svgPath = Join-Path $ScratchDirectory ("profile-$($fixture.id).svg")
            $sync = Invoke-Script (Join-Path $scriptsPath 'sync_drawio.ps1') @('-Direction','ToDrawio','-CanonicalPath',$xmlPath,'-DrawioPath',$wrapperPath,'-PageId',([string]$fixture.id),'-PageName',([string]$fixture.id))
            if ($sync.ExitCode -ne 0) { $failures.Add("$($fixture.id):sync") }
            else {
                $export = Invoke-Script (Join-Path $scriptsPath 'export_drawio.ps1') @('-CanonicalPath',$xmlPath,'-DrawioPath',$wrapperPath,'-PageId',([string]$fixture.id),'-DrawioExecutable',$DrawioExecutable,'-SvgPath',$svgPath)
                if ($export.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $svgPath -PathType Leaf)) { $failures.Add("$($fixture.id):render") }
                else {
                    try {
                        [xml]$svg = Get-Content -LiteralPath $svgPath -Raw -Encoding UTF8
                        if (-not $svg.DocumentElement -or $svg.DocumentElement.LocalName -ne 'svg') { $failures.Add("$($fixture.id):svg") }
                    }
                    catch { $failures.Add("$($fixture.id):svg") }
                    $validation = Invoke-Script (Join-Path $scriptsPath 'validate_drawio.ps1') @('-SourcePath',$xmlPath,'-SvgPath',$svgPath,'-Family',([string]$fixture.family),'-SemanticManifestPath',$manifestPath,'-NotationProfilePath',$profilePath,'-ValidationMode','Audit')
                    try {
                        $validationData = $validation.Output | ConvertFrom-Json
                        $issueTypes = @($validationData.Gates.Result.Issues.Type)
                        if ('gate-exception' -in $issueTypes -or 'invalid-gate-output' -in $issueTypes) { $failures.Add("$($fixture.id):validator-runtime") }
                        if ([string]$fixture.id -eq 'process-document-flow-swimlane' -and 'lane-header-label-overlap' -in $issueTypes) { $failures.Add("$($fixture.id):nested-lane-label") }
                    }
                    catch { $failures.Add("$($fixture.id):validator-json") }
                }
            }
        }
        $observations.Add([pscustomobject]@{ Id=[string]$fixture.id; Expected=$expectedStatus; Observed=[string]$contract.OverallStatus; ExpectedAutomatedMapping=[string]$fixture.expectedAutomatedMapping; ObservedAutomatedMapping=$observedMapping; ErrorCount=[int]$contract.ErrorCount; WarningCount=[int]$contract.WarningCount; UnresolvedManualRuleCount=[int]$contract.UnresolvedManualRuleCount; RenderSmoke=$renderSmoke })
    }
    [pscustomobject]@{ SchemaVersion=1; OverallStatus=$(if($failures.Count-eq0){'PASS'}else{'FAIL'}); FixtureCount=@($index.fixtures).Count; RenderedCount=$(if($DrawioExecutable){@($observations|Where-Object RenderSmoke).Count}else{0}); FailureCount=$failures.Count; Failures=@($failures); Observations=@($observations) } | ConvertTo-Json -Depth 6
    if ($failures.Count -gt 0) { exit 1 }
}
finally {
    if ($createdScratch -and (Test-Path -LiteralPath $ScratchDirectory)) { Remove-Item -LiteralPath $ScratchDirectory -Recurse -Force }
}
