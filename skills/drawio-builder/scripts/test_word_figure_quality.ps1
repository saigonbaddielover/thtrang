param([string]$SkillPath = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$scratchBase = Join-Path $SkillPath '.tmp'
$scratch = Join-Path $scratchBase ('drawio-word-quality-' + [guid]::NewGuid().ToString('N'))
$results = [System.Collections.Generic.List[object]]::new()

function Write-Utf8File {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path,$Content,[System.Text.UTF8Encoding]::new($false))
}

function Invoke-Child {
    param([string]$Path,[string[]]$Arguments)
    $preference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output=@(& $engine -NoProfile -File $Path @Arguments 2>&1);$exitCode=$LASTEXITCODE }
    finally { $ErrorActionPreference=$preference }
    [pscustomobject]@{ExitCode=$exitCode;Output=($output-join"`n")}
}

function Add-Result {
    param([string]$Name,[bool]$Passed,[string]$Detail)
    $results.Add([pscustomobject]@{Name=$Name;Passed=$Passed;Detail=$Detail})
}

if(-not(Test-Path -LiteralPath $scratchBase)){New-Item -ItemType Directory -Path $scratchBase|Out-Null}
New-Item -ItemType Directory -Path $scratch|Out-Null
try{
    $canonical=Join-Path $scratch 'figure.xml'
    $detourSvg=Join-Path $scratch 'detour.svg'
    $cleanSvg=Join-Path $scratch 'clean.svg'
    $parallelCanonical=Join-Path $scratch 'parallel-ports.xml'
    $parallelSvg=Join-Path $scratch 'parallel-ports.svg'
    $nestedCanonical=Join-Path $scratch 'nested-obstacle.xml'
    $nestedSvg=Join-Path $scratch 'nested-obstacle.svg'
    $crossingCanonical=Join-Path $scratch 'crossing-shortcut.xml'
    $crossingSvg=Join-Path $scratch 'crossing-shortcut.svg'
    Write-Utf8File $canonical @'
<mxGraphModel grid="1" page="1" pageWidth="827" pageHeight="1169"><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="a" value="Start" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="100" y="100" width="100" height="60" as="geometry"/></mxCell><mxCell id="b" value="Finish" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="500" y="100" width="100" height="60" as="geometry"/></mxCell><mxCell id="e" value="Flow" style="edgeStyle=orthogonalEdgeStyle;fontSize=10;endArrow=classic;exitX=1;exitY=0.5;entryX=0;entryY=0.5;" edge="1" parent="1" source="a" target="b"><mxGeometry relative="1" as="geometry"/></mxCell></root></mxGraphModel>
'@
    Write-Utf8File $detourSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"><g data-cell-id="e"><path fill="none" stroke="#000" d="M 200 130 L 300 130 L 300 180 L 500 180 L 500 130"/></g></svg>'
    Write-Utf8File $cleanSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"><g data-cell-id="e"><path fill="none" stroke="#000" d="M 200 130 L 500 130"/></g></svg>'
    $profile=Join-Path $SkillPath 'assets\quality-profile.json'
    $composition=Invoke-Child (Join-Path $PSScriptRoot 'audit_drawio_composition.ps1') @('-SourcePath',$canonical,'-QualityProfilePath',$profile)
    Add-Result 'compact-word-figure-passes' ($composition.ExitCode-eq0) $composition.Output
    $detour=Invoke-Child (Join-Path $PSScriptRoot 'audit_drawio_route_efficiency.ps1') @('-SourcePath',$canonical,'-SvgPath',$detourSvg,'-QualityProfilePath',$profile)
    $detourData=$detour.Output|ConvertFrom-Json
    Add-Result 'avoidable-bend-reported-without-false-blocking' ($detour.ExitCode-eq0-and$detourData.WarningCount-eq1-and'avoidable-bend'-in@($detourData.Issues.Type)) $detour.Output
    $clean=Invoke-Child (Join-Path $PSScriptRoot 'audit_drawio_route_efficiency.ps1') @('-SourcePath',$canonical,'-SvgPath',$cleanSvg,'-QualityProfilePath',$profile)
    Add-Result 'minimum-bend-route-passes' ($clean.ExitCode-eq0) $clean.Output
    Write-Utf8File $parallelCanonical @'
<mxGraphModel grid="1" page="1" pageWidth="827" pageHeight="1169"><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="a" value="Start" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="300" y="100" width="100" height="60" as="geometry"/></mxCell><mxCell id="b" value="Finish" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="100" y="300" width="100" height="60" as="geometry"/></mxCell><mxCell id="e" value="Flow" style="edgeStyle=orthogonalEdgeStyle; fontSize=10; endArrow=classic; exitX=0.5; exitY=1; entryX=0.5; entryY=0;" edge="1" parent="1" source="a" target="b"><mxGeometry relative="1" as="geometry"><Array as="points"><mxPoint x="350" y="220"/><mxPoint x="150" y="220"/></Array></mxGeometry></mxCell></root></mxGraphModel>
'@
    Write-Utf8File $parallelSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"><g data-cell-id="e"><path fill="none" stroke="#000" d="M 350 160 L 350 220 L 150 220 L 150 300"/></g></svg>'
    $parallel=Invoke-Child (Join-Path $PSScriptRoot 'audit_drawio_route_efficiency.ps1') @('-SourcePath',$parallelCanonical,'-SvgPath',$parallelSvg,'-QualityProfilePath',$profile)
    $parallelData=$parallel.Output|ConvertFrom-Json
    Add-Result 'parallel-normal-ports-require-two-bends' ($parallel.ExitCode-eq0-and$parallelData.WarningCount-eq0-and$parallelData.Metrics[0].BendCount-eq2) $parallel.Output
    Write-Utf8File $nestedCanonical @'
<mxGraphModel grid="1" page="1" pageWidth="827" pageHeight="1169"><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="lane" value="Lane" style="swimlane;horizontal=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="300" y="100" width="300" height="400" as="geometry"/></mxCell><mxCell id="obstacle" value="Obstacle" style="rounded=1;fontSize=11;" vertex="1" parent="lane"><mxGeometry x="100" y="100" width="100" height="60" as="geometry"/></mxCell><mxCell id="a" value="Start" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="100" y="200" width="100" height="60" as="geometry"/></mxCell><mxCell id="b" value="Finish" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="600" y="400" width="100" height="60" as="geometry"/></mxCell><mxCell id="e" value="Flow" style="edgeStyle=orthogonalEdgeStyle;fontSize=10;endArrow=classic;exitX=1;exitY=0.5;entryX=0.5;entryY=0;" edge="1" parent="1" source="a" target="b"><mxGeometry relative="1" as="geometry"><Array as="points"><mxPoint x="300" y="230"/><mxPoint x="300" y="150"/><mxPoint x="650" y="150"/></Array></mxGeometry></mxCell></root></mxGraphModel>
'@
    Write-Utf8File $nestedSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"><g data-cell-id="e"><path fill="none" stroke="#000" d="M 200 230 L 300 230 L 300 150 L 650 150 L 650 400"/></g></svg>'
    $nested=Invoke-Child (Join-Path $PSScriptRoot 'audit_drawio_route_efficiency.ps1') @('-SourcePath',$nestedCanonical,'-SvgPath',$nestedSvg,'-QualityProfilePath',$profile)
    $nestedData=$nested.Output|ConvertFrom-Json
    Add-Result 'nested-lane-obstacle-rejects-false-shortcut' ($nested.ExitCode-eq0-and$nestedData.WarningCount-eq0-and$null-eq$nestedData.Metrics[0].OptimalBendCount) $nested.Output
    Write-Utf8File $crossingCanonical @'
<mxGraphModel grid="1" page="1" pageWidth="827" pageHeight="1169"><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="a" value="Start" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="100" y="100" width="100" height="60" as="geometry"/></mxCell><mxCell id="b" value="Finish" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="500" y="300" width="100" height="60" as="geometry"/></mxCell><mxCell id="c" value="Upper" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="325" y="20" width="50" height="30" as="geometry"/></mxCell><mxCell id="d" value="Lower" style="rounded=1;fontSize=11;" vertex="1" parent="1"><mxGeometry x="325" y="410" width="50" height="30" as="geometry"/></mxCell><mxCell id="e" value="Flow" style="edgeStyle=orthogonalEdgeStyle;fontSize=10;endArrow=classic;exitX=1;exitY=0.5;entryX=0;entryY=0.5;" edge="1" parent="1" source="a" target="b"><mxGeometry relative="1" as="geometry"><Array as="points"><mxPoint x="250" y="130"/><mxPoint x="250" y="390"/><mxPoint x="500" y="390"/></Array></mxGeometry></mxCell><mxCell id="blocker" value="Existing" style="edgeStyle=orthogonalEdgeStyle;fontSize=10;endArrow=classic;exitX=0.5;exitY=1;entryX=0.5;entryY=0;" edge="1" parent="1" source="c" target="d"><mxGeometry relative="1" as="geometry"/></mxCell></root></mxGraphModel>
'@
    Write-Utf8File $crossingSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"><g data-cell-id="e"><path fill="none" stroke="#000" d="M 200 130 L 250 130 L 250 390 L 500 390 L 500 330"/></g><g data-cell-id="blocker"><path fill="none" stroke="#000" d="M 350 50 L 350 410"/></g></svg>'
    $crossing=Invoke-Child (Join-Path $PSScriptRoot 'audit_drawio_route_efficiency.ps1') @('-SourcePath',$crossingCanonical,'-SvgPath',$crossingSvg,'-QualityProfilePath',$profile)
    $crossingData=$crossing.Output|ConvertFrom-Json
    $crossingMetric=@($crossingData.Metrics|Where-Object Element -eq 'e')[0]
    $crossingIssues=@($crossingData.Issues|Where-Object Element -eq 'e')
    Add-Result 'existing-route-rejects-crossing-shortcut' ($crossing.ExitCode-eq0-and'avoidable-bend'-notin@($crossingIssues.Type)-and($null-eq$crossingMetric.OptimalBendCount-or$crossingMetric.OptimalBendCount-ge$crossingMetric.BendCount)) $crossing.Output
    $failed=@($results|Where-Object{-not$_.Passed})
    [pscustomobject]@{Engine=$engine;Version=$PSVersionTable.PSVersion.ToString();TestCount=$results.Count;FailedCount=$failed.Count;Tests=@($results)}|ConvertTo-Json -Depth 6
    if($failed.Count-gt0){exit 1}
}
finally{
    $resolvedScratch=[System.IO.Path]::GetFullPath($scratch)
    $resolvedBase=[System.IO.Path]::GetFullPath($scratchBase)
    if($resolvedScratch.StartsWith($resolvedBase,[System.StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $resolvedScratch)){[System.IO.Directory]::Delete($resolvedScratch,$true)}
}
