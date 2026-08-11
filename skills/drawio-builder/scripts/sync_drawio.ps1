param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('FromDrawio', 'ToDrawio')]
    [string]$Direction,

    [Parameter(Mandatory = $true)]
    [string]$CanonicalPath,

    [Parameter(Mandatory = $true)]
    [string]$DrawioPath,

    [string]$PageId,
    [string]$PageName
)

$ErrorActionPreference = 'Stop'

function Expand-Diagram {
    param([System.Xml.XmlElement]$Diagram)

    $embedded = $Diagram.SelectSingleNode('./mxGraphModel')
    if ($embedded) {
        return $embedded.OuterXml
    }
    $payload = ([string]$Diagram.InnerText).Trim()
    if (-not $payload) {
        throw "Diagram page has no mxGraphModel payload: $($Diagram.id)"
    }
    $bytes = [Convert]::FromBase64String($payload)
    $input = [System.IO.MemoryStream]::new($bytes)
    $deflate = [System.IO.Compression.DeflateStream]::new($input, [System.IO.Compression.CompressionMode]::Decompress)
    $output = [System.IO.MemoryStream]::new()
    try {
        $deflate.CopyTo($output)
        $encoded = [System.Text.Encoding]::UTF8.GetString($output.ToArray())
        [uri]::UnescapeDataString($encoded)
    }
    finally {
        $output.Dispose()
        $deflate.Dispose()
        $input.Dispose()
    }
}

function Select-DiagramPage {
    param(
        [System.Xml.XmlElement[]]$Diagrams,
        [string]$RequestedId
    )

    if ($RequestedId) {
        $selected = @($Diagrams | Where-Object { [string]$_.id -eq $RequestedId })
        if ($selected.Count -ne 1) {
            throw "PageId not found or not unique: $RequestedId"
        }
        return $selected[0]
    }
    if ($Diagrams.Count -ne 1) {
        $available = @($Diagrams | ForEach-Object { "$($_.id)=$($_.name)" }) -join ', '
        throw "PageId is required for a multi-page file. Available pages: $available"
    }
    $Diagrams[0]
}

function Write-AtomicUtf8 {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not $directory) { $directory = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporaryPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

if ($Direction -eq 'FromDrawio') {
    if (-not (Test-Path -LiteralPath $DrawioPath -PathType Leaf)) {
        throw "Draw.io file not found: $DrawioPath"
    }
    [xml]$wrapper = Get-Content -LiteralPath $DrawioPath -Raw -Encoding UTF8
    $diagrams = @($wrapper.SelectNodes('/mxfile/diagram'))
    if ($diagrams.Count -eq 0) { throw "No diagram pages found: $DrawioPath" }
    $selected = Select-DiagramPage $diagrams $PageId
    $modelText = (Expand-Diagram $selected).Trim()
    [xml]$model = $modelText
    if ($model.DocumentElement.Name -ne 'mxGraphModel') {
        throw "Selected page is not an mxGraphModel: $($selected.id)"
    }
    $directory = Split-Path -Parent $CanonicalPath
    if (-not $directory) { $directory = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $candidate = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($CanonicalPath) + '.' + [guid]::NewGuid().ToString('N') + '.candidate')
    try {
        [System.IO.File]::WriteAllText($candidate, $model.OuterXml + "`n", [System.Text.UTF8Encoding]::new($false))
        $preflight = Join-Path $PSScriptRoot 'preflight_drawio.ps1'
        $preflightResult = @(& $preflight -SourcePath $candidate) -join "`n" | ConvertFrom-Json
        if ([int]$preflightResult.IssueCount -ne 0) { throw 'Imported page failed canonical preflight' }
        Move-Item -LiteralPath $candidate -Destination $CanonicalPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force }
    }
    [pscustomobject]@{ Direction='FromDrawio'; Canonical=$CanonicalPath; Drawio=$DrawioPath; PageId=[string]$selected.id; PageName=[string]$selected.name } | ConvertTo-Json
    exit 0
}

if (-not (Test-Path -LiteralPath $CanonicalPath -PathType Leaf)) {
    throw "Canonical XML not found: $CanonicalPath"
}
$preflightResult = @(& (Join-Path $PSScriptRoot 'preflight_drawio.ps1') -SourcePath $CanonicalPath) -join "`n" | ConvertFrom-Json
if ([int]$preflightResult.IssueCount -ne 0) { throw 'Canonical source failed preflight' }
[xml]$canonical = Get-Content -LiteralPath $CanonicalPath -Raw -Encoding UTF8

if (Test-Path -LiteralPath $DrawioPath -PathType Leaf) {
    [xml]$wrapper = Get-Content -LiteralPath $DrawioPath -Raw -Encoding UTF8
    $diagrams = @($wrapper.SelectNodes('/mxfile/diagram'))
    if ($diagrams.Count -eq 0) { throw "No diagram pages found: $DrawioPath" }
    $selected = Select-DiagramPage $diagrams $PageId
    $selectedId = [string]$selected.id
    foreach ($diagram in $diagrams) {
        $expanded = Expand-Diagram $diagram
        $existingId = [string]$diagram.id
        $existingName = [string]$diagram.name
        $diagram.RemoveAll()
        $diagram.SetAttribute('id', $existingId)
        $diagram.SetAttribute('name', $existingName)
        $fragment = $wrapper.CreateDocumentFragment()
        $fragment.InnerXml = $expanded
        [void]$diagram.AppendChild($fragment)
    }
    $selected = Select-DiagramPage @($wrapper.SelectNodes('/mxfile/diagram')) $selectedId
    $targetId = [string]$selected.id
    $targetName = [string]$selected.name
    $selected.RemoveAll()
    $updatedId = if ($PageId) { $PageId } else { $targetId }
    $updatedName = if ($PageName) { $PageName } else { $targetName }
    $selected.SetAttribute('id', $updatedId)
    $selected.SetAttribute('name', $updatedName)
    $canonicalNode = $wrapper.ImportNode($canonical.DocumentElement, $true)
    [void]$selected.AppendChild($canonicalNode)
    $wrapper.DocumentElement.SetAttribute('compressed', 'false')
}
else {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($DrawioPath)
    $createdId = if ($PageId) { $PageId } else { ($baseName -replace '[^A-Za-z0-9_-]', '-') }
    $createdName = if ($PageName) { $PageName } else { $baseName }
    [xml]$wrapper = '<mxfile host="app.diagrams.net" compressed="false"></mxfile>'
    $diagram = $wrapper.CreateElement('diagram')
    $diagram.SetAttribute('id', $createdId)
    $diagram.SetAttribute('name', $createdName)
    [void]$diagram.AppendChild($wrapper.ImportNode($canonical.DocumentElement, $true))
    [void]$wrapper.DocumentElement.AppendChild($diagram)
    $selected = $diagram
}

Write-AtomicUtf8 $DrawioPath ($wrapper.OuterXml + "`n")
[pscustomobject]@{ Direction='ToDrawio'; Canonical=$CanonicalPath; Drawio=$DrawioPath; PageId=[string]$selected.id; PageName=[string]$selected.name } | ConvertTo-Json
