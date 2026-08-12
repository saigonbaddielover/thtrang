param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot),
    [switch]$IncludeDetails
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$scratchBase = Join-Path $SkillPath '.tmp'
$scratch = Join-Path $scratchBase ('drawio-cell-tools-' + [guid]::NewGuid().ToString('N'))
$results = [System.Collections.Generic.List[object]]::new()

function Write-Utf8File {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path,$Content,[System.Text.UTF8Encoding]::new($false))
}

function Invoke-Child {
    param([string]$Path,[string[]]$Arguments)
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output=@(& $engine -NoProfile -File $Path @Arguments 2>&1);$exitCode=$LASTEXITCODE }
    finally { $ErrorActionPreference=$prior }
    [pscustomobject]@{ ExitCode=$exitCode; Output=($output-join"`n") }
}

function Add-Result {
    param([string]$Name,[bool]$Passed,[string]$Detail)
    $results.Add([pscustomobject]@{ Name=$Name; Passed=$Passed; Detail=$Detail })
}

if (-not (Test-Path -LiteralPath $scratchBase)) { New-Item -ItemType Directory -Path $scratchBase | Out-Null }
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $canonical = Join-Path $scratch 'diagram.xml'
    $patch = Join-Path $scratch 'patch.json'
    Write-Utf8File $canonical @'
<mxGraphModel page="1" pageWidth="827" pageHeight="1169">
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <mxCell id="lane" vertex="1" parent="1" style="swimlane=1;"><mxGeometry x="10" y="20" width="400" height="500" as="geometry"/></mxCell>
    <mxCell id="a" value="Before" vertex="1" parent="lane" style="rounded=1;fillColor=#ffffff;"><mxGeometry x="30" y="40" width="100" height="50" as="geometry"/></mxCell>
    <mxCell id="b" value="Target" vertex="1" parent="lane" style="rounded=1;"><mxGeometry x="250" y="40" width="100" height="50" as="geometry"/></mxCell>
    <mxCell id="e" value="Old" edge="1" parent="lane" source="a" target="b" style="edgeStyle=orthogonalEdgeStyle;exitX=1;entryX=0;">
      <mxGeometry relative="1" as="geometry">
        <mxPoint x="0" y="-10" as="offset"/>
        <Array as="points">
          <mxPoint x="180" y="65"/>
        </Array>
      </mxGeometry>
    </mxCell>
  </root>
</mxGraphModel>
'@
    Write-Utf8File $patch '{"updates":[{"id":"a","value":"After","style":{"fillColor":"#ddeeff","rounded":null},"geometry":{"x":35}},{"id":"e","value":"Flow","style":{"exitY":"0.5"},"offset":null,"waypoints":[{"x":170,"y":65},{"x":210,"y":65}]}]}'
    $inspectBefore = Invoke-Child (Join-Path $PSScriptRoot 'inspect_drawio_cells.ps1') @('-SourcePath',$canonical,'-CellId','a','-IncludeIncidentEdges')
    $before = $inspectBefore.Output | ConvertFrom-Json
    Add-Result 'inspect-cell-and-incident-edge' ($inspectBefore.ExitCode -eq 0 -and $before.CellCount -eq 2 -and ($before.Cells | Where-Object Id -eq 'a').AbsoluteBounds.X -eq 40) $inspectBefore.Output
    $update = Invoke-Child (Join-Path $PSScriptRoot 'update_drawio_cells.ps1') @('-SourcePath',$canonical,'-PatchPath',$patch)
    Add-Result 'update-preflight-transaction' ($update.ExitCode -eq 0) $update.Output
    $inspectAfter = Invoke-Child (Join-Path $PSScriptRoot 'inspect_drawio_cells.ps1') @('-SourcePath',$canonical,'-CellId','a,e')
    $after = $inspectAfter.Output | ConvertFrom-Json
    $vertex = $after.Cells | Where-Object Id -eq 'a'
    $edge = $after.Cells | Where-Object Id -eq 'e'
    Add-Result 'update-value-style-and-geometry' ($vertex.Value -eq 'After' -and $vertex.Style.fillColor -eq '#ddeeff' -and $null -eq $vertex.Style.rounded -and $vertex.Geometry.X -eq '35') $inspectAfter.Output
    Add-Result 'update-offset-and-waypoints' ($edge.Value -eq 'Flow' -and $edge.Style.exitY -eq '0.5' -and $null -eq $edge.Offset -and @($edge.Waypoints).Count -eq 2) $inspectAfter.Output
    $formatted = Get-Content -LiteralPath $canonical -Raw -Encoding UTF8
    Add-Result 'update-preserves-clean-whitespace' (-not ($formatted -match '(?m)^[ \t]+$') -and $formatted -match '<Array as="points">\r?\n\s+<mxPoint') $formatted
    $hash = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
    Write-Utf8File $patch '{"updates":[{"id":"missing","value":"Never"}]}'
    $invalid = Invoke-Child (Join-Path $PSScriptRoot 'update_drawio_cells.ps1') @('-SourcePath',$canonical,'-PatchPath',$patch)
    Add-Result 'invalid-patch-preserves-source' ($invalid.ExitCode -ne 0 -and (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -eq $hash) $invalid.Output
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

$failed = @($results | Where-Object { -not $_.Passed })
$result = [ordered]@{ Passed=$failed.Count -eq 0; TestCount=$results.Count; FailedCount=$failed.Count; Failures=@($failed) }
if ($IncludeDetails) { $result.Tests = @($results) }
[pscustomobject]$result | ConvertTo-Json -Depth 6
if ($failed.Count -gt 0) { exit 1 }
