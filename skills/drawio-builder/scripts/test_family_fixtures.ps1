param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot),
    [string]$DrawioExecutable,
    [string]$ScratchDirectory
)

$ErrorActionPreference = 'Stop'
$SkillPath = (Resolve-Path -LiteralPath $SkillPath).Path
$engine = (Get-Process -Id $PID).Path
$scriptsPath = Join-Path $SkillPath 'scripts'
$fixtureRoot = Join-Path $scriptsPath 'fixtures\families'
$coverage = Get-Content -LiteralPath (Join-Path $fixtureRoot 'coverage.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$observations = [System.Collections.Generic.List[object]]::new()
$createdScratch = $false
$expectedFamilies = @('architecture','bpmn','cloud','data-flow','electrical','engineering','erd','floorplan','network','pid','process','uml','wireframe')
$expectedGroups = @('data-flow','modeling','process','spatial','technical','topology')

function Compare-ExactSet {
    param([string[]]$Expected,[string[]]$Actual)
    @($Expected).Count -eq @($Actual).Count -and @(Compare-Object @($Expected | Sort-Object) @($Actual | Sort-Object)).Count -eq 0
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

if (-not $ScratchDirectory) {
    $scratchBase = Join-Path (Get-Location).Path '.tmp'
    if (-not (Test-Path -LiteralPath $scratchBase)) { New-Item -ItemType Directory -Path $scratchBase -Force | Out-Null }
    $ScratchDirectory = Join-Path $scratchBase ('drawio-family-fixtures-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $ScratchDirectory | Out-Null
    $createdScratch = $true
}
elseif (-not (Test-Path -LiteralPath $ScratchDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ScratchDirectory -Force | Out-Null
}
$ScratchDirectory = (Resolve-Path -LiteralPath $ScratchDirectory).Path

try {
    if ([int]$coverage.schemaVersion -ne 1) { $failures.Add('coverage:schema-version') }
    $groups = @($coverage.groups)
    $groupIds = @($groups.id)
    if (-not (Compare-ExactSet $expectedGroups $groupIds)) { $failures.Add('coverage:groups') }
    if (@($groupIds | Sort-Object -Unique).Count -ne $groupIds.Count) { $failures.Add('coverage:duplicate-group') }

    $coveredFamilies = @($groups | ForEach-Object { @($_.families) })
    if (-not (Compare-ExactSet $expectedFamilies $coveredFamilies)) { $failures.Add('coverage:families') }
    $referenceFamilies = @(Get-ChildItem -LiteralPath (Join-Path $SkillPath 'references\families') -Filter '*.md' -File | ForEach-Object BaseName)
    if (-not (Compare-ExactSet $expectedFamilies $referenceFamilies)) { $failures.Add('coverage:references') }

    $coveredProfiles = @($groups | ForEach-Object { @($_.profileCoverage) })
    $actualProfiles = @(Get-ChildItem -LiteralPath (Join-Path $SkillPath 'profiles') -Filter '*.json' -File | ForEach-Object { 'profiles/' + $_.Name })
    if (-not (Compare-ExactSet $actualProfiles $coveredProfiles)) { $failures.Add('coverage:profiles') }
    if (@($coveredProfiles | Sort-Object -Unique).Count -ne $coveredProfiles.Count) { $failures.Add('coverage:duplicate-profile') }
    foreach ($profile in $coveredProfiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $SkillPath $profile) -PathType Leaf)) { $failures.Add("coverage:missing-profile:$profile") }
    }

    $fixtureReferences = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $groups) {
        foreach ($property in @('positive','notationInvalid','visualInvalid')) {
            $relative = [string]$group.$property
            if (-not $relative) { $failures.Add("$($group.id):missing-$property"); continue }
            $fixtureReferences.Add($relative.Replace('\','/'))
            $xmlPath = Join-Path $fixtureRoot $relative
            if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf)) { $failures.Add("$($group.id):missing-$property"); continue }
            $preflight = Invoke-Script (Join-Path $scriptsPath 'preflight_drawio.ps1') @('-SourcePath',$xmlPath)
            if ($preflight.ExitCode -ne 0) { $failures.Add("$($group.id):preflight-$property") }
        }
    }
    $actualFixtures = @(Get-ChildItem -LiteralPath $fixtureRoot -Filter '*.xml' -File -Recurse | ForEach-Object { $_.FullName.Substring($fixtureRoot.Length + 1).Replace('\','/') })
    if (-not (Compare-ExactSet @($fixtureReferences) $actualFixtures)) { $failures.Add('coverage:fixture-inventory') }
    if ($fixtureReferences.Count -ne 18 -or @($fixtureReferences | Sort-Object -Unique).Count -ne 18) { $failures.Add('coverage:fixture-count') }

    if ($DrawioExecutable) {
        foreach ($group in $groups) {
            $xmlPath = Join-Path $fixtureRoot ([string]$group.positive)
            $wrapperPath = Join-Path $ScratchDirectory ("family-$($group.id).drawio")
            $svgPath = Join-Path $ScratchDirectory ("family-$($group.id).svg")
            $sync = Invoke-Script (Join-Path $scriptsPath 'sync_drawio.ps1') @('-Direction','ToDrawio','-CanonicalPath',$xmlPath,'-DrawioPath',$wrapperPath,'-PageId',([string]$group.id),'-PageName',([string]$group.id))
            if ($sync.ExitCode -ne 0) { $failures.Add("$($group.id):sync"); continue }
            $export = Invoke-Script (Join-Path $scriptsPath 'export_drawio.ps1') @('-CanonicalPath',$xmlPath,'-DrawioPath',$wrapperPath,'-PageId',([string]$group.id),'-DrawioExecutable',$DrawioExecutable,'-SvgPath',$svgPath)
            if ($export.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $svgPath -PathType Leaf)) { $failures.Add("$($group.id):render"); continue }
            try {
                [xml]$svg = Get-Content -LiteralPath $svgPath -Raw -Encoding UTF8
                $viewBox = @([string]$svg.DocumentElement.viewBox -split '\s+' | Where-Object { $_ })
                if ($svg.DocumentElement.LocalName -ne 'svg' -or $viewBox.Count -ne 4 -or [double]$viewBox[2] -le 0 -or [double]$viewBox[3] -le 0) { $failures.Add("$($group.id):svg") }
            }
            catch { $failures.Add("$($group.id):svg") }
            $observations.Add([pscustomobject]@{ Group=[string]$group.id; Svg=$svgPath })
        }
    }

    [pscustomobject]@{
        SchemaVersion=1
        OverallStatus=$(if($failures.Count-eq0){'PASS'}else{'FAIL'})
        Scope='inventory-geometry-smoke'
        NotationProof=$false
        GroupCount=$groups.Count
        FamilyCount=$coveredFamilies.Count
        ProfileCount=$coveredProfiles.Count
        FixtureCount=$fixtureReferences.Count
        RenderedCount=$observations.Count
        FailureCount=$failures.Count
        Failures=@($failures)
        Observations=@($observations)
    } | ConvertTo-Json -Depth 5
    if ($failures.Count -gt 0) { exit 1 }
}
finally {
    if ($createdScratch -and (Test-Path -LiteralPath $ScratchDirectory)) { [System.IO.Directory]::Delete($ScratchDirectory,$true) }
}
