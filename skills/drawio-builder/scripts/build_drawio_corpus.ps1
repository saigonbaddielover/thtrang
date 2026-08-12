param(
    [Parameter(Mandatory = $true)][string]$CorpusRoot,
    [string]$DrawioExecutable,
    [string]$OutputRoot,
    [string[]]$BaseName,
    [ValidateSet('Export','Validate','ExportAndValidate')][string]$Mode = 'ExportAndValidate',
    [ValidateSet('process','data-flow','bpmn','uml','erd','architecture','cloud','network','engineering','electrical','pid','floorplan','wireframe','generic')][string]$Family = 'process'
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$scripts = $PSScriptRoot
$root = (Resolve-Path -LiteralPath $CorpusRoot).Path
if (-not $OutputRoot) { $OutputRoot = Join-Path $root '.tmp\drawio-corpus' }
$output = [System.IO.Path]::GetFullPath($OutputRoot)
$canonicalRoot = Join-Path $root 'drawio-src'
$wrapperRoot = Join-Path $root 'assets\drawio'
$svgRoot = Join-Path $root 'assets\svg'
$pngRoot = Join-Path $root 'assets\images'

foreach ($directory in @($canonicalRoot,$wrapperRoot,$svgRoot,$pngRoot)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Corpus directory not found: $directory" }
}

function Invoke-DrawioTool {
    param([string]$Stage,[string]$Diagram,[string]$Path,[string[]]$Arguments)
    $lines = @(& $engine -NoProfile -File $Path @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $lines -join "`n"
    if ($exitCode -ne 0) { throw "$Stage failed for ${Diagram}: $text" }
    $text
}

$canonicalFiles = @(Get-ChildItem -LiteralPath $canonicalRoot -Filter '*.xml' -File | Sort-Object Name)
if ($BaseName) {
    $requested = @($BaseName | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $canonicalFiles = @($canonicalFiles | Where-Object { $_.BaseName -in $requested })
    $missing = @($requested | Where-Object { $_ -notin @($canonicalFiles.BaseName) })
    if ($missing.Count -gt 0) { throw "Canonical diagrams not found: $($missing -join ', ')" }
}
if ($canonicalFiles.Count -eq 0) { throw 'No canonical diagrams selected' }

$results = [System.Collections.Generic.List[object]]::new()
foreach ($canonical in $canonicalFiles) {
    $name = $canonical.BaseName
    $wrapper = Join-Path $wrapperRoot "$name.drawio"
    $svg = Join-Path $svgRoot "$name.svg"
    $png = Join-Path $pngRoot "$name.png"
    $diagramOutput = Join-Path $output $name
    $wordPng = Join-Path $diagramOutput 'page.png'
    $manifest = Join-Path $diagramOutput 'artifact-manifest.json'
    $reportDirectory = Join-Path $diagramOutput 'audit'
    $pageId = ''

    if ($Mode -in @('Export','ExportAndValidate')) {
        $syncText = Invoke-DrawioTool 'sync' $name (Join-Path $scripts 'sync_drawio.ps1') @('-Direction','ToDrawio','-CanonicalPath',$canonical.FullName,'-DrawioPath',$wrapper)
        $sync = $syncText | ConvertFrom-Json
        $pageId = [string]$sync.PageId
        $exportArguments = @('-CanonicalPath',$canonical.FullName,'-DrawioPath',$wrapper,'-PageId',$pageId,'-SvgPath',$svg,'-PngPath',$png,'-WordPngPath',$wordPng,'-ManifestPath',$manifest)
        if ($DrawioExecutable) { $exportArguments += @('-DrawioExecutable',$DrawioExecutable) }
        Invoke-DrawioTool 'export' $name (Join-Path $scripts 'export_drawio.ps1') $exportArguments | Out-Null
    }

    $errors = $null
    $warnings = $null
    $bends = $null
    $effectiveFont = $null
    if ($Mode -in @('Validate','ExportAndValidate')) {
        $validationText = Invoke-DrawioTool 'validate' $name (Join-Path $scripts 'validate_drawio.ps1') @('-SourcePath',$canonical.FullName,'-SvgPath',$svg,'-Family',$Family,'-ArtifactManifestPath',$manifest,'-RequiredArtifactRoles','canonical,wrapper,svg,png,word-png','-ValidationMode','Audit','-ReportDirectory',$reportDirectory)
        $validation = $validationText | ConvertFrom-Json
        $errors = [int](($validation.Gates.Result.ErrorCount | Measure-Object -Sum).Sum)
        $warnings = [int](($validation.Gates.Result.WarningCount | Measure-Object -Sum).Sum)
        if ($errors -ne 0 -or $warnings -ne 0) { throw "audit findings for ${name}: errors=$errors; warnings=$warnings" }
        $route = $validation.Gates | Where-Object Name -eq 'route-efficiency'
        $composition = $validation.Gates | Where-Object Name -eq 'composition-word-fit'
        $bends = [int]$route.Result.TotalBends
        $effectiveFont = [math]::Round([double]$composition.Result.Word.EffectiveMinimumFontPoints,2)
    }

    $results.Add([pscustomobject]@{ Diagram=$name; PageId=$pageId; Errors=$errors; Warnings=$warnings; Bends=$bends; EffectiveFontPoints=$effectiveFont })
}

[pscustomobject]@{ Mode=$Mode; CorpusRoot=$root; OutputRoot=$output; DiagramCount=$results.Count; Diagrams=@($results) } | ConvertTo-Json -Depth 5
