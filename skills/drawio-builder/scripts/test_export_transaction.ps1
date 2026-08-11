param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$exporter = Join-Path $PSScriptRoot 'export_drawio.ps1'
$sync = Join-Path $PSScriptRoot 'sync_drawio.ps1'
$canonical = Join-Path $PSScriptRoot 'fixtures\valid-process.xml'
$results = [System.Collections.Generic.List[object]]::new()
$scratchBase = Join-Path $SkillPath '.tmp'
$scratch = Join-Path $scratchBase ('drawio-export-transaction-' + [guid]::NewGuid().ToString('N'))

function Write-Utf8File {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Invoke-ChildScript {
    param([string]$Path,[string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine -NoProfile -File $Path @Arguments 2>&1)
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
    $rendererDirectory = Join-Path $scratch 'app-9.9.9'
    New-Item -ItemType Directory -Path $rendererDirectory | Out-Null
    $rendererCommand = Join-Path $rendererDirectory 'renderer.cmd'
    Write-Utf8File $rendererCommand @'
@echo off
setlocal
set "format="
set "outputPath="
:parse
if "%~1"=="" goto render
if /I "%~1"=="-f" set "format=%~2"
if /I "%~1"=="-o" set "outputPath=%~2"
shift
goto parse
:render
if "%outputPath%"=="" exit /b 2
if /I "%format%"=="svg" (
  >"%outputPath%" echo ^<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"^>^<rect x="10" y="10" width="10" height="10"/^>^</svg^>
  exit /b 0
)
if /I "%format%"=="pdf" (
  >"%outputPath%" echo invalid-pdf
  exit /b 0
)
exit /b 3
'@

    $wrapper = Join-Path $scratch 'source.drawio'
    $syncResult = Invoke-ChildScript $sync @('-Direction','ToDrawio','-CanonicalPath',$canonical,'-DrawioPath',$wrapper,'-PageId','transaction-page','-PageName','Transaction Page')
    if ($syncResult.ExitCode -ne 0) { throw $syncResult.Output }

    $lateDirectory = Join-Path $scratch 'late-format'
    New-Item -ItemType Directory -Path $lateDirectory | Out-Null
    $lateSvg = Join-Path $lateDirectory 'diagram.svg'
    $latePdf = Join-Path $lateDirectory 'diagram.pdf'
    Write-Utf8File $lateSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"><text>old-svg</text></svg>'
    Write-Utf8File $latePdf 'old-pdf'
    $lateSvgHash = Get-Sha256 $lateSvg
    $latePdfHash = Get-Sha256 $latePdf
    $lateResult = Invoke-ChildScript $exporter @('-CanonicalPath',$canonical,'-DrawioPath',$wrapper,'-PageId','transaction-page','-DrawioExecutable',$rendererCommand,'-SvgPath',$lateSvg,'-PdfPath',$latePdf)
    $lateFiles = @(Get-ChildItem -LiteralPath $lateDirectory -Force -File | Select-Object -ExpandProperty Name | Sort-Object)
    Add-Result 'late-format-failure-preserves-bundle' ($lateResult.ExitCode -ne 0 -and $lateResult.Output -match 'PDF must contain exactly one page' -and (Get-Sha256 $lateSvg) -eq $lateSvgHash -and (Get-Sha256 $latePdf) -eq $latePdfHash -and (@(Compare-Object @('diagram.pdf','diagram.svg') $lateFiles)).Count -eq 0) $lateResult.Output

    $manifestDirectory = Join-Path $scratch 'manifest-failure'
    New-Item -ItemType Directory -Path $manifestDirectory | Out-Null
    $manifestSvg = Join-Path $manifestDirectory 'diagram.svg'
    $manifestPath = Join-Path $manifestDirectory 'artifacts.json'
    Write-Utf8File $manifestSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"><text>old-svg</text></svg>'
    Write-Utf8File $manifestPath '{"schemaVersion":1,"state":"old-manifest"}'
    $manifestSvgHash = Get-Sha256 $manifestSvg
    $manifestHash = Get-Sha256 $manifestPath
    $lock = [System.IO.File]::Open($manifestPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $manifestResult = Invoke-ChildScript $exporter @('-CanonicalPath',$canonical,'-DrawioPath',$wrapper,'-PageId','transaction-page','-DrawioExecutable',$rendererCommand,'-SvgPath',$manifestSvg,'-ManifestPath',$manifestPath)
    }
    finally { $lock.Dispose() }
    $manifestFiles = @(Get-ChildItem -LiteralPath $manifestDirectory -Force -File | Select-Object -ExpandProperty Name | Sort-Object)
    Add-Result 'manifest-commit-failure-rolls-back-bundle' ($manifestResult.ExitCode -ne 0 -and $manifestResult.Output -match 'previous bundle restored' -and (Get-Sha256 $manifestSvg) -eq $manifestSvgHash -and (Get-Sha256 $manifestPath) -eq $manifestHash -and (@(Compare-Object @('artifacts.json','diagram.svg') $manifestFiles)).Count -eq 0) $manifestResult.Output

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
