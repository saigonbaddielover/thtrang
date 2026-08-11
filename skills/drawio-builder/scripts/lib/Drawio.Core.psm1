Set-StrictMode -Version 2.0

$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-DrawioNumber {
    param(
        [AllowNull()]
        [object]$Value,
        [double]$Default = 0.0,
        [switch]$AllowMissing
    )
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        if ($AllowMissing) { return $Default }
        throw 'Numeric value is missing'
    }
    $number = 0.0
    if (-not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, $script:Invariant, [ref]$number)) {
        throw "Invalid numeric value: $Value"
    }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        throw "Non-finite numeric value: $Value"
    }
    $number
}

function Get-DrawioStyleMap {
    param([AllowNull()][string]$Style)
    $map = @{}
    if ([string]::IsNullOrEmpty($Style)) { return $map }
    foreach ($part in $Style.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $pair = $part.Split('=', 2)
        if ($pair.Count -eq 2) { $map[$pair[0]] = $pair[1] } else { $map[$part] = '1' }
    }
    $map
}

function New-DrawioIssue {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [AllowEmptyString()][string]$Element = '',
        [Parameter(Mandatory = $true)][string]$Detail,
        [ValidateSet('ERROR', 'WARNING', 'INFO')][string]$Severity = 'ERROR',
        [AllowNull()][object]$Coordinates,
        [AllowNull()][object]$Evidence,
        [string]$RepairClass = 'manual-review'
    )
    [pscustomobject][ordered]@{
        Severity = $Severity
        Type = $Type
        Element = $Element
        Detail = $Detail
        Coordinates = $Coordinates
        Evidence = $Evidence
        RepairClass = $RepairClass
    }
}

function Add-DrawioIssue {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IList]$Issues,
        [Parameter(Mandatory = $true)][string]$Type,
        [AllowEmptyString()][string]$Element = '',
        [Parameter(Mandatory = $true)][string]$Detail,
        [ValidateSet('ERROR', 'WARNING', 'INFO')][string]$Severity = 'ERROR',
        [AllowNull()][object]$Coordinates,
        [AllowNull()][object]$Evidence,
        [string]$RepairClass = 'manual-review'
    )
    [void]$Issues.Add((New-DrawioIssue -Type $Type -Element $Element -Detail $Detail -Severity $Severity -Coordinates $Coordinates -Evidence $Evidence -RepairClass $RepairClass))
}

function Get-DrawioCells {
    param([Parameter(Mandatory = $true)][xml]$Document)
    $cells = @{}
    foreach ($cell in $Document.SelectNodes('//mxCell')) {
        $id = [string]$cell.id
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $cells.ContainsKey($id)) { $cells[$id] = $cell }
    }
    $cells
}

function Get-DrawioAbsoluteGeometry {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlElement]$Cell,
        [Parameter(Mandatory = $true)][hashtable]$Cells,
        [Parameter(Mandatory = $true)][hashtable]$Cache
    )
    $id = [string]$Cell.id
    if ($Cache.ContainsKey($id)) { return $Cache[$id] }
    $geometry = $Cell.SelectSingleNode('./mxGeometry')
    if (-not $geometry) { throw "Element has no mxGeometry: $id" }
    $bounds = [pscustomobject]@{
        X = ConvertTo-DrawioNumber $geometry.x -AllowMissing
        Y = ConvertTo-DrawioNumber $geometry.y -AllowMissing
        Width = ConvertTo-DrawioNumber $geometry.width -AllowMissing
        Height = ConvertTo-DrawioNumber $geometry.height -AllowMissing
    }
    $parentId = [string]$Cell.parent
    if ($Cells.ContainsKey($parentId) -and [string]$Cells[$parentId].vertex -eq '1') {
        $parentBounds = Get-DrawioAbsoluteGeometry -Cell $Cells[$parentId] -Cells $Cells -Cache $Cache
        $bounds.X += $parentBounds.X
        $bounds.Y += $parentBounds.Y
    }
    $Cache[$id] = $bounds
    $bounds
}

function ConvertTo-DrawioBox {
    param([Parameter(Mandatory = $true)][object]$Geometry)
    [pscustomobject]@{
        Left = [double]$Geometry.X
        Top = [double]$Geometry.Y
        Right = [double]$Geometry.X + [double]$Geometry.Width
        Bottom = [double]$Geometry.Y + [double]$Geometry.Height
    }
}

function Test-DrawioBoxOverlap {
    param(
        [Parameter(Mandatory = $true)][object]$A,
        [Parameter(Mandatory = $true)][object]$B,
        [double]$MinimumOverlap = 0.0
    )
    ([math]::Min($A.Right, $B.Right) - [math]::Max($A.Left, $B.Left) -gt $MinimumOverlap) -and
        ([math]::Min($A.Bottom, $B.Bottom) - [math]::Max($A.Top, $B.Top) -gt $MinimumOverlap)
}

Export-ModuleMember -Function ConvertTo-DrawioNumber, Get-DrawioStyleMap, New-DrawioIssue, Add-DrawioIssue, Get-DrawioCells, Get-DrawioAbsoluteGeometry, ConvertTo-DrawioBox, Test-DrawioBoxOverlap
