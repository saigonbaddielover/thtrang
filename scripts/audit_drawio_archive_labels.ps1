param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$SvgPath,

    [double]$MinimumClearance = 8.0
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$Epsilon = 0.05
$SvgNamespace = 'http://www.w3.org/2000/svg'
$XLinkNamespace = 'http://www.w3.org/1999/xlink'

Add-Type -AssemblyName System.Drawing

function Convert-ToNumber {
    param([string]$Value)

    [double]::Parse($Value, $Invariant)
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Type,
        [string]$Shape,
        [string]$Detail
    )

    $Issues.Add([pscustomobject]@{
        Type = $Type
        Shape = $Shape
        Detail = $Detail
    })
}

function Get-TransformOffset {
    param(
        [System.Xml.XmlElement]$Element,
        [System.Xml.XmlElement]$Boundary
    )

    $x = 0.0
    $y = 0.0
    $node = $Element.ParentNode
    while ($node -and $node -ne $Boundary) {
        if ($node.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            $transform = [string]$node.GetAttribute('transform')
            if ($transform) {
                $match = [regex]::Match(
                    $transform,
                    '^\s*translate\(\s*(-?(?:\d+(?:\.\d+)?|\.\d+))(?:[\s,]+(-?(?:\d+(?:\.\d+)?|\.\d+)))?\s*\)\s*$'
                )
                if (-not $match.Success) {
                    throw "Unsupported SVG transform: $transform"
                }
                $x += Convert-ToNumber $match.Groups[1].Value
                if ($match.Groups[2].Success) {
                    $y += Convert-ToNumber $match.Groups[2].Value
                }
            }
        }
        $node = $node.ParentNode
    }
    [pscustomobject]@{ X = $x; Y = $y }
}

function Get-PathPoints {
    param(
        [System.Xml.XmlElement]$Path,
        [System.Xml.XmlElement]$Boundary
    )

    $offset = Get-TransformOffset $Path $Boundary
    $matches = [regex]::Matches(
        [string]$Path.d,
        '(?i)(?:M|L)\s*(-?(?:\d+(?:\.\d+)?|\.\d+))[\s,]+(-?(?:\d+(?:\.\d+)?|\.\d+))'
    )
    $points = [System.Collections.Generic.List[object]]::new()
    foreach ($match in $matches) {
        $points.Add([pscustomobject]@{
            X = (Convert-ToNumber $match.Groups[1].Value) + $offset.X
            Y = (Convert-ToNumber $match.Groups[2].Value) + $offset.Y
        })
    }
    @($points)
}

function Get-ImageInkBounds {
    param(
        [System.Xml.XmlElement]$Image,
        [System.Xml.XmlElement]$Boundary
    )

    $href = [string]$Image.GetAttribute('href')
    if (-not $href) {
        $href = [string]$Image.GetAttribute('href', $XLinkNamespace)
    }
    $match = [regex]::Match($href, '^data:image/png;base64,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        throw 'Unsupported embedded image format'
    }
    $bytes = [Convert]::FromBase64String($match.Groups[1].Value)
    $stream = [System.IO.MemoryStream]::new($bytes, $false)
    $bitmap = $null
    try {
        $bitmap = [System.Drawing.Bitmap]::new($stream)
        $minimumX = $bitmap.Width
        $minimumY = $bitmap.Height
        $maximumX = -1
        $maximumY = -1
        for ($y = 0; $y -lt $bitmap.Height; $y++) {
            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                if ($bitmap.GetPixel($x, $y).A -eq 0) {
                    continue
                }
                if ($x -lt $minimumX) { $minimumX = $x }
                if ($x -gt $maximumX) { $maximumX = $x }
                if ($y -lt $minimumY) { $minimumY = $y }
                if ($y -gt $maximumY) { $maximumY = $y }
            }
        }
        if ($maximumX -lt 0 -or $maximumY -lt 0) {
            return $null
        }
        $offset = Get-TransformOffset $Image $Boundary
        $imageX = (Convert-ToNumber ([string]$Image.x)) + $offset.X
        $imageY = (Convert-ToNumber ([string]$Image.y)) + $offset.Y
        $imageWidth = Convert-ToNumber ([string]$Image.width)
        $imageHeight = Convert-ToNumber ([string]$Image.height)
        [pscustomobject]@{
            Left = $imageX + ($minimumX / $bitmap.Width * $imageWidth)
            Top = $imageY + ($minimumY / $bitmap.Height * $imageHeight)
            Right = $imageX + (($maximumX + 1) / $bitmap.Width * $imageWidth)
            Bottom = $imageY + (($maximumY + 1) / $bitmap.Height * $imageHeight)
        }
    }
    finally {
        if ($bitmap) { $bitmap.Dispose() }
        $stream.Dispose()
    }
}

function Get-InheritedValue {
    param(
        [System.Xml.XmlElement]$Element,
        [System.Xml.XmlElement]$Boundary,
        [string]$Name,
        [string]$Default
    )

    $node = $Element
    while ($node -and $node -ne $Boundary.ParentNode) {
        if ($node.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            $value = [string]$node.GetAttribute($Name)
            if ($value) {
                return $value
            }
            $style = [string]$node.GetAttribute('style')
            if ($style) {
                $match = [regex]::Match($style, '(?:^|;)\s*' + [regex]::Escape($Name) + '\s*:\s*([^;]+)')
                if ($match.Success) {
                    return $match.Groups[1].Value.Trim()
                }
            }
        }
        $node = $node.ParentNode
    }
    $Default
}

function Get-TextInkBounds {
    param(
        [System.Xml.XmlElement]$Text,
        [System.Xml.XmlElement]$Boundary
    )

    $value = [string]$Text.InnerText
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }
    $x = Convert-ToNumber (([string]$Text.x -split '[\s,]+')[0])
    $y = Convert-ToNumber (([string]$Text.y -split '[\s,]+')[0])
    $fontSizeValue = Get-InheritedValue $Text $Boundary 'font-size' '10'
    $fontSize = Convert-ToNumber ($fontSizeValue -replace 'px$', '')
    $fontName = Get-InheritedValue $Text $Boundary 'font-family' 'Arial'
    $fontWeight = Get-InheritedValue $Text $Boundary 'font-weight' 'normal'
    $fontStyleValue = Get-InheritedValue $Text $Boundary 'font-style' 'normal'
    $textAnchor = Get-InheritedValue $Text $Boundary 'text-anchor' 'start'
    $style = [System.Drawing.FontStyle]::Regular
    if ($fontWeight -in @('bold', '600', '700', '800', '900')) {
        $style = $style -bor [System.Drawing.FontStyle]::Bold
    }
    if ($fontStyleValue -eq 'italic') {
        $style = $style -bor [System.Drawing.FontStyle]::Italic
    }
    $family = $null
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $surface = [System.Drawing.Bitmap]::new(1, 1)
    $graphics = [System.Drawing.Graphics]::FromImage($surface)
    $format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
    try {
        try {
            $family = [System.Drawing.FontFamily]::new($fontName)
        }
        catch {
            $family = [System.Drawing.FontFamily]::GenericSansSerif
        }
        $ascent = $family.GetCellAscent($style) / $family.GetEmHeight($style) * $fontSize
        $path.AddString($value, $family, [int]$style, [single]$fontSize, [System.Drawing.PointF]::new(0, -$ascent), $format)
        $font = [System.Drawing.Font]::new($family, [single]$fontSize, $style, [System.Drawing.GraphicsUnit]::Pixel)
        try {
            $advance = $graphics.MeasureString($value, $font, [int]::MaxValue, $format).Width
        }
        finally {
            $font.Dispose()
        }
        $originX = $x
        if ($textAnchor -eq 'middle') { $originX -= $advance / 2.0 }
        if ($textAnchor -eq 'end') { $originX -= $advance }
        $bounds = $path.GetBounds()
        $offset = Get-TransformOffset $Text $Boundary
        [pscustomobject]@{
            Left = $originX + $bounds.Left + $offset.X
            Top = $y + $bounds.Top + $offset.Y
            Right = $originX + $bounds.Right + $offset.X
            Bottom = $y + $bounds.Bottom + $offset.Y
        }
    }
    finally {
        $format.Dispose()
        $graphics.Dispose()
        $surface.Dispose()
        $path.Dispose()
        if ($family -and $family -ne [System.Drawing.FontFamily]::GenericSansSerif) {
            $family.Dispose()
        }
    }
}

function Merge-Bounds {
    param([object[]]$Bounds)

    $items = @($Bounds | Where-Object { $_ })
    if ($items.Count -eq 0) {
        return $null
    }
    [pscustomobject]@{
        Left = ($items | Measure-Object Left -Minimum).Minimum
        Top = ($items | Measure-Object Top -Minimum).Minimum
        Right = ($items | Measure-Object Right -Maximum).Maximum
        Bottom = ($items | Measure-Object Bottom -Maximum).Maximum
    }
}

if ($MinimumClearance -lt 0 -or [double]::IsNaN($MinimumClearance) -or [double]::IsInfinity($MinimumClearance)) {
    throw 'MinimumClearance must be a finite non-negative number'
}
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Canonical source not found: $SourcePath"
}
if (-not (Test-Path -LiteralPath $SvgPath -PathType Leaf)) {
    throw "SVG not found: $SvgPath"
}

[xml]$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
[xml]$svg = Get-Content -LiteralPath $SvgPath -Raw -Encoding UTF8
$namespace = [System.Xml.XmlNamespaceManager]::new($svg.NameTable)
$namespace.AddNamespace('s', $SvgNamespace)
$archiveCells = @($source.SelectNodes('//mxCell[@vertex="1"]') | Where-Object {
    [string]$_.style -match '(?:^|;)shape=mxgraph\.dfd\.archive(?:;|$)'
})
$issues = [System.Collections.Generic.List[object]]::new()

foreach ($cell in $archiveCells) {
    $id = [string]$cell.id
    $group = $null
    foreach ($candidate in $svg.SelectNodes('//s:g[@data-cell-id]', $namespace)) {
        if ([string]$candidate.GetAttribute('data-cell-id') -eq $id) {
            $group = $candidate
            break
        }
    }
    if (-not $group) {
        Add-Issue $issues 'missing-render-group' $id 'SVG group not found'
        continue
    }
    try {
        $outline = $null
        $outlinePoints = $null
        $divider = $null
        foreach ($path in $group.SelectNodes('.//s:path', $namespace)) {
            $points = @(Get-PathPoints $path $group)
            if (-not $outline -and $points.Count -eq 3 -and [string]$path.d -match '(?i)Z\s*$') {
                $outline = $path
                $outlinePoints = $points
                continue
            }
            if (-not $divider -and $points.Count -eq 2 -and [math]::Abs($points[0].Y - $points[1].Y) -le $Epsilon) {
                $divider = $points
            }
        }
        if (-not $outline -or -not $divider) {
            Add-Issue $issues 'missing-archive-geometry' $id 'Triangle outline or divider not found'
            continue
        }
        $topPoints = @($outlinePoints | Sort-Object Y | Select-Object -First 2 | Sort-Object X)
        $bottomPoint = $outlinePoints | Sort-Object Y -Descending | Select-Object -First 1
        $left = $topPoints[0].X
        $right = $topPoints[1].X
        $top = ($topPoints[0].Y + $topPoints[1].Y) / 2.0
        $bottom = $bottomPoint.Y
        $width = $right - $left
        $height = $bottom - $top
        $dividerY = ($divider[0].Y + $divider[1].Y) / 2.0
        if ($width -le 0 -or $height -le 0 -or $dividerY -lt $top -or $dividerY -gt $bottom) {
            Add-Issue $issues 'invalid-archive-geometry' $id 'Rendered triangle geometry is invalid'
            continue
        }
        $inkBounds = [System.Collections.Generic.List[object]]::new()
        foreach ($image in $group.SelectNodes('.//s:image', $namespace)) {
            $bounds = Get-ImageInkBounds $image $group
            if ($bounds) { $inkBounds.Add($bounds) }
        }
        foreach ($text in $group.SelectNodes('.//s:text', $namespace)) {
            $bounds = Get-TextInkBounds $text $group
            if ($bounds) { $inkBounds.Add($bounds) }
        }
        $ink = Merge-Bounds @($inkBounds)
        if (-not $ink) {
            Add-Issue $issues 'missing-label-ink' $id 'Visible label ink not found'
            continue
        }
        $dividerDistance = $ink.Top - $dividerY
        $bottomDistance = $bottom - $ink.Bottom
        $halfWidth = $width / 2.0
        $slopeLength = [math]::Sqrt(($height * $height) + ($halfWidth * $halfWidth))
        $leftSlopeDistance = (($height * ($ink.Left - $left)) - ($halfWidth * ($ink.Bottom - $top))) / $slopeLength
        $rightSlopeDistance = (($height * ($right - $ink.Right)) - ($halfWidth * ($ink.Bottom - $top))) / $slopeLength
        if ($dividerDistance + $Epsilon -lt $MinimumClearance) {
            Add-Issue $issues 'divider-clearance' $id ("Label ink clearance {0:N2}px" -f $dividerDistance)
        }
        if ($leftSlopeDistance + $Epsilon -lt $MinimumClearance) {
            Add-Issue $issues 'left-slope-clearance' $id ("Label ink clearance {0:N2}px" -f $leftSlopeDistance)
        }
        if ($rightSlopeDistance + $Epsilon -lt $MinimumClearance) {
            Add-Issue $issues 'right-slope-clearance' $id ("Label ink clearance {0:N2}px" -f $rightSlopeDistance)
        }
        if ($bottomDistance + $Epsilon -lt $MinimumClearance) {
            Add-Issue $issues 'bottom-clearance' $id ("Label ink clearance {0:N2}px" -f $bottomDistance)
        }
    }
    catch {
        Add-Issue $issues 'inspection-error' $id $_.Exception.Message
    }
}

$result = [pscustomobject]@{
    Source = $SourcePath
    Svg = $SvgPath
    ShapeCount = $archiveCells.Count
    IssueCount = @($issues | Sort-Object Type, Shape, Detail -Unique).Count
    Issues = @($issues | Sort-Object Type, Shape, Detail -Unique)
}

$result | ConvertTo-Json -Depth 6
if ($result.IssueCount -gt 0) {
    exit 1
}
