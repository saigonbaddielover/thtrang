param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$SvgPath,

    [double]$MinimumStub = 15.0,

    [double]$DividerClearance = 20.0,

    [double]$PageClearance = 24.0
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$Epsilon = 0.05
$OrthogonalTolerance = 0.25

function Convert-ToNumber {
    param([string]$Value)

    [double]::Parse($Value, $Invariant)
}

function Get-StyleMap {
    param([string]$Style)

    $map = @{}
    foreach ($part in $Style.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $pair = $part.Split('=', 2)
        if ($pair.Count -eq 2) {
            $map[$pair[0]] = $pair[1]
        }
        else {
            $map[$part] = '1'
        }
    }
    $map
}

function Get-PathPoints {
    param([string]$PathData)

    $matches = [regex]::Matches(
        $PathData,
        '(?i)(?:M|L)\s*(-?(?:\d+(?:\.\d+)?|\.\d+))[\s,]+(-?(?:\d+(?:\.\d+)?|\.\d+))'
    )
    $points = [System.Collections.Generic.List[object]]::new()
    foreach ($match in $matches) {
        $point = [pscustomobject]@{
            X = Convert-ToNumber $match.Groups[1].Value
            Y = Convert-ToNumber $match.Groups[2].Value
        }
        if ($points.Count -eq 0) {
            $points.Add($point)
            continue
        }
        $previous = $points[$points.Count - 1]
        if ([math]::Abs($point.X - $previous.X) -gt $Epsilon -or [math]::Abs($point.Y - $previous.Y) -gt $Epsilon) {
            $points.Add($point)
        }
    }
    @($points)
}

function Get-AbsoluteGeometry {
    param(
        [System.Xml.XmlElement]$Cell,
        [hashtable]$Cells,
        [hashtable]$Cache
    )

    if ($Cache.ContainsKey($Cell.id)) {
        return $Cache[$Cell.id]
    }
    $geometry = $Cell.SelectSingleNode('./mxGeometry')
    $x = if ($geometry.x) { Convert-ToNumber $geometry.x } else { 0.0 }
    $y = if ($geometry.y) { Convert-ToNumber $geometry.y } else { 0.0 }
    $width = if ($geometry.width) { Convert-ToNumber $geometry.width } else { 0.0 }
    $height = if ($geometry.height) { Convert-ToNumber $geometry.height } else { 0.0 }
    if ($Cell.parent -and $Cells.ContainsKey($Cell.parent)) {
        $parent = $Cells[$Cell.parent]
        if ($parent.vertex -eq '1') {
            $parentGeometry = Get-AbsoluteGeometry $parent $Cells $Cache
            $x += $parentGeometry.X
            $y += $parentGeometry.Y
        }
    }
    $result = [pscustomobject]@{
        X = $x
        Y = $y
        Width = $width
        Height = $height
    }
    $Cache[$Cell.id] = $result
    $result
}

function Get-AllowedSides {
    param(
        [hashtable]$Style,
        [string]$Prefix
    )

    $xKey = $Prefix + 'X'
    $yKey = $Prefix + 'Y'
    $sides = [System.Collections.Generic.List[string]]::new()
    if ($Style.ContainsKey($xKey)) {
        $x = Convert-ToNumber $Style[$xKey]
        if ([math]::Abs($x) -le $Epsilon) { $sides.Add('left') }
        if ([math]::Abs($x - 1.0) -le $Epsilon) { $sides.Add('right') }
    }
    if ($Style.ContainsKey($yKey)) {
        $y = Convert-ToNumber $Style[$yKey]
        if ([math]::Abs($y) -le $Epsilon) { $sides.Add('top') }
        if ([math]::Abs($y - 1.0) -le $Epsilon) { $sides.Add('bottom') }
    }
    @($sides)
}

function Get-SegmentDirection {
    param(
        $Start,
        $End
    )

    $dx = $End.X - $Start.X
    $dy = $End.Y - $Start.Y
    $absoluteX = [math]::Abs($dx)
    $absoluteY = [math]::Abs($dy)
    $major = [math]::Max($absoluteX, $absoluteY)
    $minor = [math]::Min($absoluteX, $absoluteY)
    $allowedMinor = [math]::Max($OrthogonalTolerance, $major * 0.025)
    if ($minor -gt $allowedMinor) {
        return 'diagonal'
    }
    if ($absoluteX -ge $absoluteY) {
        if ($dx -gt 0) { return 'right' }
        return 'left'
    }
    if ($dy -gt 0) { return 'bottom' }
    'top'
}

function Get-SegmentLength {
    param(
        $Start,
        $End
    )

    [math]::Abs($End.X - $Start.X) + [math]::Abs($End.Y - $Start.Y)
}

function Test-SourceDirection {
    param(
        [string]$Direction,
        [string[]]$Sides
    )

    $Direction -in $Sides
}

function Test-TargetDirection {
    param(
        [string]$Direction,
        [string[]]$Sides
    )

    foreach ($side in $Sides) {
        if (
            ($side -eq 'left' -and $Direction -eq 'right') -or
            ($side -eq 'right' -and $Direction -eq 'left') -or
            ($side -eq 'top' -and $Direction -eq 'bottom') -or
            ($side -eq 'bottom' -and $Direction -eq 'top')
        ) {
            return $true
        }
    }
    $false
}

function Get-Segments {
    param(
        [string]$EdgeId,
        [object[]]$Points
    )

    $segments = [System.Collections.Generic.List[object]]::new()
    for ($index = 1; $index -lt $Points.Count; $index++) {
        $start = $Points[$index - 1]
        $end = $Points[$index]
        $direction = Get-SegmentDirection $start $end
        $segments.Add([pscustomobject]@{
            Edge = $EdgeId
            Index = $index - 1
            Direction = $direction
            X1 = $start.X
            Y1 = $start.Y
            X2 = $end.X
            Y2 = $end.Y
            MinimumX = [math]::Min($start.X, $end.X)
            MaximumX = [math]::Max($start.X, $end.X)
            MinimumY = [math]::Min($start.Y, $end.Y)
            MaximumY = [math]::Max($start.Y, $end.Y)
            Length = Get-SegmentLength $start $end
        })
    }
    @($segments)
}

function Test-StrictOverlap {
    param(
        [double]$MinimumA,
        [double]$MaximumA,
        [double]$MinimumB,
        [double]$MaximumB
    )

    [math]::Min($MaximumA, $MaximumB) - [math]::Max($MinimumA, $MinimumB) -gt $Epsilon
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Type,
        [string]$Edge,
        [string]$Detail
    )

    $Issues.Add([pscustomobject]@{
        Type = $Type
        Edge = $Edge
        Detail = $Detail
    })
}

[xml]$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
[xml]$svg = Get-Content -LiteralPath $SvgPath -Raw -Encoding UTF8
$namespace = [System.Xml.XmlNamespaceManager]::new($svg.NameTable)
$namespace.AddNamespace('s', 'http://www.w3.org/2000/svg')

$model = $source.SelectSingleNode('/mxGraphModel')
$pageWidth = Convert-ToNumber $model.pageWidth
$pageHeight = Convert-ToNumber $model.pageHeight
$svgRoot = $svg.SelectSingleNode('/s:svg', $namespace)
$viewBoxValues = @($svgRoot.viewBox.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { Convert-ToNumber $_ })
if (
    $viewBoxValues.Count -ne 4 -or
    [math]::Abs($viewBoxValues[0]) -gt $Epsilon -or
    [math]::Abs($viewBoxValues[1]) -gt $Epsilon -or
    [math]::Abs($viewBoxValues[2] - ($pageWidth + 1.0)) -gt 1.0 -or
    [math]::Abs($viewBoxValues[3] - ($pageHeight + 1.0)) -gt 1.0
) {
    throw "SVG viewBox does not match the canonical page: $($svgRoot.viewBox)"
}
$cells = @{}
foreach ($cell in $source.SelectNodes('//mxCell')) {
    $cells[$cell.id] = $cell
}

$geometryCache = @{}
$nodeBounds = @{}
$laneBounds = @{}
foreach ($cell in $source.SelectNodes('//mxCell[@vertex="1"]')) {
    $bounds = Get-AbsoluteGeometry $cell $cells $geometryCache
    if ($cell.style -match '(?:^|;)swimlane;') {
        $laneBounds[$cell.id] = $bounds
    }
    elseif ($cell.id -ne 'title' -and $cell.id -notlike 'qa_*') {
        $nodeBounds[$cell.id] = $bounds
    }
}

$issues = [System.Collections.Generic.List[object]]::new()
$edges = @{}
$segments = [System.Collections.Generic.List[object]]::new()
foreach ($cell in $source.SelectNodes('//mxCell[@edge="1"]')) {
    $id = [string]$cell.id
    $style = Get-StyleMap ([string]$cell.style)
    foreach ($key in @('exitX', 'exitY', 'entryX', 'entryY')) {
        if (-not $style.ContainsKey($key)) {
            Add-Issue $issues 'missing-anchor' $id $key
        }
        else {
            $anchorValue = Convert-ToNumber $style[$key]
            if ($anchorValue -lt 0.0 -or $anchorValue -gt 1.0) {
                Add-Issue $issues 'invalid-anchor-value' $id "$key=$anchorValue"
            }
        }
    }
    if (-not $style.ContainsKey('endArrow') -or $style.endArrow -ne 'classic' -or -not $style.ContainsKey('endFill') -or $style.endFill -ne '1') {
        Add-Issue $issues 'target-arrow' $id 'Expected endArrow=classic and endFill=1'
    }
    if ($style.ContainsKey('startArrow') -and $style.startArrow -ne 'none') {
        Add-Issue $issues 'source-arrow' $id "Unexpected startArrow=$($style.startArrow)"
    }
    if ($style.ContainsKey('jumpStyle')) {
        Add-Issue $issues 'jump-style' $id "Unexpected jumpStyle=$($style.jumpStyle)"
    }

    $group = $svg.SelectSingleNode("//s:g[@data-cell-id='$id']", $namespace)
    if (-not $group) {
        Add-Issue $issues 'missing-render-group' $id 'SVG group not found'
        continue
    }
    $path = $group.SelectSingleNode(".//s:path[@fill='none']", $namespace)
    if (-not $path) {
        Add-Issue $issues 'missing-render-path' $id 'Rendered connector path not found'
        continue
    }
    $points = @(Get-PathPoints $path.d)
    if ($points.Count -lt 2) {
        Add-Issue $issues 'zero-length-path' $id 'Fewer than two distinct rendered points'
        continue
    }
    $edgeSegments = @(Get-Segments $id $points)
    foreach ($segment in $edgeSegments) {
        $segments.Add($segment)
        if ($segment.Direction -eq 'diagonal') {
            Add-Issue $issues 'diagonal-segment' $id "Segment $($segment.Index) is diagonal"
        }
    }
    if ($edgeSegments.Count -gt 2) {
        for ($segmentIndex = 1; $segmentIndex -lt ($edgeSegments.Count - 1); $segmentIndex++) {
            if ($edgeSegments[$segmentIndex].Length -lt $MinimumStub) {
                Add-Issue $issues 'internal-micro-jog' $id ("Segment $segmentIndex length {0:N2}" -f $edgeSegments[$segmentIndex].Length)
            }
        }
    }

    $sourceSides = @(Get-AllowedSides $style 'exit')
    $targetSides = @(Get-AllowedSides $style 'entry')
    $first = $edgeSegments[0]
    $last = $edgeSegments[$edgeSegments.Count - 1]
    $arrowPath = $group.SelectSingleNode(".//s:path[not(@fill='none')][1]", $namespace)
    $arrowPoints = if ($arrowPath) { @(Get-PathPoints $arrowPath.d) } else { @() }
    $arrowTip = if ($arrowPoints.Count -gt 0) { $arrowPoints[0] } else { $null }
    if (-not $arrowTip) {
        Add-Issue $issues 'missing-render-arrow' $id 'Rendered target arrowhead not found'
    }
    $targetVectorStart = if ($points.Count -gt 2) { $points[$points.Count - 2] } else { $points[0] }
    $targetDirection = if ($arrowTip) { Get-SegmentDirection $targetVectorStart $arrowTip } else { $last.Direction }
    $targetLength = if ($arrowTip) { Get-SegmentLength $targetVectorStart $arrowTip } else { $last.Length }
    if ($sourceSides.Count -eq 0) {
        Add-Issue $issues 'invalid-source-side' $id 'Anchor is not on a source side'
    }
    elseif (-not (Test-SourceDirection $first.Direction $sourceSides)) {
        Add-Issue $issues 'source-direction' $id "First segment goes $($first.Direction); allowed source sides: $($sourceSides -join ',')"
    }
    if ($targetSides.Count -eq 0) {
        Add-Issue $issues 'invalid-target-side' $id 'Anchor is not on a target side'
    }
    elseif (-not (Test-TargetDirection $targetDirection $targetSides)) {
        Add-Issue $issues 'target-direction' $id "Arrow approaches $targetDirection; target sides: $($targetSides -join ',')"
    }
    if ($edgeSegments.Count -eq 1) {
        if ($targetLength -lt $MinimumStub) {
            Add-Issue $issues 'short-connector' $id ("Rendered source-to-arrow length {0:N2}" -f $targetLength)
        }
    }
    else {
        if ($first.Length -lt $MinimumStub) {
            Add-Issue $issues 'source-micro-jog' $id ("First segment length {0:N2}" -f $first.Length)
        }
        if ($targetLength -lt $MinimumStub) {
            Add-Issue $issues 'target-micro-jog' $id ("Final bend-to-arrow length {0:N2}" -f $targetLength)
        }
    }

    $edges[$id] = [pscustomobject]@{
        Id = $id
        Source = [string]$cell.source
        Target = [string]$cell.target
        ExitX = if ($style.ContainsKey('exitX')) { $style.exitX } else { '' }
        ExitY = if ($style.ContainsKey('exitY')) { $style.exitY } else { '' }
        EntryX = if ($style.ContainsKey('entryX')) { $style.entryX } else { '' }
        EntryY = if ($style.ContainsKey('entryY')) { $style.entryY } else { '' }
        Points = $points
    }
}

foreach ($group in @($edges.Values | Group-Object Source, ExitX, ExitY | Where-Object Count -gt 1)) {
    $ids = @($group.Group.Id | Sort-Object)
    foreach ($id in $ids) {
        Add-Issue $issues 'duplicate-source-anchor' $id ($ids -join ',')
    }
}
foreach ($group in @($edges.Values | Group-Object Target, EntryX, EntryY | Where-Object Count -gt 1)) {
    $ids = @($group.Group.Id | Sort-Object)
    foreach ($id in $ids) {
        Add-Issue $issues 'duplicate-target-anchor' $id ($ids -join ',')
    }
}

for ($leftIndex = 0; $leftIndex -lt $segments.Count; $leftIndex++) {
    $left = $segments[$leftIndex]
    for ($rightIndex = $leftIndex + 1; $rightIndex -lt $segments.Count; $rightIndex++) {
        $right = $segments[$rightIndex]
        if ($left.Edge -eq $right.Edge) {
            continue
        }
        $leftHorizontal = $left.Direction -in @('left', 'right')
        $rightHorizontal = $right.Direction -in @('left', 'right')
        if ($leftHorizontal -eq $rightHorizontal) {
            if ($leftHorizontal -and [math]::Abs($left.Y1 - $right.Y1) -le $Epsilon -and (Test-StrictOverlap $left.MinimumX $left.MaximumX $right.MinimumX $right.MaximumX)) {
                Add-Issue $issues 'shared-path' $left.Edge "$($right.Edge) at y=$($left.Y1)"
                Add-Issue $issues 'shared-path' $right.Edge "$($left.Edge) at y=$($left.Y1)"
            }
            elseif (-not $leftHorizontal -and [math]::Abs($left.X1 - $right.X1) -le $Epsilon -and (Test-StrictOverlap $left.MinimumY $left.MaximumY $right.MinimumY $right.MaximumY)) {
                Add-Issue $issues 'shared-path' $left.Edge "$($right.Edge) at x=$($left.X1)"
                Add-Issue $issues 'shared-path' $right.Edge "$($left.Edge) at x=$($left.X1)"
            }
            continue
        }
        $horizontal = if ($leftHorizontal) { $left } else { $right }
        $vertical = if ($leftHorizontal) { $right } else { $left }
        if (
            $vertical.X1 -gt ($horizontal.MinimumX + $Epsilon) -and
            $vertical.X1 -lt ($horizontal.MaximumX - $Epsilon) -and
            $horizontal.Y1 -gt ($vertical.MinimumY + $Epsilon) -and
            $horizontal.Y1 -lt ($vertical.MaximumY - $Epsilon)
        ) {
            Add-Issue $issues 'connector-crossing' $left.Edge "$($right.Edge) at $($vertical.X1),$($horizontal.Y1)"
            Add-Issue $issues 'connector-crossing' $right.Edge "$($left.Edge) at $($vertical.X1),$($horizontal.Y1)"
        }
    }
}

foreach ($segment in $segments) {
    $edge = $edges[$segment.Edge]
    $horizontal = $segment.Direction -in @('left', 'right')
    foreach ($entry in $nodeBounds.GetEnumerator()) {
        if ($entry.Key -in @($edge.Source, $edge.Target)) {
            continue
        }
        $bounds = $entry.Value
        $left = $bounds.X
        $right = $bounds.X + $bounds.Width
        $top = $bounds.Y
        $bottom = $bounds.Y + $bounds.Height
        if ($horizontal) {
            if ($segment.Y1 -gt ($top + $Epsilon) -and $segment.Y1 -lt ($bottom - $Epsilon) -and (Test-StrictOverlap $segment.MinimumX $segment.MaximumX $left $right)) {
                Add-Issue $issues 'node-crossing' $segment.Edge "$($entry.Key) interior"
            }
            elseif (([math]::Abs($segment.Y1 - $top) -le 1.5 -or [math]::Abs($segment.Y1 - $bottom) -le 1.5) -and (Test-StrictOverlap $segment.MinimumX $segment.MaximumX $left $right)) {
                Add-Issue $issues 'node-border-overlap' $segment.Edge "$($entry.Key) horizontal border"
            }
        }
        else {
            if ($segment.X1 -gt ($left + $Epsilon) -and $segment.X1 -lt ($right - $Epsilon) -and (Test-StrictOverlap $segment.MinimumY $segment.MaximumY $top $bottom)) {
                Add-Issue $issues 'node-crossing' $segment.Edge "$($entry.Key) interior"
            }
            elseif (([math]::Abs($segment.X1 - $left) -le 1.5 -or [math]::Abs($segment.X1 - $right) -le 1.5) -and (Test-StrictOverlap $segment.MinimumY $segment.MaximumY $top $bottom)) {
                Add-Issue $issues 'node-border-overlap' $segment.Edge "$($entry.Key) vertical border"
            }
        }
    }
    if (-not $horizontal) {
        foreach ($lane in $laneBounds.Values) {
            foreach ($divider in @($lane.X, ($lane.X + $lane.Width))) {
                $distance = [math]::Abs($segment.X1 - $divider)
                $overlapsLane = Test-StrictOverlap $segment.MinimumY $segment.MaximumY $lane.Y ($lane.Y + $lane.Height)
                if ($overlapsLane -and $distance -gt $Epsilon -and $distance -lt $DividerClearance -and $segment.Length -ge $MinimumStub) {
                    Add-Issue $issues 'divider-clearance' $segment.Edge ("Vertical segment at x={0:N2} is {1:N2}px from divider" -f $segment.X1, $distance)
                }
            }
        }
    }
    if (
        $segment.MinimumX -lt $PageClearance -or
        $segment.MaximumX -gt ($pageWidth - $PageClearance) -or
        $segment.MinimumY -lt $PageClearance -or
        $segment.MaximumY -gt ($pageHeight - $PageClearance)
    ) {
        Add-Issue $issues 'page-clearance' $segment.Edge "Segment $($segment.Index) approaches the page boundary"
    }
}

$result = [pscustomobject]@{
    Source = $SourcePath
    Svg = $SvgPath
    EdgeCount = $edges.Count
    IssueCount = @($issues | Sort-Object Type, Edge, Detail -Unique).Count
    Issues = @($issues | Sort-Object Type, Edge, Detail -Unique)
}

$result | ConvertTo-Json -Depth 6
if ($result.IssueCount -gt 0) {
    exit 1
}
