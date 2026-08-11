param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$SvgPath,

    [Parameter(Mandatory = $true)]
    [string]$QualityProfilePath
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$SvgNamespace = 'http://www.w3.org/2000/svg'
$XLinkNamespace = 'http://www.w3.org/1999/xlink'
Add-Type -AssemblyName System.Drawing

Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Svg.Geometry.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Svg.Ink.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Shapes.psm1') -Force

function Convert-ToNumber {
    param([string]$Value)
    [double]::Parse($Value, $Invariant)
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Type,
        [string]$Element,
        [string]$Detail,
        [string]$SeverityOverride = ''
    )
    $severity = if ($SeverityOverride) { $SeverityOverride } elseif ($Type -eq 'unknown-stencil-safe-area') { 'WARNING' } else { 'ERROR' }
    $repairClass = if ($Type -match 'font|label|ink') { 'resize-or-reposition-label' } elseif ($Type -match 'overlap|collision|occlusion|divider') { 'relayout' } else { 'rerender' }
    Add-DrawioIssue -Issues $Issues -Type $Type -Element $Element -Detail $Detail -Severity $severity -Evidence $Detail -RepairClass $repairClass
}

function Get-StyleMap {
    param([string]$Style)
    $map = @{}
    foreach ($part in $Style.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $pair = $part.Split('=', 2)
        if ($pair.Count -eq 2) { $map[$pair[0]] = $pair[1] } else { $map[$part] = '1' }
    }
    $map
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
                $match = [regex]::Match($transform, '^\s*translate\(\s*(-?(?:\d+(?:\.\d+)?|\.\d+))(?:[\s,]+(-?(?:\d+(?:\.\d+)?|\.\d+)))?\s*\)\s*$')
                if (-not $match.Success) { throw "Unsupported SVG transform: $transform" }
                $x += Convert-ToNumber $match.Groups[1].Value
                if ($match.Groups[2].Success) { $y += Convert-ToNumber $match.Groups[2].Value }
            }
        }
        $node = $node.ParentNode
    }
    [pscustomobject]@{ X=$x; Y=$y }
}

function Get-ImageInkBounds {
    param(
        [System.Xml.XmlElement]$Image,
        [System.Xml.XmlElement]$Boundary
    )
    $href = [string]$Image.GetAttribute('href')
    if (-not $href) { $href = [string]$Image.GetAttribute('href', $XLinkNamespace) }
    $match = [regex]::Match($href, '^data:image/png;base64,(.+)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { throw 'Unsupported embedded label image format' }
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
                if ($bitmap.GetPixel($x, $y).A -eq 0) { continue }
                if ($x -lt $minimumX) { $minimumX = $x }
                if ($x -gt $maximumX) { $maximumX = $x }
                if ($y -lt $minimumY) { $minimumY = $y }
                if ($y -gt $maximumY) { $maximumY = $y }
            }
        }
        if ($maximumX -lt 0 -or $maximumY -lt 0) { return $null }
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
            if ($value) { return $value }
            $style = [string]$node.GetAttribute('style')
            if ($style) {
                $match = [regex]::Match($style, '(?:^|;)\s*' + [regex]::Escape($Name) + '\s*:\s*([^;]+)')
                if ($match.Success) { return $match.Groups[1].Value.Trim() }
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
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $x = Convert-ToNumber (([string]$Text.x -split '[\s,]+')[0])
    $y = Convert-ToNumber (([string]$Text.y -split '[\s,]+')[0])
    $fontSize = Convert-ToNumber ((Get-InheritedValue $Text $Boundary 'font-size' '10') -replace 'px$', '')
    $fontName = Get-InheritedValue $Text $Boundary 'font-family' 'Arial'
    $fontWeight = Get-InheritedValue $Text $Boundary 'font-weight' 'normal'
    $fontStyleValue = Get-InheritedValue $Text $Boundary 'font-style' 'normal'
    $textAnchor = Get-InheritedValue $Text $Boundary 'text-anchor' 'start'
    $style = [System.Drawing.FontStyle]::Regular
    if ($fontWeight -in @('bold', '600', '700', '800', '900')) { $style = $style -bor [System.Drawing.FontStyle]::Bold }
    if ($fontStyleValue -eq 'italic') { $style = $style -bor [System.Drawing.FontStyle]::Italic }
    $family = $null
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $surface = [System.Drawing.Bitmap]::new(1, 1)
    $graphics = [System.Drawing.Graphics]::FromImage($surface)
    $format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
    try {
        try { $family = [System.Drawing.FontFamily]::new($fontName) } catch { $family = [System.Drawing.FontFamily]::GenericSansSerif }
        $ascent = $family.GetCellAscent($style) / $family.GetEmHeight($style) * $fontSize
        $path.AddString($value, $family, [int]$style, [single]$fontSize, [System.Drawing.PointF]::new(0, -$ascent), $format)
        $font = [System.Drawing.Font]::new($family, [single]$fontSize, $style, [System.Drawing.GraphicsUnit]::Pixel)
        try { $advance = $graphics.MeasureString($value, $font, [int]::MaxValue, $format).Width } finally { $font.Dispose() }
        $originX = $x
        if ($textAnchor -eq 'middle') { $originX -= $advance / 2.0 }
        if ($textAnchor -eq 'end') { $originX -= $advance }
        $bounds = $path.GetBounds()
        $offset = Get-TransformOffset $Text $Boundary
        [pscustomobject]@{ Left=$originX + $bounds.Left + $offset.X; Top=$y + $bounds.Top + $offset.Y; Right=$originX + $bounds.Right + $offset.X; Bottom=$y + $bounds.Bottom + $offset.Y }
    }
    finally {
        $format.Dispose()
        $graphics.Dispose()
        $surface.Dispose()
        $path.Dispose()
        if ($family -and $family -ne [System.Drawing.FontFamily]::GenericSansSerif) { $family.Dispose() }
    }
}

function Merge-Bounds {
    param([object[]]$Bounds)
    $items = @($Bounds | Where-Object { $_ })
    if ($items.Count -eq 0) { return $null }
    [pscustomobject]@{
        Left = ($items | Measure-Object Left -Minimum).Minimum
        Top = ($items | Measure-Object Top -Minimum).Minimum
        Right = ($items | Measure-Object Right -Maximum).Maximum
        Bottom = ($items | Measure-Object Bottom -Maximum).Maximum
    }
}

function Get-LabelBounds {
    param(
        [System.Xml.XmlElement]$Group,
        [System.Xml.XmlNamespaceManager]$Namespace
    )
    Get-SvgLabelInkBounds -Group $Group -Namespace $Namespace
}

function Get-AbsoluteGeometry {
    param(
        [System.Xml.XmlElement]$Cell,
        [hashtable]$Cells,
        [hashtable]$Cache
    )
    $id = [string]$Cell.id
    if ($Cache.ContainsKey($id)) { return $Cache[$id] }
    $geometry = $Cell.SelectSingleNode('./mxGeometry')
    $bounds = [pscustomobject]@{ X=[double]$geometry.x; Y=[double]$geometry.y; Width=[double]$geometry.width; Height=[double]$geometry.height }
    $parentId = [string]$Cell.parent
    if ($Cells.ContainsKey($parentId) -and [string]$Cells[$parentId].vertex -eq '1') {
        $parentBounds = Get-AbsoluteGeometry $Cells[$parentId] $Cells $Cache
        $bounds.X += $parentBounds.X
        $bounds.Y += $parentBounds.Y
    }
    $Cache[$id] = $bounds
    $bounds
}

function Test-Overlap {
    param(
        [object]$A,
        [object]$B,
        [double]$MinimumOverlap = 0.0
    )
    [math]::Min($A.Right, $B.Right) - [math]::Max($A.Left, $B.Left) -gt $MinimumOverlap -and [math]::Min($A.Bottom, $B.Bottom) - [math]::Max($A.Top, $B.Top) -gt $MinimumOverlap
}

function Get-PathSegments {
    param([System.Xml.XmlElement]$Path,[System.Xml.XmlElement]$Boundary)
    $points=@(Get-SvgElementPoints -Element $Path -Boundary $Boundary)
    @(Get-SvgSegments -ElementId '' -Points $points)
}

function Test-SegmentBox {
    param(
        [object]$Segment,
        [object]$Box,
        [double]$Inset = 0.0
    )
    $left = $Box.Left + $Inset
    $top = $Box.Top + $Inset
    $right = $Box.Right - $Inset
    $bottom = $Box.Bottom - $Inset
    if ($left -ge $right -or $top -ge $bottom) { return $false }
    $length=[math]::Sqrt([math]::Pow($Segment.X2-$Segment.X1,2)+[math]::Pow($Segment.Y2-$Segment.Y1,2))
    $steps=[math]::Max(1,[math]::Ceiling($length))
    for($index=0;$index-le$steps;$index++){
        $t=$index/$steps;$x=$Segment.X1+($Segment.X2-$Segment.X1)*$t;$y=$Segment.Y1+($Segment.Y2-$Segment.Y1)*$t
        if($x-gt$left-and$x-lt$right-and$y-gt$top-and$y-lt$bottom){return $true}
    }
    $false
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Canonical source not found: $SourcePath" }
if (-not (Test-Path -LiteralPath $SvgPath -PathType Leaf)) { throw "SVG not found: $SvgPath" }
if (-not (Test-Path -LiteralPath $QualityProfilePath -PathType Leaf)) { throw "Quality profile not found: $QualityProfilePath" }

[xml]$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
[xml]$svg = Get-Content -LiteralPath $SvgPath -Raw -Encoding UTF8
$profile = Get-Content -LiteralPath $QualityProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$nodeLabelClearance = [double]$profile.clearance.nodeLabelInk
$collisionOverlap = [double]$profile.clearance.collisionOverlap
$associationMargin = if ($profile.clearance.PSObject.Properties['edgeLabelAssociation']) { [double]$profile.clearance.edgeLabelAssociation } elseif ($profile.clearance.PSObject.Properties['labelAssociationMargin']) { [double]$profile.clearance.labelAssociationMargin } else { 6.0 }
$bodyMinimum = [double]$profile.fonts.bodyMinimum
$edgeMinimum = [double]$profile.fonts.edgeMinimum
$pageWidth = [double]$source.mxGraphModel.pageWidth
$pageHeight = [double]$source.mxGraphModel.pageHeight
$namespace = [System.Xml.XmlNamespaceManager]::new($svg.NameTable)
$namespace.AddNamespace('s', $SvgNamespace)
$cells = @{}
foreach ($cell in $source.SelectNodes('//mxCell')) { $cells[[string]$cell.id] = $cell }
$geometryCache = @{}
$issues = [System.Collections.Generic.List[object]]::new()
$nodeBoxes = @{}
$nodeCells = @{}
$nodeOutlines = @{}
foreach ($cell in $source.SelectNodes('//mxCell[@vertex="1"]')) {
    if ([string]$cell.id -eq 'title' -or [string]$cell.style -match '(?:^|;)swimlane;') { continue }
    $bounds = Get-AbsoluteGeometry $cell $cells $geometryCache
    $box = [pscustomobject]@{ Left=$bounds.X; Top=$bounds.Y; Right=$bounds.X+$bounds.Width; Bottom=$bounds.Y+$bounds.Height }
    $group=$svg.SelectSingleNode("//s:g[@data-cell-id='$($cell.id)']",$namespace)
    if($group){try{$outline=Get-SvgGroupOutline -Group $group -Namespace $namespace;if($outline){$box=$outline.Bounds;$nodeOutlines[[string]$cell.id]=$outline}}catch{Add-Issue $issues 'render-outline-error' ([string]$cell.id) $_.Exception.Message}}
    $nodeBoxes[[string]$cell.id] = $box
    $nodeCells[[string]$cell.id] = $cell
}

$edgeSegments = @{}
$edgePoints = @{}
foreach ($cell in $source.SelectNodes('//mxCell[@edge="1"]')) {
    $group = $svg.SelectSingleNode("//s:g[@data-cell-id='$($cell.id)']", $namespace)
    if ($group) {
        $path = $group.SelectSingleNode(".//s:path[@fill='none']", $namespace)
        if ($path) {
            try {
                $points=@(Get-SvgElementPoints -Element $path -Boundary $group)
                $edgePoints[[string]$cell.id]=$points
                $edgeSegments[[string]$cell.id]=@(Get-SvgSegments -ElementId ([string]$cell.id) -Points $points)
            }
            catch { Add-Issue $issues 'unsupported-render-geometry' ([string]$cell.id) $_.Exception.Message }
        }
    }
}

$edgeLabels = @{}
foreach ($cell in $source.SelectNodes('//mxCell[@vertex="1" or @edge="1"]')) {
    $id = [string]$cell.id
    $value = [string]$cell.value
    if ([string]::IsNullOrWhiteSpace(($value -replace '&lt;br&gt;|<br>|<br\s*/>', '' -replace '<[^>]+>', ''))) { continue }
    $group = $svg.SelectSingleNode("//s:g[@data-cell-id='$id']", $namespace)
    if (-not $group) {
        Add-Issue $issues 'missing-render-group' $id 'SVG group not found'
        continue
    }
    try { $ink = Get-LabelBounds $group $namespace } catch { Add-Issue $issues 'label-inspection-error' $id $_.Exception.Message; continue }
    if (-not $ink) { Add-Issue $issues 'missing-label-ink' $id 'Rendered label ink not found'; continue }
    if ($ink.PSObject.Properties['FontFallbacks']) {
        foreach ($fallback in @($ink.FontFallbacks)) { Add-Issue $issues 'font-fallback' $id "$($fallback.Requested) -> $($fallback.Rendered)" }
    }
    if ($ink.Left -lt 0 -or $ink.Top -lt 0 -or $ink.Right -gt $pageWidth -or $ink.Bottom -gt $pageHeight) {
        Add-Issue $issues 'label-page-overflow' $id "Label bounds $($ink.Left),$($ink.Top),$($ink.Right),$($ink.Bottom)"
    }
    $style = Get-StyleMap ([string]$cell.style)
    $fontSize = if ($style.ContainsKey('fontSize')) { [double]$style.fontSize } else { 11.0 }
    $fontFamily = if ($style.ContainsKey('fontFamily')) { [string]$style.fontFamily } else { 'Arial' }
    if ($profile.fonts.PSObject.Properties['requiredFamilies'] -and $fontFamily -notin @($profile.fonts.requiredFamilies)) { Add-Issue $issues 'font-family-profile' $id "$fontFamily is not in requiredFamilies" }
    $fontProbe=$null
    try { $fontProbe=[System.Drawing.FontFamily]::new($fontFamily) }
    catch { Add-Issue $issues 'font-unavailable' $id $fontFamily }
    finally { if($fontProbe){$fontProbe.Dispose()} }
    if ([string]$cell.vertex -eq '1') {
        $minimumFont = if ([string]$cell.style -match '(?:^|;)shape=note(?:;|$)') { $edgeMinimum } else { $bodyMinimum }
        if ($fontSize -lt $minimumFont -and $id -ne 'title') { Add-Issue $issues 'body-font-size' $id "$fontSize < $minimumFont" }
        if ($id -eq 'title') { continue }
        $bounds = Get-AbsoluteGeometry $cell $cells $geometryCache
        if([string]$cell.style-notmatch'(?:^|;)swimlane;'){
            try {
                $outline = Get-SvgGroupOutline -Group $group -Namespace $namespace
                if ($outline) { $bounds = [pscustomobject]@{X=$outline.Bounds.Left;Y=$outline.Bounds.Top;Width=$outline.Bounds.Right-$outline.Bounds.Left;Height=$outline.Bounds.Bottom-$outline.Bounds.Top} }
            }
            catch { Add-Issue $issues 'render-outline-error' $id $_.Exception.Message; continue }
        }
        $safe = Get-DrawioShapeSafeArea -Cell $cell -Bounds $bounds -Clearance $nodeLabelClearance
        $inside = Test-DrawioInkSafeArea -Ink $ink -SafeArea $safe
        if ($null -eq $inside) {
            if ($safe.Kind -eq 'unknown') { Add-Issue $issues 'unknown-stencil-safe-area' $id "No verified safe-area adapter for style: $($cell.style)" }
        }
        elseif (-not $inside) { Add-Issue $issues 'node-label-clearance' $id "Rendered label ink exceeds the $($safe.Kind) safe area" }
    }
    else {
        if ($fontSize -lt $edgeMinimum) { Add-Issue $issues 'edge-font-size' $id "$fontSize < $edgeMinimum" }
        $edgeLabels[$id] = $ink
        foreach ($node in $nodeBoxes.GetEnumerator()) {
            $overlapDetected = if ($nodeOutlines.ContainsKey($node.Key)) { Test-SvgBoxPolygonOverlap -Box $ink -Polygon @($nodeOutlines[$node.Key].Points) -Inset $collisionOverlap } else { Test-Overlap $ink $node.Value $collisionOverlap }
            if ($overlapDetected) {
                $overlapWidth = [math]::Min($ink.Right,$node.Value.Right) - [math]::Max($ink.Left,$node.Value.Left)
                $overlapHeight = [math]::Min($ink.Bottom,$node.Value.Bottom) - [math]::Max($ink.Top,$node.Value.Top)
                $detail="$($node.Key); overlap=$([math]::Round($overlapWidth,2))x$([math]::Round($overlapHeight,2))"
                if($nodeOutlines.ContainsKey($node.Key)){Add-Issue $issues 'edge-label-node-collision' $id $detail}else{Add-Issue $issues 'edge-label-node-bbox-risk' $id $detail 'WARNING'}
            }
        }
        foreach ($entry in $edgeSegments.GetEnumerator()) {
            if ($entry.Key -eq $id) { continue }
            foreach ($segment in $entry.Value) {
                if (Test-SegmentBox $segment $ink $collisionOverlap) {
                    Add-Issue $issues 'edge-label-edge-collision' $id "$($entry.Key); segment=$($segment.X1),$($segment.Y1)-$($segment.X2),$($segment.Y2)"
                    break
                }
            }
        }
    }
}

$nodeEntries=@($nodeBoxes.GetEnumerator())
for($leftIndex=0;$leftIndex-lt$nodeEntries.Count;$leftIndex++){
    for($rightIndex=$leftIndex+1;$rightIndex-lt$nodeEntries.Count;$rightIndex++){
        $leftId=[string]$nodeEntries[$leftIndex].Key;$rightId=[string]$nodeEntries[$rightIndex].Key
        if([string]$nodeCells[$leftId].parent-eq$rightId-or[string]$nodeCells[$rightId].parent-eq$leftId){continue}
        if(Test-Overlap $nodeEntries[$leftIndex].Value $nodeEntries[$rightIndex].Value $collisionOverlap){
            Add-Issue $issues 'node-node-overlap' $leftId $rightId
            Add-Issue $issues 'node-node-overlap' $rightId $leftId
        }
    }
}

foreach($entry in $nodeBoxes.GetEnumerator()){
    $cell=$nodeCells[$entry.Key];$parentId=[string]$cell.parent
    if(-not$cells.ContainsKey($parentId)-or[string]$cells[$parentId].vertex-ne'1'-or[string]$cells[$parentId].style-notmatch'(?:^|;)swimlane;'){continue}
    $lane=$cells[$parentId];$laneBounds=Get-AbsoluteGeometry $lane $cells $geometryCache;$laneStyle=Get-StyleMap ([string]$lane.style);$startSize=if($laneStyle.ContainsKey('startSize')){[double]$laneStyle.startSize}else{23.0};$horizontal=(-not$laneStyle.ContainsKey('horizontal'))-or[string]$laneStyle.horizontal-ne'0'
    if($horizontal-and$entry.Value.Top-lt($laneBounds.Y+$startSize-$collisionOverlap)){Add-Issue $issues 'swimlane-header-intrusion' $entry.Key $parentId}
    if(-not$horizontal-and$entry.Value.Left-lt($laneBounds.X+$startSize-$collisionOverlap)){Add-Issue $issues 'swimlane-header-intrusion' $entry.Key $parentId}
}

$edgeLabelEntries = @($edgeLabels.GetEnumerator())
for ($leftIndex=0; $leftIndex -lt $edgeLabelEntries.Count; $leftIndex++) {
    for ($rightIndex=$leftIndex+1; $rightIndex -lt $edgeLabelEntries.Count; $rightIndex++) {
        if (Test-Overlap $edgeLabelEntries[$leftIndex].Value $edgeLabelEntries[$rightIndex].Value $collisionOverlap) {
            Add-Issue $issues 'edge-label-label-collision' $edgeLabelEntries[$leftIndex].Key $edgeLabelEntries[$rightIndex].Key
            Add-Issue $issues 'edge-label-label-collision' $edgeLabelEntries[$rightIndex].Key $edgeLabelEntries[$leftIndex].Key
        }
    }
}

foreach($entry in $edgeLabels.GetEnumerator()){
    if(-not$edgePoints.ContainsKey($entry.Key)){continue}
    $center=[pscustomobject]@{X=($entry.Value.Left+$entry.Value.Right)/2.0;Y=($entry.Value.Top+$entry.Value.Bottom)/2.0}
    $ownDistance=Get-PointPolylineDistance $center @($edgePoints[$entry.Key]);$closestId='';$closestDistance=[double]::PositiveInfinity
    foreach($candidate in $edgePoints.GetEnumerator()){
        if($candidate.Key-eq$entry.Key){continue}
        $distance=Get-PointPolylineDistance $center @($candidate.Value)
        if($distance-lt$closestDistance){$closestDistance=$distance;$closestId=[string]$candidate.Key}
    }
    if($closestId-and$closestDistance+$associationMargin-lt$ownDistance){
        Add-Issue $issues 'edge-label-misassociation' $entry.Key ("Closer to {0}: own={1:N2}px, unrelated={2:N2}px" -f $closestId,$ownDistance,$closestDistance)
    }
}

$uniqueIssues = @($issues | Sort-Object Severity, Type, Element, Detail -Unique)
$result = [pscustomobject]@{ Source=$SourcePath; Svg=$SvgPath; LabelCount=@($source.SelectNodes('//mxCell[(@vertex="1" or @edge="1") and string-length(@value)>0]')).Count; ErrorCount=@($uniqueIssues|Where-Object Severity -eq 'ERROR').Count; WarningCount=@($uniqueIssues|Where-Object Severity -eq 'WARNING').Count; IssueCount=$uniqueIssues.Count; Issues=$uniqueIssues }
$result | ConvertTo-Json -Depth 6
if ($result.ErrorCount -gt 0) { exit 1 }
