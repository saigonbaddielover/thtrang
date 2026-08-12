param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$QualityProfilePath
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$issues = [System.Collections.Generic.List[object]]::new()

function Convert-ToNumber {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 0.0 }
    [double]::Parse($Value, $Invariant)
}

function Get-StyleMap {
    param([string]$Style)
    $map = @{}
    foreach ($part in $Style.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $pair = $part.Split('=', 2)
        if ($pair.Count -eq 2) { $map[$pair[0]] = $pair[1] }
        else { $map[$part] = '1' }
    }
    $map
}

function Get-AbsoluteGeometry {
    param([System.Xml.XmlElement]$Cell,[hashtable]$Cells,[hashtable]$Cache)
    if ($Cache.ContainsKey([string]$Cell.id)) { return $Cache[[string]$Cell.id] }
    $geometry = $Cell.SelectSingleNode('./mxGeometry')
    $x = Convert-ToNumber ([string]$geometry.x)
    $y = Convert-ToNumber ([string]$geometry.y)
    $width = Convert-ToNumber ([string]$geometry.width)
    $height = Convert-ToNumber ([string]$geometry.height)
    if ($Cell.parent -and $Cells.ContainsKey([string]$Cell.parent) -and $Cells[[string]$Cell.parent].vertex -eq '1') {
        $parentGeometry = Get-AbsoluteGeometry $Cells[[string]$Cell.parent] $Cells $Cache
        $x += $parentGeometry.X
        $y += $parentGeometry.Y
    }
    $result = [pscustomobject]@{ X=$x; Y=$y; Width=$width; Height=$height; Right=$x+$width; Bottom=$y+$height }
    $Cache[[string]$Cell.id] = $result
    $result
}

function Add-Issue {
    param([string]$Severity,[string]$Type,[string]$Element,[string]$Detail,[object]$Coordinates,[string]$Evidence,[string]$RepairClass)
    $issues.Add([pscustomobject]@{ Severity=$Severity; Type=$Type; Element=$Element; Detail=$Detail; Coordinates=$Coordinates; Evidence=$Evidence; RepairClass=$RepairClass })
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Canonical XML not found: $SourcePath" }
if (-not (Test-Path -LiteralPath $QualityProfilePath -PathType Leaf)) { throw "Quality profile not found: $QualityProfilePath" }

[xml]$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
$quality = Get-Content -LiteralPath $QualityProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$pageWidth = Convert-ToNumber ([string]$source.mxGraphModel.pageWidth)
$pageHeight = Convert-ToNumber ([string]$source.mxGraphModel.pageHeight)
$cells = @{}
foreach ($cell in @($source.SelectNodes('//mxCell'))) { $cells[[string]$cell.id] = $cell }
$cache = @{}
$bounds = [System.Collections.Generic.List[object]]::new()
$bodyFonts = [System.Collections.Generic.List[double]]::new()
$edgeFonts = [System.Collections.Generic.List[double]]::new()

foreach ($cell in @($source.SelectNodes('//mxCell[@vertex="1"]'))) {
    $style = Get-StyleMap ([string]$cell.style)
    $isTitle = [string]$cell.id -eq 'title' -or ($style.ContainsKey('text') -and $style.ContainsKey('fontStyle') -and [string]$style.fontStyle -match '1')
    if ($isTitle) {
        Add-Issue 'ERROR' 'embedded-title' ([string]$cell.id) 'Word-ready figures must use an external heading or caption' $null ([string]$cell.value) 'remove-embedded-title'
        continue
    }
    $geometry = Get-AbsoluteGeometry $cell $cells $cache
    if ($geometry.Width -le 0 -or $geometry.Height -le 0) { continue }
    $bounds.Add($geometry)
    if ($geometry.X -lt 0 -or $geometry.Y -lt 0 -or $geometry.Right -gt $pageWidth -or $geometry.Bottom -gt $pageHeight) {
        Add-Issue 'ERROR' 'page-overflow' ([string]$cell.id) 'Rendered vertex exceeds canonical page bounds' $geometry "page=$pageWidth x $pageHeight" 'relayout-page-edge'
    }
    if ($style.ContainsKey('fontSize')) {
        $fontSize = Convert-ToNumber ([string]$style.fontSize)
        if ($fontSize -gt 0) { $bodyFonts.Add($fontSize) }
    }
}

foreach ($edge in @($source.SelectNodes('//mxCell[@edge="1"]'))) {
    $style = Get-StyleMap ([string]$edge.style)
    if ($style.ContainsKey('fontSize') -and -not [string]::IsNullOrWhiteSpace([string]$edge.value)) {
        $fontSize = Convert-ToNumber ([string]$style.fontSize)
        if ($fontSize -gt 0) { $edgeFonts.Add($fontSize) }
    }
    foreach ($point in @($edge.SelectNodes('./mxGeometry/Array[@as="points"]/mxPoint'))) {
        $x = Convert-ToNumber ([string]$point.x)
        $y = Convert-ToNumber ([string]$point.y)
        $bounds.Add([pscustomobject]@{ X=$x; Y=$y; Width=0.0; Height=0.0; Right=$x; Bottom=$y })
        if ($x -lt 0 -or $y -lt 0 -or $x -gt $pageWidth -or $y -gt $pageHeight) {
            Add-Issue 'ERROR' 'page-overflow' ([string]$edge.id) 'Connector waypoint exceeds canonical page bounds' ([pscustomobject]@{X=$x;Y=$y}) "page=$pageWidth x $pageHeight" 'reroute-page-edge'
        }
    }
}

if ($bounds.Count -eq 0) {
    Add-Issue 'ERROR' 'empty-composition' '' 'No visible content bounds were found' $null $SourcePath 'restore-content'
    $content = [pscustomobject]@{ Left=0.0; Top=0.0; Right=0.0; Bottom=0.0; Width=0.0; Height=0.0 }
}
else {
    $left = [double]($bounds | Measure-Object X -Minimum).Minimum
    $top = [double]($bounds | Measure-Object Y -Minimum).Minimum
    $right = [double]($bounds | Measure-Object Right -Maximum).Maximum
    $bottom = [double]($bounds | Measure-Object Bottom -Maximum).Maximum
    $content = [pscustomobject]@{ Left=$left; Top=$top; Right=$right; Bottom=$bottom; Width=$right-$left; Height=$bottom-$top }
}

$word = $quality.delivery.word
$border = [double]$word.cropBorder
$cropWidth = $content.Width + 2.0 * $border
$cropHeight = $content.Height + 2.0 * $border
$frameWidth = [double]$word.frameWidthMm * 96.0 / 25.4
$frameHeight = [double]$word.frameHeightMm * 96.0 / 25.4
$placedScale = if ($cropWidth -gt 0 -and $cropHeight -gt 0) { [math]::Min($frameWidth / $cropWidth, $frameHeight / $cropHeight) } else { 0.0 }
$bodyMinimum = if ($bodyFonts.Count -gt 0) { [double]($bodyFonts | Measure-Object -Minimum).Minimum } else { [double]$quality.fonts.bodyMinimum }
$edgeMinimum = if ($edgeFonts.Count -gt 0) { [double]($edgeFonts | Measure-Object -Minimum).Minimum } else { $null }
$declaredMinimum = if ($null -ne $edgeMinimum) { [math]::Min($bodyMinimum, [double]$edgeMinimum) } else { $bodyMinimum }
$effectiveMinimum = $declaredMinimum * $placedScale
$requiredMinimum = [double]$word.minimumEffectiveFontPoints
if ($effectiveMinimum + 0.01 -lt $requiredMinimum) {
    Add-Issue 'ERROR' 'word-font-too-small' 'composition' "Effective minimum font is $([math]::Round($effectiveMinimum,2)) pt; required $requiredMinimum pt" $content "declared=$declaredMinimum;scale=$placedScale;crop=$cropWidth x $cropHeight" 'compact-or-resize-layout'
}

$result = [pscustomobject]@{
    SchemaVersion = 1
    Source = $SourcePath
    Page = [pscustomobject]@{ Width=$pageWidth; Height=$pageHeight }
    Content = $content
    Crop = [pscustomobject]@{ Border=$border; Width=$cropWidth; Height=$cropHeight; Aspect=$(if($cropHeight-gt0){$cropWidth/$cropHeight}else{0}) }
    Word = [pscustomobject]@{ FrameWidthMm=[double]$word.frameWidthMm; FrameHeightMm=[double]$word.frameHeightMm; PlacedScale=$placedScale; DeclaredMinimumFontPoints=$declaredMinimum; EffectiveMinimumFontPoints=$effectiveMinimum; RequiredMinimumFontPoints=$requiredMinimum }
    ErrorCount = @($issues | Where-Object { $_.Severity -eq 'ERROR' }).Count
    WarningCount = @($issues | Where-Object { $_.Severity -eq 'WARNING' }).Count
    IssueCount = $issues.Count
    Issues = @($issues)
}
$result | ConvertTo-Json -Depth 8
if ($result.ErrorCount -gt 0) { exit 1 }
