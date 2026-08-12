param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$SvgPath,
    [Parameter(Mandatory = $true)][string]$QualityProfilePath
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$issues = [System.Collections.Generic.List[object]]::new()
Import-Module (Join-Path $PSScriptRoot 'lib\Svg.Geometry.psm1') -Force

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

function Compress-Points {
    param([object[]]$Points,[double]$Tolerance)
    $distinct = [System.Collections.Generic.List[object]]::new()
    foreach ($point in $Points) {
        if ($distinct.Count -eq 0 -or [math]::Abs($point.X-$distinct[$distinct.Count-1].X) -gt $Tolerance -or [math]::Abs($point.Y-$distinct[$distinct.Count-1].Y) -gt $Tolerance) { $distinct.Add($point) }
    }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($point in $distinct) {
        while ($result.Count -ge 2) {
            $a = $result[$result.Count-2]
            $b = $result[$result.Count-1]
            $vertical = [math]::Abs($a.X-$b.X) -le $Tolerance -and [math]::Abs($b.X-$point.X) -le $Tolerance
            $horizontal = [math]::Abs($a.Y-$b.Y) -le $Tolerance -and [math]::Abs($b.Y-$point.Y) -le $Tolerance
            if (-not ($vertical -or $horizontal)) { break }
            $result.RemoveAt($result.Count-1)
        }
        $result.Add($point)
    }
    @($result)
}

function Get-PathMetrics {
    param([object[]]$Points,[double]$Tolerance)
    $compressed = @(Compress-Points $Points $Tolerance)
    $length = 0.0
    $directions = [System.Collections.Generic.List[string]]::new()
    for ($index=1; $index -lt $compressed.Count; $index++) {
        $dx = $compressed[$index].X-$compressed[$index-1].X
        $dy = $compressed[$index].Y-$compressed[$index-1].Y
        $length += [math]::Abs($dx)+[math]::Abs($dy)
        if ([math]::Abs($dx) -gt $Tolerance -and [math]::Abs($dy) -gt $Tolerance) { $directions.Add('diagonal') }
        elseif ([math]::Abs($dx) -gt $Tolerance) { $directions.Add('horizontal') }
        elseif ([math]::Abs($dy) -gt $Tolerance) { $directions.Add('vertical') }
    }
    $bends = 0
    for ($index=1; $index -lt $directions.Count; $index++) { if ($directions[$index] -ne $directions[$index-1]) { $bends++ } }
    [pscustomobject]@{ Points=$compressed; SegmentCount=$directions.Count; BendCount=$bends; Length=$length; HasDiagonal=('diagonal' -in $directions) }
}

function Get-SegmentDirection {
    param([object]$Start,[object]$End,[double]$Tolerance)
    $dx=$End.X-$Start.X
    $dy=$End.Y-$Start.Y
    if([math]::Abs($dx) -gt $Tolerance -and [math]::Abs($dy) -le $Tolerance){if($dx -gt 0){return 'right'}return 'left'}
    if([math]::Abs($dy) -gt $Tolerance -and [math]::Abs($dx) -le $Tolerance){if($dy -gt 0){return 'down'}return 'up'}
    'other'
}

function Get-PortDirections {
    param([hashtable]$Style,[string]$Mode,[double]$Tolerance)
    $xKey=if($Mode-eq'Exit'){'exitX'}else{'entryX'}
    $yKey=if($Mode-eq'Exit'){'exitY'}else{'entryY'}
    if(-not $Style.ContainsKey($xKey) -or -not $Style.ContainsKey($yKey)){return @()}
    $x=Convert-ToNumber ([string]$Style[$xKey])
    $y=Convert-ToNumber ([string]$Style[$yKey])
    $directions=[System.Collections.Generic.List[string]]::new()
    if([math]::Abs($x) -le $Tolerance){$directions.Add($(if($Mode -eq 'Exit'){'left'}else{'right'}))}
    if([math]::Abs($x-1) -le $Tolerance){$directions.Add($(if($Mode -eq 'Exit'){'right'}else{'left'}))}
    if([math]::Abs($y) -le $Tolerance){$directions.Add($(if($Mode -eq 'Exit'){'up'}else{'down'}))}
    if([math]::Abs($y-1) -le $Tolerance){$directions.Add($(if($Mode -eq 'Exit'){'down'}else{'up'}))}
    @($directions)
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
    $result = [pscustomobject]@{ Left=$x; Top=$y; Right=$x+$width; Bottom=$y+$height }
    $Cache[[string]$Cell.id] = $result
    $result
}

function Test-SegmentClear {
    param([object]$Start,[object]$End,[object[]]$Obstacles,[double]$Tolerance)
    $horizontal = [math]::Abs($Start.Y-$End.Y) -le $Tolerance
    $vertical = [math]::Abs($Start.X-$End.X) -le $Tolerance
    if (-not ($horizontal -or $vertical)) { return $false }
    foreach ($obstacle in $Obstacles) {
        if ($horizontal) {
            $minimum = [math]::Min($Start.X,$End.X)
            $maximum = [math]::Max($Start.X,$End.X)
            if ($Start.Y -gt $obstacle.Top+$Tolerance -and $Start.Y -lt $obstacle.Bottom-$Tolerance -and $maximum -gt $obstacle.Left+$Tolerance -and $minimum -lt $obstacle.Right-$Tolerance) { return $false }
        }
        else {
            $minimum = [math]::Min($Start.Y,$End.Y)
            $maximum = [math]::Max($Start.Y,$End.Y)
            if ($Start.X -gt $obstacle.Left+$Tolerance -and $Start.X -lt $obstacle.Right-$Tolerance -and $maximum -gt $obstacle.Top+$Tolerance -and $minimum -lt $obstacle.Bottom-$Tolerance) { return $false }
        }
    }
    $true
}

function Get-BestCandidate {
    param([object]$Start,[object]$End,[object[]]$Obstacles,[double[]]$Xs,[double[]]$Ys,[string[]]$ExitDirections,[string[]]$EntryDirections,[double]$Tolerance)
    $candidates = [System.Collections.Generic.List[object]]::new()
    $paths = [System.Collections.Generic.List[object]]::new()
    $paths.Add(@($Start,$End))
    $paths.Add(@($Start,[pscustomobject]@{X=$Start.X;Y=$End.Y},$End))
    $paths.Add(@($Start,[pscustomobject]@{X=$End.X;Y=$Start.Y},$End))
    foreach ($x in $Xs) { $paths.Add(@($Start,[pscustomobject]@{X=$x;Y=$Start.Y},[pscustomobject]@{X=$x;Y=$End.Y},$End)) }
    foreach ($y in $Ys) { $paths.Add(@($Start,[pscustomobject]@{X=$Start.X;Y=$y},[pscustomobject]@{X=$End.X;Y=$y},$End)) }
    foreach ($path in $paths) {
        $candidatePoints=@(Compress-Points $path $Tolerance)
        if($candidatePoints.Count-lt2){continue}
        $firstDirection=Get-SegmentDirection $candidatePoints[0] $candidatePoints[1] $Tolerance
        $lastDirection=Get-SegmentDirection $candidatePoints[$candidatePoints.Count-2] $candidatePoints[$candidatePoints.Count-1] $Tolerance
        if($ExitDirections.Count-gt0-and$firstDirection-notin$ExitDirections){continue}
        if($EntryDirections.Count-gt0-and$lastDirection-notin$EntryDirections){continue}
        $clear = $true
        for ($index=1; $index -lt $path.Count; $index++) { if (-not (Test-SegmentClear $path[$index-1] $path[$index] $Obstacles $Tolerance)) { $clear=$false; break } }
        if ($clear) { $candidates.Add((Get-PathMetrics $path $Tolerance)) }
    }
    if ($candidates.Count -eq 0) { return $null }
    $candidates | Sort-Object BendCount,Length | Select-Object -First 1
}

function Add-Issue {
    param([string]$Type,[string]$Element,[string]$Detail,[object]$Coordinates,[string]$Evidence,[string]$RepairClass,[string]$Severity='ERROR')
    $issues.Add([pscustomobject]@{ Severity=$Severity; Type=$Type; Element=$Element; Detail=$Detail; Coordinates=$Coordinates; Evidence=$Evidence; RepairClass=$RepairClass })
}

[xml]$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
[xml]$svg = Get-Content -LiteralPath $SvgPath -Raw -Encoding UTF8
$quality = Get-Content -LiteralPath $QualityProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$tolerance = [double]$quality.routing.orthogonalTolerance
$clearance = [double]$quality.clearance.shapeOutline
$ratioMaximum = [double]$quality.routing.lengthRatioMaximum
$absoluteTolerance = [double]$quality.routing.lengthAbsoluteTolerance
$namespace = [System.Xml.XmlNamespaceManager]::new($svg.NameTable)
$namespace.AddNamespace('s','http://www.w3.org/2000/svg')
$cells = @{}
foreach ($cell in @($source.SelectNodes('//mxCell'))) { $cells[[string]$cell.id] = $cell }
$cache = @{}
$vertexBounds = @{}
foreach ($vertex in @($source.SelectNodes('//mxCell[@vertex="1"]'))) {
    $style = Get-StyleMap ([string]$vertex.style)
    if ($style.ContainsKey('swimlane') -or [string]$vertex.id -eq 'title') { continue }
    $geometry = Get-AbsoluteGeometry $vertex $cells $cache
    $vertexBounds[[string]$vertex.id] = [pscustomobject]@{ Left=$geometry.Left-$clearance; Top=$geometry.Top-$clearance; Right=$geometry.Right+$clearance; Bottom=$geometry.Bottom+$clearance }
}

$metrics = [System.Collections.Generic.List[object]]::new()
foreach ($edge in @($source.SelectNodes('//mxCell[@edge="1"]'))) {
    $id = [string]$edge.id
    $edgeStyle=Get-StyleMap ([string]$edge.style)
    $group = $svg.SelectSingleNode("//s:g[@data-cell-id='$id']",$namespace)
    $path = if ($group) { $group.SelectSingleNode(".//s:path[@fill='none']",$namespace) } else { $null }
    if (-not $path) { Add-Issue 'missing-render-path' $id 'Rendered connector path not found' $null $id 'rerender-artifacts'; continue }
    try { $actual = Get-PathMetrics @(Get-SvgElementPoints -Element $path -Boundary $group) $tolerance }
    catch { Add-Issue 'unsupported-render-geometry' $id $_.Exception.Message $null ([string]$path.d) 'rerender-artifacts'; continue }
    if ($actual.HasDiagonal) { continue }
    $canonicalPoints = @($edge.SelectNodes('./mxGeometry/Array[@as="points"]/mxPoint') | ForEach-Object { [pscustomobject]@{X=Convert-ToNumber ([string]$_.x);Y=Convert-ToNumber ([string]$_.y)} })
    for ($index=1; $index -lt $canonicalPoints.Count; $index++) {
        if ([math]::Abs($canonicalPoints[$index].X-$canonicalPoints[$index-1].X) -le $tolerance -and [math]::Abs($canonicalPoints[$index].Y-$canonicalPoints[$index-1].Y) -le $tolerance) {
            Add-Issue 'duplicate-waypoint' $id 'Consecutive canonical waypoints are identical' $canonicalPoints[$index] "index=$index" 'remove-waypoint'
        }
    }
    $start = $actual.Points[0]
    $end = $actual.Points[$actual.Points.Count-1]
    $obstacles = @($vertexBounds.GetEnumerator() | Where-Object { $_.Key -notin @([string]$edge.source,[string]$edge.target) } | ForEach-Object { $_.Value })
    $xs = @($start.X,$end.X)+@($obstacles | ForEach-Object { $_.Left; $_.Right })
    $ys = @($start.Y,$end.Y)+@($obstacles | ForEach-Object { $_.Top; $_.Bottom })
    $exitDirections=@(Get-PortDirections $edgeStyle 'Exit' $tolerance)
    $entryDirections=@(Get-PortDirections $edgeStyle 'Entry' $tolerance)
    $best = Get-BestCandidate $start $end $obstacles @($xs|Sort-Object -Unique) @($ys|Sort-Object -Unique) $exitDirections $entryDirections $tolerance
    if ($best) {
        if ($actual.BendCount -gt $best.BendCount) {
            Add-Issue 'avoidable-bend' $id "Rendered route has $($actual.BendCount) bends; a port-compatible clear route uses $($best.BendCount)" $null "actualLength=$($actual.Length);optimalLength=$($best.Length)" 'reroute-edge' 'WARNING'
        }
        elseif ($actual.BendCount -eq $best.BendCount -and $actual.Length -gt ($best.Length*$ratioMaximum+$absoluteTolerance)) {
            Add-Issue 'route-detour' $id "Rendered route length $([math]::Round($actual.Length,2)) exceeds the port-compatible equal-bend optimum $([math]::Round($best.Length,2))" $null "ratioMaximum=$ratioMaximum;absoluteTolerance=$absoluteTolerance" 'reroute-edge' 'WARNING'
        }
    }
    $metrics.Add([pscustomobject]@{ Element=$id; SegmentCount=$actual.SegmentCount; BendCount=$actual.BendCount; Length=$actual.Length; OptimalBendCount=$(if($best){$best.BendCount}else{$null}); OptimalLength=$(if($best){$best.Length}else{$null}) })
}

$result = [pscustomobject]@{
    SchemaVersion=1
    Source=$SourcePath
    Svg=$SvgPath
    EdgeCount=$metrics.Count
    TotalBends=[int](($metrics | Measure-Object BendCount -Sum).Sum)
    TotalLength=[double](($metrics | Measure-Object Length -Sum).Sum)
    Metrics=@($metrics)
    ErrorCount=@($issues|Where-Object Severity -eq 'ERROR').Count
    WarningCount=@($issues|Where-Object Severity -eq 'WARNING').Count
    IssueCount=$issues.Count
    Issues=@($issues)
}
$result | ConvertTo-Json -Depth 8
if (@($issues|Where-Object Severity -eq 'ERROR').Count -gt 0) { exit 1 }
