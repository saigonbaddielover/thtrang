param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture

Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Core.psm1') -Force

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Type,
        [string]$Element,
        [string]$Detail
    )

    $repairClass = if ($Type -match 'geometry|bounds|containment') { 'repair-canonical-geometry' } elseif ($Type -match 'edge|anchor') { 'repair-canonical-edge' } else { 'repair-canonical-structure' }
    Add-DrawioIssue -Issues $Issues -Type $Type -Element $Element -Detail $Detail -Evidence $Detail -RepairClass $repairClass
}

function Convert-ToFiniteNumber {
    param([string]$Value)

    $number = 0.0
    if (-not [double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, $Invariant, [ref]$number)) {
        throw "Invalid numeric value: $Value"
    }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        throw "Non-finite numeric value: $Value"
    }
    $number
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

function Get-AbsoluteGeometry {
    param(
        [System.Xml.XmlElement]$Cell,
        [hashtable]$Cells,
        [hashtable]$Cache
    )

    $id = [string]$Cell.id
    if ($Cache.ContainsKey($id)) {
        return $Cache[$id]
    }
    $geometry = $Cell.SelectSingleNode('./mxGeometry')
    $bounds = [pscustomobject]@{
        X = Convert-ToFiniteNumber ([string]$geometry.x)
        Y = Convert-ToFiniteNumber ([string]$geometry.y)
        Width = Convert-ToFiniteNumber ([string]$geometry.width)
        Height = Convert-ToFiniteNumber ([string]$geometry.height)
    }
    $parentId = [string]$Cell.parent
    if ($Cells.ContainsKey($parentId) -and [string]$Cells[$parentId].vertex -eq '1') {
        $parentBounds = Get-AbsoluteGeometry $Cells[$parentId] $Cells $Cache
        $bounds.X += $parentBounds.X
        $bounds.Y += $parentBounds.Y
    }
    $Cache[$id] = $bounds
    $bounds
}

$issues = [System.Collections.Generic.List[object]]::new()
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    Add-Issue $issues 'missing-source' '' $SourcePath
}

$document = $null
if ($issues.Count -eq 0) {
    try {
        [xml]$document = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
    }
    catch {
        Add-Issue $issues 'xml-parse' '' $_.Exception.Message
    }
}

$cells = @{}
$pageWidth = 0.0
$pageHeight = 0.0
if ($document) {
    $model = $document.DocumentElement
    if ($model.Name -ne 'mxGraphModel') {
        Add-Issue $issues 'invalid-root' '' "Expected mxGraphModel, found $($model.Name)"
    }
    else {
        try {
            $pageWidth = Convert-ToFiniteNumber ([string]$model.pageWidth)
            $pageHeight = Convert-ToFiniteNumber ([string]$model.pageHeight)
            if ($pageWidth -le 0 -or $pageHeight -le 0) {
                Add-Issue $issues 'invalid-page' '' 'Page width and height must be positive'
            }
        }
        catch {
            Add-Issue $issues 'invalid-page' '' $_.Exception.Message
        }
    }

    foreach ($cell in $document.SelectNodes('//mxCell')) {
        $id = [string]$cell.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            Add-Issue $issues 'missing-id' '' 'mxCell has no id'
            continue
        }
        if ($cells.ContainsKey($id)) {
            Add-Issue $issues 'duplicate-id' $id 'ID is not unique'
            continue
        }
        $cells[$id] = $cell
    }

    foreach ($requiredId in @('0', '1')) {
        if (-not $cells.ContainsKey($requiredId)) {
            Add-Issue $issues 'missing-structural-cell' $requiredId 'Required structural cell is missing'
        }
    }

    foreach ($cell in $cells.Values) {
        $id = [string]$cell.id
        $parentId = [string]$cell.parent
        if ($parentId -and -not $cells.ContainsKey($parentId)) {
            Add-Issue $issues 'invalid-parent' $id $parentId
        }

        $seen = @{}
        $cursor = $cell
        while ($cursor -and [string]$cursor.parent) {
            $nextId = [string]$cursor.parent
            if ($seen.ContainsKey($nextId)) {
                Add-Issue $issues 'parent-cycle' $id $nextId
                break
            }
            $seen[$nextId] = $true
            if (-not $cells.ContainsKey($nextId)) { break }
            $cursor = $cells[$nextId]
        }

        $isVertex = [string]$cell.vertex -eq '1'
        $isEdge = [string]$cell.edge -eq '1'
        if ($isVertex -or $isEdge) {
            $geometry = $cell.SelectSingleNode('./mxGeometry')
            if (-not $geometry) {
                Add-Issue $issues 'missing-geometry' $id 'mxGeometry is required'
                continue
            }
        }

        if ($isVertex) {
            if ([string]::IsNullOrWhiteSpace([string]$cell.style)) {
                Add-Issue $issues 'missing-style' $id 'Vertex style is empty'
            }
            elseif ([string]$cell.style -match '(?:^|;)shape=(?:;|$)') {
                Add-Issue $issues 'invalid-shape' $id 'Shape identifier is empty'
            }
            try {
                $geometry = $cell.SelectSingleNode('./mxGeometry')
                $x = Convert-ToFiniteNumber ([string]$geometry.x)
                $y = Convert-ToFiniteNumber ([string]$geometry.y)
                $width = Convert-ToFiniteNumber ([string]$geometry.width)
                $height = Convert-ToFiniteNumber ([string]$geometry.height)
                if ($width -le 0 -or $height -le 0) {
                    Add-Issue $issues 'non-positive-geometry' $id "$width x $height"
                }
                $parent = if ($cells.ContainsKey($parentId)) { $cells[$parentId] } else { $null }
                if ($parent -and [string]$parent.vertex -eq '1' -and [string]$parent.style -match '(?:^|;)swimlane;') {
                    $parentGeometry = $parent.SelectSingleNode('./mxGeometry')
                    $parentWidth = Convert-ToFiniteNumber ([string]$parentGeometry.width)
                    $parentHeight = Convert-ToFiniteNumber ([string]$parentGeometry.height)
                    $parentStyle = Get-StyleMap ([string]$parent.style)
                    $startSize = if ($parentStyle.ContainsKey('startSize')) { Convert-ToFiniteNumber $parentStyle.startSize } else { 0.0 }
                    $horizontal = -not $parentStyle.ContainsKey('horizontal') -or $parentStyle.horizontal -ne '0'
                    $minimumX = if ($horizontal) { 0.0 } else { $startSize }
                    $minimumY = if ($horizontal) { $startSize } else { 0.0 }
                    if ($x -lt $minimumX -or $y -lt $minimumY -or ($x + $width) -gt $parentWidth -or ($y + $height) -gt $parentHeight) {
                        Add-Issue $issues 'lane-containment' $id "Child geometry exceeds lane client area $parentId"
                    }
                }
            }
            catch {
                Add-Issue $issues 'invalid-geometry' $id $_.Exception.Message
            }
        }

        if ($isEdge) {
            $sourceId = [string]$cell.source
            $targetId = [string]$cell.target
            if (-not $cells.ContainsKey($sourceId) -or [string]$cells[$sourceId].vertex -ne '1') {
                Add-Issue $issues 'invalid-edge-source' $id $sourceId
            }
            if (-not $cells.ContainsKey($targetId) -or [string]$cells[$targetId].vertex -ne '1') {
                Add-Issue $issues 'invalid-edge-target' $id $targetId
            }
            $geometry = $cell.SelectSingleNode('./mxGeometry')
            if ([string]$geometry.relative -ne '1') {
                Add-Issue $issues 'edge-geometry-relative' $id 'Expected relative=1'
            }
            foreach ($point in $geometry.SelectNodes('.//mxPoint')) {
                foreach ($axis in @('x', 'y')) {
                    $value = [string]$point.GetAttribute($axis)
                    if ($value) {
                        try { [void](Convert-ToFiniteNumber $value) }
                        catch { Add-Issue $issues 'invalid-waypoint' $id "$axis=$value" }
                    }
                }
            }
            $style = Get-StyleMap ([string]$cell.style)
            foreach ($anchor in @('exitX', 'exitY', 'entryX', 'entryY')) {
                if ($style.ContainsKey($anchor)) {
                    try {
                        $value = Convert-ToFiniteNumber $style[$anchor]
                        if ($value -lt 0 -or $value -gt 1) {
                            Add-Issue $issues 'invalid-anchor' $id "$anchor=$value"
                        }
                    }
                    catch {
                        Add-Issue $issues 'invalid-anchor' $id "$anchor=$($style[$anchor])"
                    }
                }
            }
        }
    }

    $geometryCache = @{}
    foreach ($cell in $cells.Values | Where-Object { [string]$_.vertex -eq '1' }) {
        try {
            $bounds = Get-AbsoluteGeometry $cell $cells $geometryCache
            if ($bounds.X -lt 0 -or $bounds.Y -lt 0 -or ($bounds.X + $bounds.Width) -gt $pageWidth -or ($bounds.Y + $bounds.Height) -gt $pageHeight) {
                Add-Issue $issues 'page-bounds' ([string]$cell.id) "x=$($bounds.X), y=$($bounds.Y), width=$($bounds.Width), height=$($bounds.Height)"
            }
        }
        catch {
            Add-Issue $issues 'absolute-geometry' ([string]$cell.id) $_.Exception.Message
        }
    }
}

$uniqueIssues = @($issues | Sort-Object Type, Element, Detail -Unique)
$result = [pscustomobject]@{
    Source = $SourcePath
    CellCount = $cells.Count
    VertexCount = @($cells.Values | Where-Object { [string]$_.vertex -eq '1' }).Count
    EdgeCount = @($cells.Values | Where-Object { [string]$_.edge -eq '1' }).Count
    ErrorCount = @($uniqueIssues | Where-Object Severity -eq 'ERROR').Count
    WarningCount = @($uniqueIssues | Where-Object Severity -eq 'WARNING').Count
    IssueCount = $uniqueIssues.Count
    Issues = $uniqueIssues
}
$result | ConvertTo-Json -Depth 6
if ($result.IssueCount -gt 0) { exit 1 }
