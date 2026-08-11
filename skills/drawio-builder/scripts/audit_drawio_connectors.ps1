param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$SvgPath,

    [double]$MinimumStub = 15.0,

    [double]$DividerClearance = 20.0,

    [double]$PageClearance = 24.0,

    [ValidateSet('process', 'data-flow', 'bpmn', 'uml', 'erd', 'architecture', 'cloud', 'network', 'engineering', 'electrical', 'pid', 'floorplan', 'wireframe', 'modeling', 'layout', 'generic')]
    [string]$Profile = 'process'
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$Epsilon = 0.05
$OrthogonalTolerance = 0.25
$ContactTolerance = 3.0

Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Svg.Geometry.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Shapes.psm1') -Force

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

function Compress-PathPoints {
    param([object[]]$Points)
    if($Points.Count-lt3){return @($Points)}
    $compressed=[System.Collections.Generic.List[object]]::new();$compressed.Add($Points[0])
    for($index=1;$index-lt($Points.Count-1);$index++){
        $start=$compressed[$compressed.Count-1];$middle=$Points[$index];$end=$Points[$index+1]
        $ax=$middle.X-$start.X;$ay=$middle.Y-$start.Y;$bx=$end.X-$middle.X;$by=$end.Y-$middle.Y
        $cross=[math]::Abs(($ax*$by)-($ay*$bx));$scale=[math]::Max(1.0,([math]::Sqrt(($ax*$ax)+($ay*$ay))*[math]::Sqrt(($bx*$bx)+($by*$by))))
        if($cross/$scale-gt0.0025-or(($ax*$bx)+($ay*$by))-le0){$compressed.Add($middle)}
    }
    $compressed.Add($Points[$Points.Count-1]);@($compressed)
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
        [string]$Detail,
        [AllowNull()][object]$Coordinates,
        [string]$SeverityOverride = ''
    )

    $repairClass = if ($Type -match 'arrow|anchor|direction|connector|path|jog|backtrack|crossing|touch|border|divider|node') { 'reroute-edge' } elseif ($Type -match 'page') { 'relayout' } else { 'rerender' }
    $severity = if ($SeverityOverride) { $SeverityOverride } else { 'ERROR' }
    Add-DrawioIssue -Issues $Issues -Type $Type -Element $Edge -Detail $Detail -Coordinates $Coordinates -Evidence $Detail -RepairClass $repairClass -Severity $severity
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
$laneStyles = @{}
$nodeOutlines = @{}
$issues = [System.Collections.Generic.List[object]]::new()
$strictRoutingProfile = $Profile -in @('process', 'data-flow')
foreach ($cell in $source.SelectNodes('//mxCell[@vertex="1"]')) {
    $bounds = Get-AbsoluteGeometry $cell $cells $geometryCache
    if ($cell.style -match '(?:^|;)swimlane;') {
        $laneBounds[$cell.id] = $bounds
        $laneStyles[$cell.id] = Get-StyleMap ([string]$cell.style)
    }
    elseif ($cell.id -ne 'title' -and $cell.id -notlike 'qa_*') {
        $nodeBounds[$cell.id] = $bounds
    }
    $group = $svg.SelectSingleNode("//s:g[@data-cell-id='$($cell.id)']", $namespace)
    if ($group) {
        try {
            $outline = Get-SvgGroupOutline -Group $group -Namespace $namespace
            if ($outline) { $nodeOutlines[[string]$cell.id] = $outline }
        }
        catch { Add-Issue $issues 'render-outline-error' ([string]$cell.id) $_.Exception.Message }
    }
}

$edges = @{}
$segments = [System.Collections.Generic.List[object]]::new()
foreach ($cell in $source.SelectNodes('//mxCell[@edge="1"]')) {
    $id = [string]$cell.id
    $style = Get-StyleMap ([string]$cell.style)
    foreach ($key in @('exitX', 'exitY', 'entryX', 'entryY')) {
        if ($style.ContainsKey($key)) {
            $anchorValue = Convert-ToNumber $style[$key]
            if ($anchorValue -lt 0.0 -or $anchorValue -gt 1.0) {
                Add-Issue $issues 'invalid-anchor-value' $id "$key=$anchorValue"
            }
        }
    }
    if ($style.ContainsKey('jumpStyle')) {
        if ($strictRoutingProfile) { Add-Issue $issues 'jump-style' $id "Unexpected jumpStyle=$($style.jumpStyle)" }
        else { Add-Issue $issues 'jump-style-review' $id "jumpStyle=$($style.jumpStyle) requires notation or legend review" $null 'WARNING' }
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
    try { $points = @(Compress-PathPoints @(Get-SvgElementPoints -Element $path -Boundary $group)) }
    catch { Add-Issue $issues 'unsupported-render-geometry' $id $_.Exception.Message; continue }
    if ($points.Count -lt 2) {
        Add-Issue $issues 'zero-length-path' $id 'Fewer than two distinct rendered points'
        continue
    }
    $edgeSegments = @(Get-Segments $id $points)
    foreach ($segment in $edgeSegments) {
        $segments.Add($segment)
        if ($segment.Direction -eq 'diagonal') {
            if ($strictRoutingProfile) { Add-Issue $issues 'diagonal-segment' $id "Segment $($segment.Index) is diagonal" }
            else { Add-Issue $issues 'diagonal-routing-review' $id "Segment $($segment.Index) is diagonal and requires notation review" $null 'WARNING' }
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
    $arrowShapes = [System.Collections.Generic.List[object]]::new()
    foreach ($arrowPath in $group.SelectNodes(".//s:path[not(@fill='none')]", $namespace)) {
        try {
            $candidatePoints = @(Get-SvgElementPoints -Element $arrowPath -Boundary $group)
            if ($candidatePoints.Count -gt 0) { $arrowShapes.Add([pscustomobject]@{Points=$candidatePoints}) }
        }
        catch { Add-Issue $issues 'unsupported-render-arrow' $id $_.Exception.Message }
    }
    $sourceOutline = if ($nodeOutlines.ContainsKey([string]$cell.source)) { $nodeOutlines[[string]$cell.source] } else { $null }
    $targetOutline = if ($nodeOutlines.ContainsKey([string]$cell.target)) { $nodeOutlines[[string]$cell.target] } else { $null }
    $expectsTargetArrow = $style.ContainsKey('endArrow') -and $style.endArrow -ne 'none' -and [string]$style.endArrow -notmatch '(?i)^ER'
    $expectsSourceArrow = $style.ContainsKey('startArrow') -and $style.startArrow -ne 'none' -and [string]$style.startArrow -notmatch '(?i)^ER'
    $arrowTip = $null
    $sourceArrowTip = $null
    $allArrowPoints = @($arrowShapes | ForEach-Object { @($_.Points) })
    if ($expectsTargetArrow -and $allArrowPoints.Count -gt 0 -and $targetOutline) { $arrowTip = $allArrowPoints | Sort-Object { Get-PointPolylineDistance $_ @($targetOutline.Points) } | Select-Object -First 1 }
    elseif ($expectsTargetArrow -and $allArrowPoints.Count -gt 0) { $arrowTip = $allArrowPoints[0] }
    if ($expectsSourceArrow -and $allArrowPoints.Count -gt 0 -and $sourceOutline) { $sourceArrowTip = $allArrowPoints | Sort-Object { Get-PointPolylineDistance $_ @($sourceOutline.Points) } | Select-Object -First 1 }
    if ($expectsTargetArrow -and -not $arrowTip) {
        Add-Issue $issues 'missing-render-arrow' $id 'Rendered target arrowhead not found'
    }
    $targetVectorStart = $points[$points.Count - 1]
    $targetDirection = if ($arrowTip) { Get-SegmentDirection $targetVectorStart $arrowTip } else { $last.Direction }
    $targetLength = $last.Length + $(if ($arrowTip) { Get-SegmentLength $targetVectorStart $arrowTip } else { 0.0 })
    if (-not $sourceOutline) {
        Add-Issue $issues 'missing-source-outline' $id "Rendered outline not found for $($cell.source)"
    }
    else {
        $sourceContactPoint = if ($expectsSourceArrow -and $sourceArrowTip) { $sourceArrowTip } else { $points[0] }
        $sourceDistance = Get-PointPolylineDistance $sourceContactPoint @($sourceOutline.Points)
        if ($sourceDistance -gt $ContactTolerance) { Add-Issue $issues 'source-outline-contact' $id ("Source endpoint is {0:N2}px from rendered outline" -f $sourceDistance) ([pscustomobject]@{X=$sourceContactPoint.X;Y=$sourceContactPoint.Y}) }
        if ($expectsSourceArrow -and -not $sourceArrowTip) { Add-Issue $issues 'missing-render-source-arrow' $id 'Rendered source arrowhead not found' }
        elseif ($expectsSourceArrow) {
            $sourceArrowDirection = Get-SegmentDirection $points[0] $sourceArrowTip
            if ($sourceSides.Count -gt 0 -and -not (Test-TargetDirection $sourceArrowDirection $sourceSides)) { Add-Issue $issues 'source-arrow-direction' $id "Source arrow approaches $sourceArrowDirection; source sides: $($sourceSides -join ',')" }
        }
    }
    if (-not $targetOutline) {
        Add-Issue $issues 'missing-target-outline' $id "Rendered outline not found for $($cell.target)"
    }
    else {
        $targetContactPoint = if ($arrowTip) { $arrowTip } else { $points[$points.Count - 1] }
        $targetDistance = Get-PointPolylineDistance $targetContactPoint @($targetOutline.Points)
        if ($targetDistance -gt $ContactTolerance) { Add-Issue $issues 'target-outline-contact' $id ("Target endpoint is {0:N2}px from rendered outline" -f $targetDistance) ([pscustomobject]@{X=$targetContactPoint.X;Y=$targetContactPoint.Y}) }
        if ($arrowTip) {
            $shaftDistance = Get-PointPolylineDistance $targetVectorStart @($targetOutline.Points)
            if ($shaftDistance -lt 0.75) { Add-Issue $issues 'arrow-shaft-border-contact' $id ("Arrow shaft ends {0:N2}px from target outline" -f $shaftDistance) }
        }
    }
    if ($sourceSides.Count -gt 0 -and -not (Test-SourceDirection $first.Direction $sourceSides)) {
        Add-Issue $issues 'source-direction' $id "First segment goes $($first.Direction); allowed source sides: $($sourceSides -join ',')"
    }
    if ($targetSides.Count -gt 0 -and -not (Test-TargetDirection $targetDirection $targetSides)) {
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

foreach ($edgeGroup in @($segments | Group-Object Edge)) {
    $edgeSegments = @($edgeGroup.Group | Sort-Object Index)
    for ($index = 1; $index -lt $edgeSegments.Count; $index++) {
        $previous = $edgeSegments[$index - 1]
        $current = $edgeSegments[$index]
        if (
            ($previous.Direction -eq 'left' -and $current.Direction -eq 'right') -or
            ($previous.Direction -eq 'right' -and $current.Direction -eq 'left') -or
            ($previous.Direction -eq 'top' -and $current.Direction -eq 'bottom') -or
            ($previous.Direction -eq 'bottom' -and $current.Direction -eq 'top')
        ) {
            Add-Issue $issues 'backtracking' $edgeGroup.Name "Segments $($previous.Index) and $($current.Index) reverse direction"
        }
    }
    for ($leftIndex = 0; $leftIndex -lt $edgeSegments.Count; $leftIndex++) {
        for ($rightIndex = $leftIndex + 2; $rightIndex -lt $edgeSegments.Count; $rightIndex++) {
            $left = $edgeSegments[$leftIndex]
            $right = $edgeSegments[$rightIndex]
            $leftHorizontal = $left.Direction -in @('left', 'right')
            $rightHorizontal = $right.Direction -in @('left', 'right')
            if ($leftHorizontal -eq $rightHorizontal) {
                if ($leftHorizontal -and [math]::Abs($left.Y1 - $right.Y1) -le $Epsilon -and (Test-StrictOverlap $left.MinimumX $left.MaximumX $right.MinimumX $right.MaximumX)) {
                    Add-Issue $issues 'self-overlap' $edgeGroup.Name "Segments $($left.Index) and $($right.Index) overlap"
                }
                elseif (-not $leftHorizontal -and [math]::Abs($left.X1 - $right.X1) -le $Epsilon -and (Test-StrictOverlap $left.MinimumY $left.MaximumY $right.MinimumY $right.MaximumY)) {
                    Add-Issue $issues 'self-overlap' $edgeGroup.Name "Segments $($left.Index) and $($right.Index) overlap"
                }
            }
            else {
                $horizontal = if ($leftHorizontal) { $left } else { $right }
                $vertical = if ($leftHorizontal) { $right } else { $left }
                if (
                    $vertical.X1 -gt ($horizontal.MinimumX + $Epsilon) -and
                    $vertical.X1 -lt ($horizontal.MaximumX - $Epsilon) -and
                    $horizontal.Y1 -gt ($vertical.MinimumY + $Epsilon) -and
                    $horizontal.Y1 -lt ($vertical.MaximumY - $Epsilon)
                ) {
                    Add-Issue $issues 'self-crossing' $edgeGroup.Name "Segments $($left.Index) and $($right.Index) cross"
                }
            }
        }
    }
}

foreach ($group in @($edges.Values | Where-Object { $_.ExitX -or $_.ExitY } | Group-Object Source, ExitX, ExitY | Where-Object Count -gt 1)) {
    $ids = @($group.Group.Id | Sort-Object)
    foreach ($id in $ids) {
        Add-Issue $issues 'duplicate-source-anchor' $id ($ids -join ',')
    }
}
foreach ($group in @($edges.Values | Where-Object { $_.EntryX -or $_.EntryY } | Group-Object Target, EntryX, EntryY | Where-Object Count -gt 1)) {
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
            elseif ($leftHorizontal -and [math]::Abs($left.Y1 - $right.Y1) -le 2.0 -and (Test-StrictOverlap $left.MinimumX $left.MaximumX $right.MinimumX $right.MaximumX)) {
                Add-Issue $issues 'near-shared-path' $left.Edge "$($right.Edge) near y=$($left.Y1)"
                Add-Issue $issues 'near-shared-path' $right.Edge "$($left.Edge) near y=$($right.Y1)"
            }
            elseif (-not $leftHorizontal -and [math]::Abs($left.X1 - $right.X1) -le 2.0 -and (Test-StrictOverlap $left.MinimumY $left.MaximumY $right.MinimumY $right.MaximumY)) {
                Add-Issue $issues 'near-shared-path' $left.Edge "$($right.Edge) near x=$($left.X1)"
                Add-Issue $issues 'near-shared-path' $right.Edge "$($left.Edge) near x=$($right.X1)"
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
            $crossingSeverity = if ($strictRoutingProfile) { 'ERROR' } else { 'WARNING' }
            Add-Issue $issues 'connector-crossing' $left.Edge "$($right.Edge) at $($vertical.X1),$($horizontal.Y1)" $null $crossingSeverity
            Add-Issue $issues 'connector-crossing' $right.Edge "$($left.Edge) at $($vertical.X1),$($horizontal.Y1)" $null $crossingSeverity
        }
        elseif (
            $vertical.X1 -ge ($horizontal.MinimumX - $Epsilon) -and
            $vertical.X1 -le ($horizontal.MaximumX + $Epsilon) -and
            $horizontal.Y1 -ge ($vertical.MinimumY - $Epsilon) -and
            $horizontal.Y1 -le ($vertical.MaximumY + $Epsilon)
        ) {
            $touchSeverity = if ($strictRoutingProfile) { 'ERROR' } else { 'WARNING' }
            Add-Issue $issues 'connector-touch' $left.Edge "$($right.Edge) at $($vertical.X1),$($horizontal.Y1)" $null $touchSeverity
            Add-Issue $issues 'connector-touch' $right.Edge "$($left.Edge) at $($vertical.X1),$($horizontal.Y1)" $null $touchSeverity
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
        if ($nodeOutlines.ContainsKey($entry.Key)) {
            $outlineBounds = $nodeOutlines[$entry.Key].Bounds
            if ($segment.MaximumX -lt ($outlineBounds.Left - 1.5) -or $segment.MinimumX -gt ($outlineBounds.Right + 1.5) -or $segment.MaximumY -lt ($outlineBounds.Top - 1.5) -or $segment.MinimumY -gt ($outlineBounds.Bottom + 1.5)) { continue }
            $relation = Get-SegmentPolygonRelation -Segment $segment -Polygon @($nodeOutlines[$entry.Key].Points) -BorderTolerance 1.5
            if ($relation.InteriorSamples -gt 0) {
                Add-Issue $issues 'node-crossing' $segment.Edge "$($entry.Key) rendered interior"
            }
            elseif ($relation.BorderSamples -ge 3 -and $segment.Length -ge $MinimumStub) {
                Add-Issue $issues 'node-border-overlap' $segment.Edge "$($entry.Key) rendered outline"
            }
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
        foreach ($laneEntry in $laneBounds.GetEnumerator()) {
            $lane = $laneEntry.Value
            $laneStyle = $laneStyles[$laneEntry.Key]
            $laneHorizontal = (-not $laneStyle.ContainsKey('horizontal')) -or [string]$laneStyle.horizontal -ne '0'
            $startSize = if ($laneStyle.ContainsKey('startSize')) { Convert-ToNumber $laneStyle.startSize } else { 23.0 }
            $dividers = @($lane.X, ($lane.X + $lane.Width))
            if (-not $laneHorizontal) { $dividers += ($lane.X + $startSize) }
            foreach ($divider in @($dividers | Sort-Object -Unique)) {
                $distance = [math]::Abs($segment.X1 - $divider)
                $overlapsLane = Test-StrictOverlap $segment.MinimumY $segment.MaximumY $lane.Y ($lane.Y + $lane.Height)
                if ($overlapsLane -and $distance -gt $Epsilon -and $distance -lt $DividerClearance -and $segment.Length -ge $MinimumStub) {
                    Add-Issue $issues 'divider-clearance' $segment.Edge ("Vertical segment at x={0:N2} is {1:N2}px from divider" -f $segment.X1, $distance)
                }
            }
        }
    }
    else {
        foreach ($laneEntry in $laneBounds.GetEnumerator()) {
            $lane = $laneEntry.Value
            $laneStyle = $laneStyles[$laneEntry.Key]
            $laneHorizontal = (-not $laneStyle.ContainsKey('horizontal')) -or [string]$laneStyle.horizontal -ne '0'
            $startSize = if ($laneStyle.ContainsKey('startSize')) { Convert-ToNumber $laneStyle.startSize } else { 23.0 }
            $dividers = @($lane.Y, ($lane.Y + $lane.Height))
            if ($laneHorizontal) { $dividers += ($lane.Y + $startSize) }
            foreach ($divider in @($dividers | Sort-Object -Unique)) {
                $distance = [math]::Abs($segment.Y1 - $divider)
                $overlapsLane = Test-StrictOverlap $segment.MinimumX $segment.MaximumX $lane.X ($lane.X + $lane.Width)
                if ($overlapsLane -and $distance -gt $Epsilon -and $distance -lt $DividerClearance -and $segment.Length -ge $MinimumStub) {
                    Add-Issue $issues 'divider-clearance' $segment.Edge ("Horizontal segment at y={0:N2} is {1:N2}px from divider" -f $segment.Y1, $distance)
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

$uniqueIssues = @($issues | Sort-Object Severity, Type, Element, Detail -Unique)
$result = [pscustomobject]@{
    Source = $SourcePath
    Svg = $SvgPath
    Profile = $Profile
    EdgeCount = $edges.Count
    ErrorCount = @($uniqueIssues | Where-Object Severity -eq 'ERROR').Count
    WarningCount = @($uniqueIssues | Where-Object Severity -eq 'WARNING').Count
    IssueCount = $uniqueIssues.Count
    Issues = $uniqueIssues
}

$result | ConvertTo-Json -Depth 6
if ($result.ErrorCount -gt 0) {
    exit 1
}
