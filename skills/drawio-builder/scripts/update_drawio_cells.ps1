param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$PatchPath
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourcePath).Path
$patchFile = (Resolve-Path -LiteralPath $PatchPath).Path
$patch = Get-Content -LiteralPath $patchFile -Raw -Encoding UTF8 | ConvertFrom-Json

function Test-Property {
    param([object]$Object,[string]$Name)
    $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-Properties {
    param([object]$Object,[string[]]$Allowed,[string]$Context)
    $unknown = @($Object.PSObject.Properties.Name | Where-Object { $_ -notin $Allowed })
    if ($unknown.Count -gt 0) { throw "Unsupported $Context properties: $($unknown -join ', ')" }
}

function Set-AttributeValue {
    param([System.Xml.XmlElement]$Element,[string]$Name,[object]$Value)
    if ($null -eq $Value) { $Element.RemoveAttribute($Name) }
    else { $Element.SetAttribute($Name,[Convert]::ToString($Value,[System.Globalization.CultureInfo]::InvariantCulture)) }
}

Assert-Properties $patch @('updates') 'patch'
if (-not $patch.updates -or @($patch.updates).Count -eq 0) { throw 'Patch must contain at least one update' }

function Update-Style {
    param([System.Xml.XmlElement]$Cell,[object]$Changes)
    $order = [System.Collections.Generic.List[string]]::new()
    $values = @{}
    foreach ($part in @(([string]$Cell.style) -split ';' | Where-Object { $_ })) {
        $pair = $part -split '=', 2
        if (-not $values.ContainsKey($pair[0])) { $order.Add($pair[0]) }
        $values[$pair[0]] = if ($pair.Count -eq 2) { $pair[1] } else { $null }
    }
    foreach ($property in $Changes.PSObject.Properties) {
        if ($null -eq $property.Value) {
            $values.Remove($property.Name)
            $order.Remove($property.Name) | Out-Null
        }
        else {
            if (-not $values.ContainsKey($property.Name)) { $order.Add($property.Name) }
            $values[$property.Name] = [Convert]::ToString($property.Value,[System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
    $parts = foreach ($key in $order) {
        if ($null -eq $values[$key]) { $key } else { "$key=$($values[$key])" }
    }
    $Cell.SetAttribute('style',(($parts -join ';') + $(if ($parts.Count -gt 0) { ';' } else { '' })))
}

$document = [System.Xml.XmlDocument]::new()
$document.PreserveWhitespace = $true
$document.Load($source)
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$byId = @{}
foreach ($cellNode in @($document.SelectNodes('//mxCell'))) { $byId[[string]$cellNode.id] = $cellNode }

foreach ($update in @($patch.updates)) {
    Assert-Properties $update @('id','value','style','geometry','offset','waypoints') 'update'
    $id = [string]$update.id
    if (-not $id) { throw 'Every update requires an id' }
    if (-not $seen.Add($id)) { throw "Duplicate update id: $id" }
    if (-not $byId.ContainsKey($id)) { throw "Cell not found: $id" }
    $cell = $byId[$id]
    if (Test-Property $update 'value') { Set-AttributeValue $cell 'value' $update.value }
    if (Test-Property $update 'style') {
        if ($null -eq $update.style) { $cell.RemoveAttribute('style') }
        else { Update-Style $cell $update.style }
    }
    $geometry = $cell.SelectSingleNode('./mxGeometry')
    if ((Test-Property $update 'geometry') -or (Test-Property $update 'offset') -or (Test-Property $update 'waypoints')) {
        if (-not $geometry) { throw "Cell has no geometry: $id" }
    }
    if (Test-Property $update 'geometry') {
        if ($null -eq $update.geometry) { throw "Geometry update cannot be null: $id" }
        Assert-Properties $update.geometry @('x','y','width','height','relative') 'geometry'
        foreach ($name in @('x','y','width','height','relative')) {
            if (Test-Property $update.geometry $name) { Set-AttributeValue $geometry $name $update.geometry.$name }
        }
    }
    if (Test-Property $update 'offset') {
        $offset = $geometry.SelectSingleNode('./mxPoint[@as="offset"]')
        if ($null -eq $update.offset) {
            if ($offset) { $geometry.RemoveChild($offset) | Out-Null }
        }
        else {
            Assert-Properties $update.offset @('x','y') 'offset'
            if (-not $offset) {
                $offset = $document.CreateElement('mxPoint')
                $offset.SetAttribute('as','offset')
                $geometry.AppendChild($offset) | Out-Null
            }
            foreach ($name in @('x','y')) {
                if (Test-Property $update.offset $name) { Set-AttributeValue $offset $name $update.offset.$name }
            }
        }
    }
    if (Test-Property $update 'waypoints') {
        $pointsNode = $geometry.SelectSingleNode('./Array[@as="points"]')
        if ($pointsNode) { $geometry.RemoveChild($pointsNode) | Out-Null }
        if ($null -ne $update.waypoints -and @($update.waypoints).Count -gt 0) {
            $pointsNode = $document.CreateElement('Array')
            $pointsNode.SetAttribute('as','points')
            foreach ($point in @($update.waypoints)) {
                Assert-Properties $point @('x','y') 'waypoint'
                if (-not (Test-Property $point 'x') -or -not (Test-Property $point 'y')) { throw "Every waypoint requires x and y: $id" }
                $node = $document.CreateElement('mxPoint')
                Set-AttributeValue $node 'x' $point.x
                Set-AttributeValue $node 'y' $point.y
                $pointsNode.AppendChild($node) | Out-Null
            }
            $geometry.AppendChild($pointsNode) | Out-Null
        }
    }
}

$temporary = Join-Path (Split-Path -Parent $source) ('.drawio-update-' + [guid]::NewGuid().ToString('N') + '.xml')
$backup = $temporary + '.backup'
try {
    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.Indent = $false
    $settings.OmitXmlDeclaration = -not (Get-Content -LiteralPath $source -TotalCount 1 -Encoding UTF8).StartsWith('<?xml')
    $writer = [System.Xml.XmlWriter]::Create($temporary,$settings)
    try { $document.Save($writer) } finally { $writer.Dispose() }
    $engine = (Get-Process -Id $PID).Path
    $preflight = @(& $engine -NoProfile -File (Join-Path $PSScriptRoot 'preflight_drawio.ps1') -SourcePath $temporary 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Updated canonical failed preflight: $($preflight -join "`n")" }
    [System.IO.File]::Replace($temporary,$source,$backup)
    Remove-Item -LiteralPath $backup -Force
}
finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force }
}

[pscustomobject]@{ SourcePath=$source; PatchPath=$patchFile; UpdatedCellCount=$seen.Count; UpdatedCellIds=@($seen | Sort-Object) } | ConvertTo-Json -Depth 4
