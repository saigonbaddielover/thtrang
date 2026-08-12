param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string[]]$CellId,
    [switch]$IncludeIncidentEdges
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourcePath).Path
$document = [System.Xml.XmlDocument]::new()
$document.PreserveWhitespace = $true
$document.Load($source)
$cells = @($document.SelectNodes('//mxCell'))
$byId = @{}
foreach ($cell in $cells) { $byId[[string]$cell.id] = $cell }
$requestedIds = @($CellId | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
if ($requestedIds.Count -eq 0) { throw 'At least one cell ID is required' }

$selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($id in $requestedIds) {
    if (-not $byId.ContainsKey($id)) { throw "Cell not found: $id" }
    $selected.Add($id) | Out-Null
}
if ($IncludeIncidentEdges) {
    foreach ($cell in $cells) {
        if ([string]$cell.edge -eq '1' -and ([string]$cell.source -in $requestedIds -or [string]$cell.target -in $requestedIds)) {
            $selected.Add([string]$cell.id) | Out-Null
        }
    }
}

function Convert-Style {
    param([string]$Style)
    $result = [ordered]@{}
    foreach ($part in @($Style -split ';' | Where-Object { $_ })) {
        $pair = $part -split '=', 2
        $result[$pair[0]] = if ($pair.Count -eq 2) { $pair[1] } else { $true }
    }
    [pscustomobject]$result
}

function Get-AbsoluteOrigin {
    param([System.Xml.XmlElement]$Cell)
    $x = 0.0
    $y = 0.0
    $current = $Cell
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    while ($current -and $visited.Add([string]$current.id)) {
        $geometry = $current.SelectSingleNode('./mxGeometry')
        if ($geometry -and [string]$current.vertex -eq '1') {
            if ($geometry.HasAttribute('x')) { $x += [double]::Parse($geometry.x,[System.Globalization.CultureInfo]::InvariantCulture) }
            if ($geometry.HasAttribute('y')) { $y += [double]::Parse($geometry.y,[System.Globalization.CultureInfo]::InvariantCulture) }
        }
        $parentId = [string]$current.parent
        $current = if ($parentId -and $byId.ContainsKey($parentId)) { $byId[$parentId] } else { $null }
    }
    [pscustomobject]@{ X=$x; Y=$y }
}

$results = foreach ($id in @($selected | Sort-Object)) {
    $cell = $byId[$id]
    $geometry = $cell.SelectSingleNode('./mxGeometry')
    $offset = if ($geometry) { $geometry.SelectSingleNode('./mxPoint[@as="offset"]') } else { $null }
    $points = if ($geometry) { @($geometry.SelectNodes('./Array[@as="points"]/mxPoint') | ForEach-Object { [pscustomobject]@{ X=[double]$_.x; Y=[double]$_.y } }) } else { @() }
    $bounds = $null
    if ([string]$cell.vertex -eq '1' -and $geometry) {
        $origin = Get-AbsoluteOrigin $cell
        $bounds = [pscustomobject]@{
            X = $origin.X
            Y = $origin.Y
            Width = if ($geometry.HasAttribute('width')) { [double]$geometry.width } else { 0.0 }
            Height = if ($geometry.HasAttribute('height')) { [double]$geometry.height } else { 0.0 }
        }
    }
    [pscustomobject]@{
        Id = [string]$cell.id
        Kind = if ([string]$cell.edge -eq '1') { 'edge' } elseif ([string]$cell.vertex -eq '1') { 'vertex' } else { 'cell' }
        Value = [string]$cell.value
        Parent = [string]$cell.parent
        Source = [string]$cell.source
        Target = [string]$cell.target
        Style = Convert-Style ([string]$cell.style)
        Geometry = if ($geometry) { [pscustomobject]@{ X=[string]$geometry.x; Y=[string]$geometry.y; Width=[string]$geometry.width; Height=[string]$geometry.height; Relative=[string]$geometry.relative } } else { $null }
        AbsoluteBounds = $bounds
        Offset = if ($offset) { [pscustomobject]@{ X=[double]$offset.x; Y=[double]$offset.y } } else { $null }
        Waypoints = @($points)
    }
}

[pscustomobject]@{ SourcePath=$source; CellCount=@($results).Count; Cells=@($results) } | ConvertTo-Json -Depth 8
