param(
    [Parameter(Mandatory = $true)][string]$PngPath,
    [Parameter(Mandatory = $true)][string]$SvgPath,
    [Parameter(Mandatory = $true)][string]$ValidationReportPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$ReportPath,
    [double]$Padding = 24,
    [double]$MinimumSize = 160
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\Svg.Geometry.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Svg.Ink.psm1') -Force

foreach ($path in @($PngPath, $SvgPath, $ValidationReportPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Input file not found: $path" }
}
$PngPath = (Resolve-Path -LiteralPath $PngPath).Path
$SvgPath = (Resolve-Path -LiteralPath $SvgPath).Path
$ValidationReportPath = (Resolve-Path -LiteralPath $ValidationReportPath).Path
if ($Padding -lt 0 -or $MinimumSize -le 0) { throw 'Padding must be non-negative and MinimumSize must be positive' }

$report = Get-Content -LiteralPath $ValidationReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$issues = [System.Collections.Generic.List[object]]::new()
if ($report.PSObject.Properties.Name -contains 'Gates') {
    foreach ($gate in @($report.Gates)) {
        foreach ($issue in @($gate.Result.Issues)) {
            if ($null -ne $issue) { $issues.Add([pscustomobject]@{ Gate=[string]$gate.Name; Issue=$issue }) }
        }
    }
}
elseif ($report.PSObject.Properties.Name -contains 'Issues') {
    foreach ($issue in @($report.Issues)) {
        if ($null -ne $issue) { $issues.Add([pscustomobject]@{ Gate='audit'; Issue=$issue }) }
    }
}
else { throw 'Validation report contains neither Gates nor Issues' }

[xml]$svg = Get-Content -LiteralPath $SvgPath -Raw -Encoding UTF8
$namespace = [System.Xml.XmlNamespaceManager]::new($svg.NameTable)
$namespace.AddNamespace('s', 'http://www.w3.org/2000/svg')
$root = $svg.DocumentElement
$viewBox = @(([string]$root.viewBox -split '[,\s]+' | Where-Object { $_ }) | ForEach-Object { [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture) })
if ($viewBox.Count -ne 4 -or $viewBox[2] -le 0 -or $viewBox[3] -le 0) { throw 'SVG viewBox is invalid' }

Add-Type -AssemblyName System.Drawing
$bitmap = [System.Drawing.Bitmap]::new((Resolve-Path -LiteralPath $PngPath).Path)
try {
    $scaleX = $bitmap.Width / $viewBox[2]
    $scaleY = $bitmap.Height / $viewBox[3]
    if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
    $OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $groups = @($svg.SelectNodes('//s:g[@data-cell-id]', $namespace))
    $results = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($entry in $issues) {
        $issue = $entry.Issue
        $index++
        $centerX = $null
        $centerY = $null
        if ($null -ne $issue.Coordinates -and $issue.Coordinates.PSObject.Properties.Name -contains 'X' -and $issue.Coordinates.PSObject.Properties.Name -contains 'Y') {
            $centerX = [double]$issue.Coordinates.X
            $centerY = [double]$issue.Coordinates.Y
        }
        $group = $groups | Where-Object { [string]$_.GetAttribute('data-cell-id') -eq [string]$issue.Element } | Select-Object -First 1
        $ink = if ($group) { Get-SvgLabelInkBounds -Group $group -Namespace $namespace } else { $null }
        if ($null -ne $centerX -and $null -ne $centerY) {
            $left = $centerX - $MinimumSize / 2
            $top = $centerY - $MinimumSize / 2
            $right = $centerX + $MinimumSize / 2
            $bottom = $centerY + $MinimumSize / 2
        }
        elseif ($ink) {
            $width = [math]::Max($MinimumSize, $ink.Right - $ink.Left + 2 * $Padding)
            $height = [math]::Max($MinimumSize, $ink.Bottom - $ink.Top + 2 * $Padding)
            $centerX = ($ink.Left + $ink.Right) / 2
            $centerY = ($ink.Top + $ink.Bottom) / 2
            $left = $centerX - $width / 2
            $top = $centerY - $height / 2
            $right = $centerX + $width / 2
            $bottom = $centerY + $height / 2
        }
        else {
            $results.Add([pscustomobject]@{ Gate=$entry.Gate; Element=[string]$issue.Element; Type=[string]$issue.Type; Status='SKIPPED'; Reason='No rendered coordinates or label ink bounds' })
            continue
        }
        $left = [math]::Max($viewBox[0], $left - $Padding)
        $top = [math]::Max($viewBox[1], $top - $Padding)
        $right = [math]::Min($viewBox[0] + $viewBox[2], $right + $Padding)
        $bottom = [math]::Min($viewBox[1] + $viewBox[3], $bottom + $Padding)
        $pixelLeft = [math]::Max(0, [math]::Floor(($left - $viewBox[0]) * $scaleX))
        $pixelTop = [math]::Max(0, [math]::Floor(($top - $viewBox[1]) * $scaleY))
        $pixelRight = [math]::Min($bitmap.Width, [math]::Ceiling(($right - $viewBox[0]) * $scaleX))
        $pixelBottom = [math]::Min($bitmap.Height, [math]::Ceiling(($bottom - $viewBox[1]) * $scaleY))
        $rectangle = [System.Drawing.Rectangle]::FromLTRB($pixelLeft, $pixelTop, $pixelRight, $pixelBottom)
        if ($rectangle.Width -le 0 -or $rectangle.Height -le 0) { throw "Computed crop is empty for issue $index" }
        $safeElement = ([string]$issue.Element -replace '[^A-Za-z0-9_.-]', '_')
        $safeType = ([string]$issue.Type -replace '[^A-Za-z0-9_.-]', '_')
        $fileName = '{0:D3}-{1}-{2}.png' -f $index, $safeElement, $safeType
        $destination = Join-Path $OutputDirectory $fileName
        $crop = $bitmap.Clone($rectangle, $bitmap.PixelFormat)
        try { $crop.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $crop.Dispose() }
        $results.Add([pscustomobject]@{ Gate=$entry.Gate; Element=[string]$issue.Element; Type=[string]$issue.Type; Status='EXPORTED'; Path=$destination; PixelBounds=[pscustomobject]@{ X=$rectangle.X; Y=$rectangle.Y; Width=$rectangle.Width; Height=$rectangle.Height } })
    }
}
finally { $bitmap.Dispose() }

$result = [pscustomobject]@{
    SchemaVersion = 1
    Png = $PngPath
    Svg = $SvgPath
    Report = $ValidationReportPath
    ValidationReportSha256 = (Get-FileHash -LiteralPath $ValidationReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    IssueCount = $issues.Count
    ExportedCount = @($results | Where-Object { $_.Status -eq 'EXPORTED' }).Count
    SkippedCount = @($results | Where-Object { $_.Status -eq 'SKIPPED' }).Count
    Crops = @($results)
}
$resultJson = $result | ConvertTo-Json -Depth 8
if ($ReportPath) {
    $reportParent = Split-Path -Parent $ReportPath
    if ($reportParent -and -not (Test-Path -LiteralPath $reportParent)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    [System.IO.File]::WriteAllText($ReportPath, $resultJson, [System.Text.UTF8Encoding]::new($false))
}
$resultJson
if ($result.SkippedCount -gt 0) { exit 2 }
