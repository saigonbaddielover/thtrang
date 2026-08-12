param(
    [Parameter(Mandatory = $true)]
    [string]$CanonicalPath,

    [Parameter(Mandatory = $true)]
    [string]$DrawioPath,

    [string]$DrawioExecutable,
    [string]$PageId,
    [string]$SvgPath,
    [string]$PngPath,
    [string]$WordPngPath,
    [string]$PdfPath,
    [string]$ManifestPath,
    [string]$QualityProfilePath
)

$ErrorActionPreference = 'Stop'
if (-not $QualityProfilePath) { $QualityProfilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\quality-profile.json' }

function Resolve-DrawioExecutable {
    param(
        [string]$RequestedPath,
        [string]$AnchorPath
    )

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) { throw "Draw.io executable not found: $RequestedPath" }
        $resolved = (Resolve-Path -LiteralPath $RequestedPath).Path
        $match = [regex]::Match((Split-Path -Leaf (Split-Path -Parent $resolved)), '^(?:app|desktop)-(?<version>\d+(?:\.\d+){1,3})$')
        $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolved).FileVersion
        if ($match.Success) { $version = $match.Groups['version'].Value }
        return [pscustomobject]@{ Path=$resolved; Version=$version }
    }
    foreach ($commandName in @('draw.io', 'drawio')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            $resolved = $command.Source
            return [pscustomobject]@{ Path=$resolved; Version=[System.Diagnostics.FileVersionInfo]::GetVersionInfo($resolved).FileVersion }
        }
    }
    $directory = Split-Path -Parent (Resolve-Path -LiteralPath $AnchorPath).Path
    while ($directory) {
        $candidateRoot = Join-Path $directory '.tmp\drawio'
        if (Test-Path -LiteralPath $candidateRoot) {
            $candidates = @(Get-ChildItem -LiteralPath $candidateRoot -Filter 'draw.io.exe' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $match = [regex]::Match((Split-Path -Leaf $_.DirectoryName), '^(?:app|desktop)-(?<version>\d+(?:\.\d+){1,3})$')
                $version = [version]'0.0'
                if ($match.Success) { $version = [version]$match.Groups['version'].Value }
                [pscustomobject]@{ Path=$_.FullName; Version=$version }
            } | Sort-Object Version,Path -Descending)
            if ($candidates.Count -gt 0) { return [pscustomobject]@{ Path=$candidates[0].Path; Version=[string]$candidates[0].Version } }
        }
        $parent = Split-Path -Parent $directory
        if (-not $parent -or $parent -eq $directory) { break }
        $directory = $parent
    }
    throw 'Draw.io executable was not provided and could not be discovered'
}

function Export-Format {
    param(
        [string]$Executable,
        [string]$InputPath,
        [string]$Format,
        [string]$OutputPath,
        [double]$Scale,
        [ValidateSet('page','diagram')][string]$Size = 'page',
        [double]$Border = 0,
        [int]$Width = 0,
        [int]$Height = 0,
        [string]$Theme
    )

    if (-not $OutputPath) { return $null }
    $directory = Split-Path -Parent $OutputPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (-not $directory) { $directory = (Get-Location).Path }
    $extension = [System.IO.Path]::GetExtension($OutputPath)
    if (-not $extension) { $extension = '.' + $Format }
    $temporaryPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileNameWithoutExtension($OutputPath) + '.' + [guid]::NewGuid().ToString('N') + $extension)
    $arguments = @('-x', '-f', $Format)
    if ($Format -eq 'png') { $arguments += @('-s', [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Scale)) }
    $arguments += @('--size', $Size)
    if ($Size -eq 'diagram') { $arguments += @('--border', [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Border)) }
    if ($Width -gt 0) { $arguments += @('--width', [string]$Width) }
    if ($Height -gt 0) { $arguments += @('--height', [string]$Height) }
    if ($Theme) { $arguments += @('--theme', $Theme) }
    $arguments += @('-o', $temporaryPath, $InputPath)
    $process = Start-Process -FilePath $Executable -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Draw.io $Format export failed with exit code $($process.ExitCode)" }
    if (-not (Test-Path -LiteralPath $temporaryPath -PathType Leaf) -or (Get-Item -LiteralPath $temporaryPath).Length -eq 0) {
        throw "Draw.io $Format export did not produce a fresh file: $OutputPath"
    }
    $temporaryPath
}

function New-ExportDrawio {
    param(
        [System.Xml.XmlDocument]$Canonical,
        [string]$Path
    )

    [xml]$wrapper = '<mxfile host="app.diagrams.net" compressed="false"><diagram id="export-page" name="Export"></diagram></mxfile>'
    $model = $wrapper.ImportNode($Canonical.DocumentElement, $true)
    [void]$wrapper.mxfile.diagram.AppendChild($model)
    [System.IO.File]::WriteAllText($Path, $wrapper.OuterXml + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Expand-Diagram {
    param([System.Xml.XmlElement]$Diagram)
    $embedded = $Diagram.SelectSingleNode('./mxGraphModel')
    if ($embedded) { return $embedded.OuterXml }
    $payload = ([string]$Diagram.InnerText).Trim()
    if (-not $payload) { throw "Diagram page has no mxGraphModel payload: $($Diagram.id)" }
    $bytes = [Convert]::FromBase64String($payload)
    $input = [System.IO.MemoryStream]::new($bytes)
    $deflate = [System.IO.Compression.DeflateStream]::new($input, [System.IO.Compression.CompressionMode]::Decompress)
    $output = [System.IO.MemoryStream]::new()
    try {
        $deflate.CopyTo($output)
        [uri]::UnescapeDataString([System.Text.Encoding]::UTF8.GetString($output.ToArray()))
    }
    finally {
        $output.Dispose()
        $deflate.Dispose()
        $input.Dispose()
    }
}

function Get-NodeSignature {
    param([System.Xml.XmlNode]$Node)
    if ($Node.NodeType -eq [System.Xml.XmlNodeType]::Text -or $Node.NodeType -eq [System.Xml.XmlNodeType]::CDATA) {
        if ([string]::IsNullOrWhiteSpace($Node.Value)) { return '' }
        return '#text=' + $Node.Value
    }
    if ($Node.NodeType -ne [System.Xml.XmlNodeType]::Element) { return '' }
    $attributes = @($Node.Attributes | Sort-Object Name | ForEach-Object { $_.Name + '=' + $_.Value }) -join '|'
    $children = @($Node.ChildNodes | ForEach-Object { Get-NodeSignature $_ } | Where-Object { $_ }) -join ''
    '<' + $Node.Name + '|' + $attributes + '>' + $children + '</' + $Node.Name + '>'
}

function Assert-WrapperParity {
    param(
        [System.Xml.XmlDocument]$Canonical,
        [string]$WrapperPath,
        [string]$RequestedPageId
    )
    [xml]$wrapper = Get-Content -LiteralPath $WrapperPath -Raw -Encoding UTF8
    $diagrams = @($wrapper.SelectNodes('/mxfile/diagram'))
    if ($diagrams.Count -eq 0) { throw "No diagram pages found: $WrapperPath" }
    if ($RequestedPageId) {
        $selected = @($diagrams | Where-Object { [string]$_.id -eq $RequestedPageId })
        if ($selected.Count -ne 1) { throw "PageId not found or not unique: $RequestedPageId" }
        $diagram = $selected[0]
    }
    else {
        if ($diagrams.Count -ne 1) {
            $available = @($diagrams | ForEach-Object { "$($_.id)=$($_.name)" }) -join ', '
            throw "PageId is required for a multi-page file. Available pages: $available"
        }
        $diagram = $diagrams[0]
    }
    [xml]$embedded = Expand-Diagram $diagram
    if ((Get-NodeSignature $Canonical.DocumentElement) -ne (Get-NodeSignature $embedded.DocumentElement)) {
        throw "Canonical XML does not match selected Draw.io page: $($diagram.id)"
    }
    [pscustomobject]@{ Id=[string]$diagram.id; Name=[string]$diagram.name }
}

function Set-PngDensity {
    param([string]$Path,[int]$DensityPpi)
    Add-Type -AssemblyName System.Drawing
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $source = [System.Drawing.Image]::FromFile($resolved)
    $replacement = $resolved + '.' + [guid]::NewGuid().ToString('N') + '.png'
    try {
        $bitmap = [System.Drawing.Bitmap]::new($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $bitmap.SetResolution([single]$DensityPpi,[single]$DensityPpi)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $destination = [System.Drawing.Rectangle]::new(0,0,$source.Width,$source.Height)
                $graphics.DrawImage($source,$destination,0,0,$source.Width,$source.Height,[System.Drawing.GraphicsUnit]::Pixel)
            }
            finally { $graphics.Dispose() }
            $bitmap.Save($replacement,[System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $bitmap.Dispose() }
    }
    finally { $source.Dispose() }
    [System.IO.File]::Delete($resolved)
    [System.IO.File]::Move($replacement,$resolved)
}

function Assert-WordPng {
    param([string]$Path,[int]$MaximumWidth,[int]$MaximumHeight,[string]$LimitingDimension,[int]$DensityPpi)
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Path).Path)
    try {
        if ($image.Width -gt $MaximumWidth+2 -or $image.Height -gt $MaximumHeight+2) { throw "Word PNG exceeds target frame: $($image.Width)x$($image.Height)" }
        if ($LimitingDimension -eq 'width' -and [math]::Abs($image.Width-$MaximumWidth) -gt 2) { throw "Word PNG width is not frame-limited: $($image.Width)" }
        if ($LimitingDimension -eq 'height' -and [math]::Abs($image.Height-$MaximumHeight) -gt 2) { throw "Word PNG height is not frame-limited: $($image.Height)" }
        if ([math]::Abs($image.HorizontalResolution-$DensityPpi) -gt 1.0 -or [math]::Abs($image.VerticalResolution-$DensityPpi) -gt 1.0) { throw "Word PNG density is invalid: $($image.HorizontalResolution)x$($image.VerticalResolution)" }
    }
    finally { $image.Dispose() }
}

function Assert-PdfPage {
    param(
        [string]$Path,
        [double]$PageWidth,
        [double]$PageHeight
    )
    $text = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($Path))
    $pageCount = [regex]::Matches($text, '/Type\s*/Page(?!s)\b').Count
    if ($pageCount -ne 1) { throw "PDF must contain exactly one page: $pageCount" }
    $matches = [regex]::Matches($text, '/MediaBox\s*\[\s*(-?(?:\d+(?:\.\d+)?|\.\d+))\s+(-?(?:\d+(?:\.\d+)?|\.\d+))\s+(-?(?:\d+(?:\.\d+)?|\.\d+))\s+(-?(?:\d+(?:\.\d+)?|\.\d+))\s*\]')
    if ($matches.Count -eq 0) { throw 'PDF MediaBox not found' }
    $box = $matches[0]
    $width = [double]::Parse($box.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture) - [double]::Parse($box.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    $height = [double]::Parse($box.Groups[4].Value, [System.Globalization.CultureInfo]::InvariantCulture) - [double]::Parse($box.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    $expectedWidth = $PageWidth * 0.72
    $expectedHeight = $PageHeight * 0.72
    if ([math]::Abs($width - $expectedWidth) -gt 2.0 -or [math]::Abs($height - $expectedHeight) -gt 2.0) {
        throw "PDF MediaBox does not match canonical page: $width x $height"
    }
}

function Install-TransactionalBundle {
    param(
        [object[]]$Items
    )

    $destinationKeys = @($Items | ForEach-Object { [System.IO.Path]::GetFullPath([string]$_.DestinationPath).ToUpperInvariant() })
    if (@($destinationKeys | Sort-Object -Unique).Count -ne $destinationKeys.Count) {
        throw 'Requested export destinations must be unique'
    }

    $attempted = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($item in $Items) {
            $destinationPath = [System.IO.Path]::GetFullPath([string]$item.DestinationPath)
            $destinationDirectory = Split-Path -Parent $destinationPath
            if (-not (Test-Path -LiteralPath $destinationDirectory)) { New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null }
            $hadExisting = Test-Path -LiteralPath $destinationPath -PathType Leaf
            $backupPath = if ($hadExisting) { Join-Path $destinationDirectory ('.' + [System.IO.Path]::GetFileName($destinationPath) + '.' + [guid]::NewGuid().ToString('N') + '.bak') } else { $null }
            $record = [pscustomobject]@{
                StagedPath = [string]$item.StagedPath
                DestinationPath = $destinationPath
                BackupPath = $backupPath
                HadExisting = $hadExisting
            }
            $attempted.Add($record)
            if ($hadExisting) {
                [System.IO.File]::Replace($record.StagedPath, $destinationPath, $backupPath, $true)
            }
            else {
                [System.IO.File]::Move($record.StagedPath, $destinationPath)
            }
        }
    }
    catch {
        $commitFailure = $_.Exception.Message
        $rollbackFailures = [System.Collections.Generic.List[string]]::new()
        for ($index = $attempted.Count - 1; $index -ge 0; $index--) {
            $record = $attempted[$index]
            try {
                if ($record.HadExisting) {
                    if (Test-Path -LiteralPath $record.BackupPath -PathType Leaf) {
                        if (Test-Path -LiteralPath $record.DestinationPath -PathType Leaf) {
                            $rollbackDiscardPath = Join-Path (Split-Path -Parent $record.DestinationPath) ('.' + [System.IO.Path]::GetFileName($record.DestinationPath) + '.' + [guid]::NewGuid().ToString('N') + '.rollback')
                            [System.IO.File]::Replace($record.BackupPath, $record.DestinationPath, $rollbackDiscardPath, $true)
                            if (Test-Path -LiteralPath $rollbackDiscardPath -PathType Leaf) { [System.IO.File]::Delete($rollbackDiscardPath) }
                        }
                        else {
                            [System.IO.File]::Move($record.BackupPath, $record.DestinationPath)
                        }
                    }
                    elseif (-not (Test-Path -LiteralPath $record.StagedPath -PathType Leaf)) {
                        throw "Backup is unavailable: $($record.BackupPath)"
                    }
                }
                elseif (-not (Test-Path -LiteralPath $record.StagedPath -PathType Leaf) -and (Test-Path -LiteralPath $record.DestinationPath -PathType Leaf)) {
                    [System.IO.File]::Delete($record.DestinationPath)
                }
            }
            catch {
                $rollbackFailures.Add("$($record.DestinationPath): $($_.Exception.Message)")
            }
        }
        foreach ($record in $attempted) {
            if ($record.BackupPath -and (Test-Path -LiteralPath $record.BackupPath -PathType Leaf)) {
                try { [System.IO.File]::Delete($record.BackupPath) }
                catch { $rollbackFailures.Add("$($record.BackupPath): $($_.Exception.Message)") }
            }
        }
        if ($rollbackFailures.Count -gt 0) {
            throw "Bundle commit failed: $commitFailure. Rollback failed: $($rollbackFailures -join '; ')"
        }
        throw "Bundle commit failed; previous bundle restored: $commitFailure"
    }

    foreach ($record in $attempted) {
        if ($record.BackupPath -and (Test-Path -LiteralPath $record.BackupPath -PathType Leaf)) {
            try { [System.IO.File]::Delete($record.BackupPath) }
            catch { Write-Warning "Committed bundle backup could not be removed: $($record.BackupPath): $($_.Exception.Message)" }
        }
    }
}

function Get-RelativeArtifactPath {
    param(
        [string]$BaseDirectory,
        [string]$TargetPath
    )
    $basePath = [System.IO.Path]::GetFullPath($BaseDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $targetResolved = [System.IO.Path]::GetFullPath($TargetPath)
    if ([System.IO.Path]::GetPathRoot($basePath) -ne [System.IO.Path]::GetPathRoot($targetResolved)) {
        throw "Artifact manifest cannot represent a path on another volume: $targetResolved"
    }
    $baseUri = [uri]$basePath
    $targetUri = [uri]$targetResolved
    [uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Assert-StagedManifest {
    param(
        [string]$Path,
        [object[]]$Artifacts,
        [double]$PageWidth,
        [double]$PageHeight
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "Artifact manifest staging failed: $Path"
    }
    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 2) { throw "Unsupported artifact manifest schema: $($manifest.schemaVersion)" }
    if (-not [string]$manifest.renderer.name -or -not [string]$manifest.renderer.version) { throw 'Artifact manifest renderer provenance is incomplete' }
    if ([math]::Abs([double]$manifest.page.width - $PageWidth) -gt 0.01 -or [math]::Abs([double]$manifest.page.height - $PageHeight) -gt 0.01) { throw 'Artifact manifest page dimensions are invalid' }
    $actualArtifacts = @($manifest.artifacts)
    if ($actualArtifacts.Count -ne $Artifacts.Count) { throw 'Artifact manifest entry count is invalid' }
    foreach ($artifact in $Artifacts) {
        $matches = @($actualArtifacts | Where-Object { [string]$_.role -eq [string]$artifact.Role })
        if ($matches.Count -ne 1) { throw "Artifact manifest role is missing or duplicated: $($artifact.Role)" }
        $expectedHash = (Get-FileHash -LiteralPath $artifact.HashPath -Algorithm SHA256).Hash
        if ([string]$matches[0].sha256 -ne $expectedHash) { throw "Artifact manifest hash is invalid: $($artifact.Role)" }
        if ([string]$matches[0].path -ne [string]$artifact.RelativePath) { throw "Artifact manifest path is invalid: $($artifact.Role)" }
    }
}

if (-not $SvgPath -and -not $PngPath -and -not $WordPngPath -and -not $PdfPath) { throw 'At least one output path is required' }
if (-not (Test-Path -LiteralPath $CanonicalPath -PathType Leaf)) { throw "Canonical XML not found: $CanonicalPath" }
if (-not (Test-Path -LiteralPath $DrawioPath -PathType Leaf)) { throw "Draw.io file not found: $DrawioPath" }
if (-not (Test-Path -LiteralPath $QualityProfilePath -PathType Leaf)) { throw "Quality profile not found: $QualityProfilePath" }

[xml]$canonical = Get-Content -LiteralPath $CanonicalPath -Raw -Encoding UTF8
$profile = Get-Content -LiteralPath $QualityProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$scale = [double]$profile.export.pngScale
$word = $profile.delivery.word
$page = Assert-WrapperParity $canonical $DrawioPath $PageId
$resolvedExecutable = Resolve-DrawioExecutable $DrawioExecutable $DrawioPath
$executable = $resolvedExecutable.Path
$pageWidth = [double]$canonical.mxGraphModel.pageWidth
$pageHeight = [double]$canonical.mxGraphModel.pageHeight
$scratchRoot = Join-Path (Get-Location).Path '.tmp'
if (-not (Test-Path -LiteralPath $scratchRoot)) { New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null }
$workingDrawio = Join-Path $scratchRoot ('drawio-builder-export-' + [guid]::NewGuid().ToString('N') + '.drawio')
$temporaryOutputs = [System.Collections.Generic.List[string]]::new()
$bundleItems = [System.Collections.Generic.List[object]]::new()
try {
    New-ExportDrawio $canonical $workingDrawio
    $svgTemporary = Export-Format $executable $workingDrawio 'svg' $SvgPath $scale -Size page
    if ($svgTemporary) {
        $temporaryOutputs.Add($svgTemporary)
        [xml]$svg = Get-Content -LiteralPath $svgTemporary -Raw -Encoding UTF8
        $viewBox = @(([string]$svg.svg.viewBox).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { [double]$_ })
        if ($viewBox.Count -ne 4) { throw "SVG viewBox is invalid: $($svg.svg.viewBox)" }
        $overflow = $viewBox[0] -lt -1.0 -or $viewBox[1] -lt -1.0 -or $viewBox[2] -gt ($pageWidth + 1.0) -or $viewBox[3] -gt ($pageHeight + 1.0)
        if ($overflow) { throw "SVG content exceeds canonical page bounds: $($svg.svg.viewBox). Move page-edge shapes, labels, or routes inward" }
        if ([math]::Abs($viewBox[0]) -gt 1.0 -or [math]::Abs($viewBox[1]) -gt 1.0 -or [math]::Abs($viewBox[2] - $pageWidth) -gt 1.0 -or [math]::Abs($viewBox[3] - $pageHeight) -gt 1.0) {
            throw "SVG page export did not establish canonical bounds: $($svg.svg.viewBox)"
        }
    }

    $pngTemporary = Export-Format $executable $workingDrawio 'png' $PngPath $scale -Size page
    if ($pngTemporary) {
        $temporaryOutputs.Add($pngTemporary)
        Add-Type -AssemblyName System.Drawing
        $image = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $pngTemporary).Path)
        $expectedWidth = [math]::Round(($pageWidth + 1.0) * $scale)
        $expectedHeight = [math]::Round(($pageHeight + 1.0) * $scale)
        try {
            if ([math]::Abs($image.Width - $expectedWidth) -gt 2 -or [math]::Abs($image.Height - $expectedHeight) -gt 2) {
                throw "PNG dimensions do not match canonical page and scale: $($image.Width)x$($image.Height)"
            }
        }
        finally { $image.Dispose() }
    }

    $wordPngTemporary = $null
    if ($WordPngPath) {
        $compositionOutput = @(& (Join-Path $PSScriptRoot 'audit_drawio_composition.ps1') -SourcePath $CanonicalPath -QualityProfilePath $QualityProfilePath) -join "`n"
        $composition = $compositionOutput | ConvertFrom-Json
        if ([int]$composition.ErrorCount -gt 0) { throw 'Word PNG export requires a passing composition-word-fit audit' }
        $maximumWidth = [int][math]::Round([double]$word.frameWidthMm/25.4*[double]$word.densityPpi)
        $maximumHeight = [int][math]::Round([double]$word.frameHeightMm/25.4*[double]$word.densityPpi)
        $cropAspect = [double]$composition.Crop.Aspect
        $frameAspect = [double]$maximumWidth/[double]$maximumHeight
        $limitingDimension = if ($cropAspect -ge $frameAspect) { 'width' } else { 'height' }
        $wordWidth = if ($limitingDimension -eq 'width') { $maximumWidth } else { 0 }
        $wordHeight = if ($limitingDimension -eq 'height') { $maximumHeight } else { 0 }
        $wordPngTemporary = Export-Format $executable $workingDrawio 'png' $WordPngPath 1.0 -Size diagram -Border ([double]$word.cropBorder) -Width $wordWidth -Height $wordHeight -Theme ([string]$word.theme)
        $temporaryOutputs.Add($wordPngTemporary)
        Set-PngDensity $wordPngTemporary ([int]$word.densityPpi)
        Assert-WordPng $wordPngTemporary $maximumWidth $maximumHeight $limitingDimension ([int]$word.densityPpi)
    }

    $pdfTemporary = Export-Format $executable $workingDrawio 'pdf' $PdfPath $scale -Size page
    if ($pdfTemporary) {
        $temporaryOutputs.Add($pdfTemporary)
        Assert-PdfPage $pdfTemporary $pageWidth $pageHeight
    }

    if ($svgTemporary) { $bundleItems.Add([pscustomobject]@{ StagedPath=$svgTemporary; DestinationPath=$SvgPath }) }
    if ($pngTemporary) { $bundleItems.Add([pscustomobject]@{ StagedPath=$pngTemporary; DestinationPath=$PngPath }) }
    if ($wordPngTemporary) { $bundleItems.Add([pscustomobject]@{ StagedPath=$wordPngTemporary; DestinationPath=$WordPngPath }) }
    if ($pdfTemporary) { $bundleItems.Add([pscustomobject]@{ StagedPath=$pdfTemporary; DestinationPath=$PdfPath }) }

    if ($ManifestPath) {
        $manifestDirectory = Split-Path -Parent $ManifestPath
        if (-not $manifestDirectory) { $manifestDirectory = (Get-Location).Path }
        if (-not (Test-Path -LiteralPath $manifestDirectory)) { New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null }
        $artifactSources = [System.Collections.Generic.List[object]]::new()
        $artifactSources.Add([pscustomobject]@{ Role='canonical'; HashPath=$CanonicalPath; RelativePath=(Get-RelativeArtifactPath $manifestDirectory $CanonicalPath) })
        $artifactSources.Add([pscustomobject]@{ Role='wrapper'; HashPath=$DrawioPath; RelativePath=(Get-RelativeArtifactPath $manifestDirectory $DrawioPath) })
        if ($SvgPath) { $artifactSources.Add([pscustomobject]@{ Role='svg'; HashPath=$svgTemporary; RelativePath=(Get-RelativeArtifactPath $manifestDirectory $SvgPath) }) }
        if ($PngPath) { $artifactSources.Add([pscustomobject]@{ Role='png'; HashPath=$pngTemporary; RelativePath=(Get-RelativeArtifactPath $manifestDirectory $PngPath) }) }
        if ($WordPngPath) { $artifactSources.Add([pscustomobject]@{ Role='word-png'; HashPath=$wordPngTemporary; RelativePath=(Get-RelativeArtifactPath $manifestDirectory $WordPngPath) }) }
        if ($PdfPath) { $artifactSources.Add([pscustomobject]@{ Role='pdf'; HashPath=$pdfTemporary; RelativePath=(Get-RelativeArtifactPath $manifestDirectory $PdfPath) }) }
        $artifacts = @($artifactSources | ForEach-Object { [pscustomobject]@{ role=$_.Role; path=$_.RelativePath; sha256=(Get-FileHash -LiteralPath $_.HashPath -Algorithm SHA256).Hash } })
        $manifest = [ordered]@{
            schemaVersion = 2
            page = [ordered]@{ id=$page.Id; width=$pageWidth; height=$pageHeight }
            renderer = [ordered]@{ name='draw.io'; version=[string]$resolvedExecutable.Version }
            delivery = [ordered]@{ frameWidthMm=[double]$word.frameWidthMm; frameHeightMm=[double]$word.frameHeightMm; densityPpi=[int]$word.densityPpi; minimumEffectiveFontPoints=[double]$word.minimumEffectiveFontPoints; cropBorder=[double]$word.cropBorder }
            artifacts = @($artifacts)
        }
        $manifestTemporary = Join-Path $manifestDirectory ('.' + [System.IO.Path]::GetFileName($ManifestPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($manifestTemporary, ($manifest | ConvertTo-Json -Depth 6) + "`n", [System.Text.UTF8Encoding]::new($false))
        $temporaryOutputs.Add($manifestTemporary)
        Assert-StagedManifest $manifestTemporary @($artifactSources) $pageWidth $pageHeight
        $bundleItems.Add([pscustomobject]@{ StagedPath=$manifestTemporary; DestinationPath=$ManifestPath })
    }

    Install-TransactionalBundle @($bundleItems)
}
finally {
    if (Test-Path -LiteralPath $workingDrawio) { [System.IO.File]::Delete($workingDrawio) }
    foreach ($temporaryOutput in @($temporaryOutputs)) {
        if (Test-Path -LiteralPath $temporaryOutput) { [System.IO.File]::Delete($temporaryOutput) }
    }
}

[pscustomobject]@{
    Canonical = $CanonicalPath
    Drawio = $DrawioPath
    Executable = $executable
    ExecutableVersion = $resolvedExecutable.Version
    PageId = $page.Id
    PageName = $page.Name
    Svg = $SvgPath
    Png = $PngPath
    WordPng = $WordPngPath
    Pdf = $PdfPath
    Manifest = $ManifestPath
    Scale = $scale
} | ConvertTo-Json
