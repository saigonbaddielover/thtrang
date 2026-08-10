param(
    [Parameter(Mandatory = $true)]
    [string]$FileName
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$canonicalFileName = [System.IO.Path]::GetFileName($FileName)
if ($canonicalFileName -ne $FileName -or [System.IO.Path]::GetExtension($FileName) -ne '.xml') {
    throw "FileName must be a canonical XML file name without a path: $FileName"
}

$sourcePath = Join-Path (Join-Path $projectDirectory 'drawio-src') $FileName
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
$wrapperDirectory = Join-Path (Join-Path $projectDirectory 'assets') 'drawio'
$wrapperPath = Join-Path $wrapperDirectory ($baseName + '.drawio')

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Canonical source not found: $sourcePath"
}
if (-not (Test-Path -LiteralPath $wrapperPath)) {
    throw "Draw.io wrapper not found: $wrapperPath"
}

[xml]$wrapper = Get-Content -LiteralPath $wrapperPath -Raw -Encoding UTF8
$diagrams = @($wrapper.SelectNodes('/mxfile/diagram'))
if ($diagrams.Count -ne 1) {
    throw "Wrapper must contain exactly one diagram element: $wrapperPath"
}
$diagram = $diagrams[0]

$canonical = (Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8).Trim()
[xml]$canonicalDocument = $canonical
if ($canonicalDocument.DocumentElement.Name -ne 'mxGraphModel') {
    throw "Canonical source root must be mxGraphModel: $sourcePath"
}

$diagramId = [System.Security.SecurityElement]::Escape([string]$diagram.id)
$diagramName = [System.Security.SecurityElement]::Escape([string]$diagram.name)
$content = @(
    '<mxfile host="app.diagrams.net" compressed="false">'
    ('  <diagram id="{0}" name="{1}">' -f $diagramId, $diagramName)
    $canonical
    '  </diagram>'
    '</mxfile>'
) -join "`n"

$temporaryPath = Join-Path $wrapperDirectory ('.' + [System.IO.Path]::GetFileName($wrapperPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    [System.IO.File]::WriteAllText($temporaryPath, $content + "`n", [System.Text.UTF8Encoding]::new($false))
    [xml]$writtenWrapper = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8
    if (@($writtenWrapper.SelectNodes('/mxfile/diagram/mxGraphModel')).Count -ne 1) {
        throw "Generated wrapper must contain exactly one mxGraphModel: $temporaryPath"
    }
    Move-Item -LiteralPath $temporaryPath -Destination $wrapperPath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}
"SYNCED $FileName"
