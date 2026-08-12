param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Check', 'Install')]
    [string]$Mode,

    [string]$SourcePath = (Split-Path -Parent $PSScriptRoot),
    [string]$DestinationPath,
    [string]$DrawioExecutable,
    [switch]$SkipTests,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$manifestName = '.drawio-builder-install.json'
$engine = (Get-Process -Id $PID).Path

function Get-NormalizedPath {
    param([string]$Path)
    [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-DefaultDestination {
    if ($env:CODEX_HOME) {
        return Join-Path $env:CODEX_HOME 'skills\drawio-builder'
    }
    $profileRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not $profileRoot) { throw 'Unable to resolve the user profile directory' }
    Join-Path $profileRoot '.codex\skills\drawio-builder'
}

function Get-RelativeFileRecords {
    param([string]$Root)
    $rootPath = Get-NormalizedPath $Root
    $prefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
    @(
        Get-ChildItem -LiteralPath $rootPath -File -Recurse | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length).Replace('\', '/')
            if ($_.Name -eq $manifestName -or $relative -match '^(\.git|\.tmp)(/|$)') { return }
            [pscustomobject]@{
                path = $relative
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } | Sort-Object path
    )
}

function Get-ContentDigest {
    param([object[]]$Records)
    $payload = (@($Records | ForEach-Object { "$($_.path)`0$($_.sha256)" }) -join "`n")
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-SourceRevision {
    param([string]$Root)
    $repositoryRoot = @(& git -C $Root rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $repositoryRoot.Count -ne 1) { throw 'Skill source must be inside a Git repository' }
    $commit = @(& git -C $Root rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $commit.Count -ne 1) { throw 'Unable to resolve the skill source commit' }
    $sourceRoot = Get-NormalizedPath $Root
    $repoRoot = Get-NormalizedPath $repositoryRoot[0]
    $relative = $sourceRoot.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
    if (-not $relative) { $relative = '.' }
    $status = @(& git -C $repoRoot status --porcelain=v1 --untracked-files=all -- $relative 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the skill source state' }
    [pscustomobject]@{
        Commit = ([string]$commit[0]).Trim()
        Clean = $status.Count -eq 0
        RepositoryRoot = $repoRoot
    }
}

function Invoke-PowerShellScript {
    param(
        [string]$Path,
        [string[]]$Arguments
    )
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine -NoProfile -File $Path @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prior
    }
    [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

function Test-SkillTree {
    param([string]$Root)
    $validator = Join-Path $Root 'scripts\validate_skill.ps1'
    $runner = Join-Path $Root 'scripts\test_drawio_builder.ps1'
    if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { throw "Skill validator not found: $validator" }
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Skill test runner not found: $runner" }
    $validation = Invoke-PowerShellScript $validator @('-SkillPath', $Root)
    if ($validation.ExitCode -ne 0) { throw "Skill validation failed:`n$($validation.Output)" }
    $arguments = @('-SkillPath', $Root, '-SkipSyncTests')
    if ($DrawioExecutable) { $arguments += @('-DrawioExecutable', $DrawioExecutable) }
    $tests = Invoke-PowerShellScript $runner $arguments
    if ($tests.ExitCode -ne 0) { throw "Skill tests failed:`n$($tests.Output)" }
    [pscustomobject]@{ Validation = ($validation.Output | ConvertFrom-Json); Tests = ($tests.Output | ConvertFrom-Json) }
}

function Test-DestinationState {
    param(
        [string]$Root,
        [object[]]$SourceRecords
    )
    if (-not (Test-Path -LiteralPath $Root)) {
        return [pscustomobject]@{ Exists = $false; Drifted = $false; MatchesSource = $false; Issues = @('destination-missing'); Manifest = $null }
    }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Destination is not a directory: $Root" }
    $issues = [System.Collections.Generic.List[string]]::new()
    $manifestPath = Join-Path $Root $manifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $true; Drifted = $true; MatchesSource = $false; Issues = @('install-manifest-missing'); Manifest = $null }
    }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return [pscustomobject]@{ Exists = $true; Drifted = $true; MatchesSource = $false; Issues = @('install-manifest-invalid'); Manifest = $null } }
    if ([int]$manifest.schemaVersion -ne 1) { $issues.Add('install-manifest-version-invalid') }
    if ([string]$manifest.skillName -ne 'drawio-builder') { $issues.Add('install-manifest-skill-invalid') }
    $actual = @(Get-RelativeFileRecords $Root)
    $recorded = @($manifest.files | Sort-Object path)
    $actualMap = @{}
    foreach ($record in $actual) { $actualMap[[string]$record.path] = [string]$record.sha256 }
    $recordedMap = @{}
    foreach ($record in $recorded) { $recordedMap[[string]$record.path] = [string]$record.sha256 }
    if ($recordedMap.Count -ne $recorded.Count) { $issues.Add('install-manifest-duplicate-path') }
    foreach ($path in @($actualMap.Keys + $recordedMap.Keys | Sort-Object -Unique)) {
        if (-not $actualMap.ContainsKey($path) -or -not $recordedMap.ContainsKey($path) -or $actualMap[$path] -ne $recordedMap[$path]) {
            $issues.Add("destination-drift:$path")
        }
    }
    $recordedDigest = Get-ContentDigest $recorded
    if ([string]$manifest.contentDigest -ne $recordedDigest) { $issues.Add('install-manifest-digest-mismatch') }
    $sourceMap = @{}
    foreach ($record in $SourceRecords) { $sourceMap[[string]$record.path] = [string]$record.sha256 }
    $matchesSource = $sourceMap.Count -eq $actualMap.Count
    if ($matchesSource) {
        foreach ($path in $sourceMap.Keys) {
            if (-not $actualMap.ContainsKey($path) -or $actualMap[$path] -ne $sourceMap[$path]) { $matchesSource = $false; break }
        }
    }
    [pscustomobject]@{
        Exists = $true
        Drifted = $issues.Count -gt 0
        MatchesSource = $matchesSource
        Issues = @($issues)
        Manifest = $manifest
    }
}

function Assert-ChildPath {
    param(
        [string]$Parent,
        [string]$Child
    )
    $parentPrefix = (Get-NormalizedPath $Parent) + [System.IO.Path]::DirectorySeparatorChar
    $childPath = Get-NormalizedPath $Child
    if (-not $childPath.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Temporary path is outside the destination parent: $childPath"
    }
}

$source = Get-NormalizedPath $SourcePath
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Skill source not found: $source" }
if (-not $DestinationPath) { $DestinationPath = Get-DefaultDestination }
$destination = Get-NormalizedPath $DestinationPath
if ($source -eq $destination -or $destination.StartsWith($source + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination must be outside the source skill tree'
}
$revision = Get-SourceRevision $source
if (-not $revision.Clean) { throw 'Skill source has uncommitted changes; commit the source before checking or installing it' }
$sourceRecords = @(Get-RelativeFileRecords $source)
if ($sourceRecords.Count -eq 0) { throw 'Skill source contains no installable files' }
$sourceDigest = Get-ContentDigest $sourceRecords
$state = Test-DestinationState $destination $sourceRecords

if ($Mode -eq 'Check') {
    $checkTests = if ($SkipTests) { $null } else { Test-SkillTree $source }
    $passed = $state.Exists -and -not $state.Drifted -and $state.MatchesSource -and [string]$state.Manifest.sourceCommit -eq $revision.Commit -and [string]$state.Manifest.contentDigest -eq $sourceDigest
    [pscustomobject]@{
        Mode = $Mode
        Passed = $passed
        SourceCommit = $revision.Commit
        ContentDigest = $sourceDigest
        Destination = $destination
        DestinationExists = $state.Exists
        DestinationDrifted = $state.Drifted
        DestinationMatchesSource = $state.MatchesSource
        Issues = @($state.Issues)
        Tests = if ($checkTests) { $checkTests.Tests } else { $null }
    } | ConvertTo-Json -Depth 8
    if (-not $passed) { exit 1 }
    exit 0
}

if ($state.Exists -and $state.Drifted -and -not $Force) {
    throw "Destination drift detected; rerun with -Force only after reviewing the destination: $($state.Issues -join ', ')"
}

$destinationParent = Split-Path -Parent $destination
if (-not (Test-Path -LiteralPath $destinationParent)) { New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null }
$stage = Join-Path $destinationParent ('.drawio-builder-stage-' + [guid]::NewGuid().ToString('N'))
$backup = Join-Path $destinationParent ('.drawio-builder-backup-' + [guid]::NewGuid().ToString('N'))
Assert-ChildPath $destinationParent $stage
Assert-ChildPath $destinationParent $backup

try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($record in $sourceRecords) {
        $sourceFile = Join-Path $source ($record.path.Replace('/', '\'))
        $stageFile = Join-Path $stage ($record.path.Replace('/', '\'))
        $stageParent = Split-Path -Parent $stageFile
        if (-not (Test-Path -LiteralPath $stageParent)) { New-Item -ItemType Directory -Path $stageParent -Force | Out-Null }
        Copy-Item -LiteralPath $sourceFile -Destination $stageFile
    }
    $stageTests = Test-SkillTree $stage
    $manifest = [ordered]@{
        schemaVersion = 1
        skillName = 'drawio-builder'
        sourceCommit = $revision.Commit
        installedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        contentDigest = $sourceDigest
        files = @($sourceRecords)
    }
    $manifestPath = Join-Path $stage $manifestName
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $destination) { Move-Item -LiteralPath $destination -Destination $backup }
    try {
        Move-Item -LiteralPath $stage -Destination $destination
    }
    catch {
        if (Test-Path -LiteralPath $backup -PathType Container) { Move-Item -LiteralPath $backup -Destination $destination }
        throw
    }
    if (Test-Path -LiteralPath $backup -PathType Container) { Remove-Item -LiteralPath $backup -Recurse -Force }
    $installedManifest = Join-Path $destination $manifestName
    [pscustomobject]@{
        Mode = $Mode
        Passed = $true
        SourceCommit = $revision.Commit
        ContentDigest = $sourceDigest
        ManifestSha256 = (Get-FileHash -LiteralPath $installedManifest -Algorithm SHA256).Hash.ToLowerInvariant()
        Destination = $destination
        Tests = $stageTests.Tests
    } | ConvertTo-Json -Depth 8
}
finally {
    if (Test-Path -LiteralPath $stage -PathType Container) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if (Test-Path -LiteralPath $backup -PathType Container) {
        if (-not (Test-Path -LiteralPath $destination)) { Move-Item -LiteralPath $backup -Destination $destination }
        else { Remove-Item -LiteralPath $backup -Recurse -Force }
    }
}
