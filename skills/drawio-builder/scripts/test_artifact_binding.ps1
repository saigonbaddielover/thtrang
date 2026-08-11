param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$audit = Join-Path $PSScriptRoot 'audit_drawio_artifacts.ps1'
$sync = Join-Path $PSScriptRoot 'sync_drawio.ps1'
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$scratchBase = Join-Path $SkillPath '.tmp'
$scratch = Join-Path $scratchBase ('drawio-artifact-binding-' + [guid]::NewGuid().ToString('N'))
$results = [System.Collections.Generic.List[object]]::new()

function Write-Utf8File {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path,$Content,[System.Text.UTF8Encoding]::new($false))
}

function Invoke-ChildScript {
    param([string]$Path,[string[]]$Arguments)
    $previousPreference=$ErrorActionPreference
    $ErrorActionPreference='Continue'
    try{$output=@(& $engine -NoProfile -File $Path @Arguments 2>&1);$exitCode=$LASTEXITCODE}
    finally{$ErrorActionPreference=$previousPreference}
    [pscustomobject]@{ExitCode=$exitCode;Output=($output-join"`n")}
}

function Add-Result {
    param([string]$Name,[bool]$Passed,[string]$Detail)
    $results.Add([pscustomobject]@{Name=$Name;Passed=$Passed;Detail=$Detail})
}

function Write-Manifest {
    param([string]$Path,[string]$Canonical,[string]$Wrapper,[string]$Svg,[string]$Png)
    $artifacts=@(
        [ordered]@{role='canonical';path=[System.IO.Path]::GetFileName($Canonical);sha256=(Get-FileHash -LiteralPath $Canonical -Algorithm SHA256).Hash},
        [ordered]@{role='wrapper';path=[System.IO.Path]::GetFileName($Wrapper);sha256=(Get-FileHash -LiteralPath $Wrapper -Algorithm SHA256).Hash},
        [ordered]@{role='svg';path=[System.IO.Path]::GetFileName($Svg);sha256=(Get-FileHash -LiteralPath $Svg -Algorithm SHA256).Hash},
        [ordered]@{role='png';path=[System.IO.Path]::GetFileName($Png);sha256=(Get-FileHash -LiteralPath $Png -Algorithm SHA256).Hash}
    )
    [xml]$model=Get-Content -LiteralPath $Canonical -Raw -Encoding UTF8
    $manifest=[ordered]@{schemaVersion=1;page=[ordered]@{id='artifact-page';width=[double]$model.mxGraphModel.pageWidth;height=[double]$model.mxGraphModel.pageHeight};renderer=[ordered]@{name='draw.io';version='test'};artifacts=$artifacts}
    Write-Utf8File $Path (($manifest|ConvertTo-Json -Depth 6)+"`n")
}

if(-not(Test-Path -LiteralPath $scratchBase)){New-Item -ItemType Directory -Path $scratchBase|Out-Null}
New-Item -ItemType Directory -Path $scratch|Out-Null
try{
    $canonical=Join-Path $scratch 'canonical.xml'
    $otherCanonical=Join-Path $scratch 'other.xml'
    Copy-Item -LiteralPath (Join-Path $fixtures 'valid-process.xml') -Destination $canonical
    Copy-Item -LiteralPath (Join-Path $fixtures 'invalid-visual-process.xml') -Destination $otherCanonical
    $wrapper=Join-Path $scratch 'diagram.drawio'
    $otherWrapper=Join-Path $scratch 'other.drawio'
    $syncResult=Invoke-ChildScript $sync @('-Direction','ToDrawio','-CanonicalPath',$canonical,'-DrawioPath',$wrapper,'-PageId','artifact-page','-PageName','Artifact Page')
    $otherSyncResult=Invoke-ChildScript $sync @('-Direction','ToDrawio','-CanonicalPath',$otherCanonical,'-DrawioPath',$otherWrapper,'-PageId','artifact-page','-PageName','Artifact Page')
    if($syncResult.ExitCode-ne0-or$otherSyncResult.ExitCode-ne0){throw 'Wrapper fixture setup failed'}
    $svg=Join-Path $scratch 'diagram.svg'
    $png=Join-Path $scratch 'diagram.png'
    Write-Utf8File $svg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 827 1169"></svg>'
    Write-Utf8File $png 'png-fixture'
    $manifest=Join-Path $scratch 'artifacts.json'
    Write-Manifest $manifest $canonical $wrapper $svg $png
    $valid=Invoke-ChildScript $audit @('-ManifestPath',$manifest,'-SourcePath',$canonical,'-SvgPath',$svg)
    Add-Result 'current-bundle-accepted' ($valid.ExitCode-eq0) $valid.Output

    $typedManifest=Join-Path $scratch 'typed-artifacts.json'
    $typed=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json
    $typed.schemaVersion='1'
    $typed.page.width='827'
    $typed.page.height='1169'
    $typed.renderer.name=31
    $typed.renderer.version=1
    Write-Utf8File $typedManifest (($typed|ConvertTo-Json -Depth 6)+"`n")
    $typedResult=Invoke-ChildScript $audit @('-ManifestPath',$typedManifest,'-SourcePath',$canonical,'-SvgPath',$svg)
    $typedData=$typedResult.Output|ConvertFrom-Json
    Add-Result 'schema-invalid-types-rejected' ($typedResult.ExitCode-eq1-and'unsupported-artifact-schema'-in@($typedData.Issues.Type)-and'artifact-page-contract'-in@($typedData.Issues.Type)-and'missing-renderer-provenance'-in@($typedData.Issues.Type)) $typedResult.Output

    $unrelatedManifest=Join-Path $scratch 'unrelated-artifacts.json'
    Write-Manifest $unrelatedManifest $otherCanonical $otherWrapper $svg $png
    $unrelated=Invoke-ChildScript $audit @('-ManifestPath',$unrelatedManifest,'-SourcePath',$canonical,'-SvgPath',$svg)
    $unrelatedData=$unrelated.Output|ConvertFrom-Json
    Add-Result 'unrelated-bundle-rejected' ($unrelated.ExitCode-eq1-and'artifact-path-mismatch'-in@($unrelatedData.Issues.Type)) $unrelated.Output

    Copy-Item -LiteralPath $otherWrapper -Destination $wrapper -Force
    Write-Manifest $manifest $canonical $wrapper $svg $png
    $drift=Invoke-ChildScript $audit @('-ManifestPath',$manifest,'-SourcePath',$canonical,'-SvgPath',$svg)
    $driftData=$drift.Output|ConvertFrom-Json
    Add-Result 'wrapper-drift-rejected' ($drift.ExitCode-eq1-and'artifact-wrapper-parity'-in@($driftData.Issues.Type)) $drift.Output

    $failed=@($results|Where-Object{-not$_.Passed})
    [pscustomobject]@{Engine=$engine;Version=$PSVersionTable.PSVersion.ToString();TestCount=$results.Count;FailedCount=$failed.Count;Tests=@($results)}|ConvertTo-Json -Depth 6
    if($failed.Count-gt0){exit 1}
}
finally{
    $resolvedScratch=[System.IO.Path]::GetFullPath($scratch)
    $resolvedBase=[System.IO.Path]::GetFullPath($scratchBase)
    if($resolvedScratch.StartsWith($resolvedBase,[System.StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $resolvedScratch)){[System.IO.Directory]::Delete($resolvedScratch,$true)}
}
