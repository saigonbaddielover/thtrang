param(
    [Parameter(Mandatory = $true)][string]$SkillPath,
    [Parameter(Mandatory = $true)][string]$DrawioExecutable,
    [string]$ScratchDirectory
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$skill = (Resolve-Path -LiteralPath $SkillPath).Path
$scripts = Join-Path $skill 'scripts'
$fixtureRoot = Join-Path $scripts 'fixtures\approval'
$scratchBase = if ($ScratchDirectory) { $ScratchDirectory } else { Join-Path $skill '.tmp' }
if (-not (Test-Path -LiteralPath $scratchBase)) { New-Item -ItemType Directory -Path $scratchBase -Force | Out-Null }
$scratch = Join-Path (Resolve-Path -LiteralPath $scratchBase).Path ('approval-workflow-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$failures = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8File {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path,$Content + "`n",$utf8)
}

function Invoke-ChildScript {
    param([string]$Path,[object[]]$Arguments)
    $output = @(& $engine -NoProfile -File $Path @Arguments 2>&1)
    [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=($output -join "`n")}
}

function Convert-ResultJson {
    param([object]$Result)
    try { $Result.Output | ConvertFrom-Json }
    catch { throw "Invalid JSON from child process: $($Result.Output)" }
}

function Add-Result {
    param([string]$Name,[bool]$Passed,[string]$Detail)
    $results.Add([pscustomobject]@{Name=$Name;Passed=$Passed;Detail=$Detail})
    if (-not $Passed) { $failures.Add($Name) }
}

function Get-ValidationArguments {
    param(
        [string]$SemanticPath,
        [string]$NotationPath,
        [string]$ArtifactPath,
        [string]$WarningPath,
        [string]$QualityPath,
        [string]$ReportPath,
        [string]$VisualPath,
        [string]$CropPath
    )
    $arguments = @(
        '-SourcePath',$canonical,
        '-SvgPath',$svg,
        '-Family','process',
        '-SemanticManifestPath',$SemanticPath,
        '-NotationProfilePath',$NotationPath,
        '-ArtifactManifestPath',$ArtifactPath,
        '-RequiredArtifactRoles','canonical,wrapper,svg,png',
        '-WarningDispositionPath',$WarningPath,
        '-QualityProfilePath',$QualityPath,
        '-ValidationMode','Approval',
        '-ReportDirectory',$ReportPath
    )
    if ($VisualPath) { $arguments += @('-VisualInspectionPath',$VisualPath) }
    if ($CropPath) { $arguments += @('-CropReportPath',$CropPath) }
    $arguments
}

function Invoke-NegativeValidation {
    param([string]$Name,[object[]]$Arguments,[string]$GateName)
    $result = Invoke-ChildScript $validator $Arguments
    $data = Convert-ResultJson $result
    $gate = $data.Gates | Where-Object Name -eq $GateName
    $passed = $result.ExitCode -eq 1 -and $data.Decision -eq 'NOT APPROVED' -and $gate.Status -ne 'PASS'
    Add-Result $Name $passed ($data | ConvertTo-Json -Compress -Depth 12)
}

try {
    $canonical = Join-Path $scratch 'approved-process.xml'
    $semantic = Join-Path $scratch 'approved-process.manifest.json'
    $notation = Join-Path $skill 'profiles\process.json'
    $quality = Join-Path $skill 'assets\quality-profile.json'
    $wrapper = Join-Path $scratch 'approved-process.drawio'
    $svg = Join-Path $scratch 'approved-process.svg'
    $png = Join-Path $scratch 'approved-process.png'
    $artifact = Join-Path $scratch 'artifact-manifest.json'
    $warning = Join-Path $scratch 'warning-dispositions.json'
    $previsualDirectory = Join-Path $scratch 'previsual'
    $finalDirectory = Join-Path $scratch 'final'
    $cropDirectory = Join-Path $scratch 'crops'
    $cropReport = Join-Path $scratch 'crop-report.json'
    $visual = Join-Path $scratch 'visual-inspection.json'
    $sync = Join-Path $scripts 'sync_drawio.ps1'
    $exporter = Join-Path $scripts 'export_drawio.ps1'
    $validator = Join-Path $scripts 'validate_drawio.ps1'
    $cropExporter = Join-Path $scripts 'export_drawio_crops.ps1'

    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'approved-process.xml') -Destination $canonical
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'approved-process.manifest.json') -Destination $semantic

    $syncResult = Invoke-ChildScript $sync @('-Direction','ToDrawio','-CanonicalPath',$canonical,'-DrawioPath',$wrapper,'-PageId','approved-process','-PageName','Approved Process')
    Add-Result 'approval-wrapper-sync' ($syncResult.ExitCode -eq 0) $syncResult.Output

    $exportResult = Invoke-ChildScript $exporter @('-CanonicalPath',$canonical,'-DrawioPath',$wrapper,'-PageId','approved-process','-DrawioExecutable',$DrawioExecutable,'-SvgPath',$svg,'-PngPath',$png,'-ManifestPath',$artifact,'-QualityProfilePath',$quality)
    Add-Result 'approval-artifact-export' ($exportResult.ExitCode -eq 0 -and (Test-Path -LiteralPath $svg) -and (Test-Path -LiteralPath $png) -and (Test-Path -LiteralPath $artifact)) $exportResult.Output

    $warningData = [ordered]@{schemaVersion=1;dispositions=@([ordered]@{gate='rendered-labels';type='unknown-stencil-safe-area';element='review-note';decision='accepted';reason='Full-page and crop inspection confirm the annotation label is legible and contained.'})}
    Write-Utf8File $warning ($warningData | ConvertTo-Json -Depth 8)

    $previsualArguments = Get-ValidationArguments $semantic $notation $artifact $warning $quality $previsualDirectory '' ''
    $previsualResult = Invoke-ChildScript $validator $previsualArguments
    $previsualData = Convert-ResultJson $previsualResult
    $blockingNames = @($previsualData.Gates | Where-Object {$_.Blocking -and -not $_.Passed} | ForEach-Object Name)
    $warningGate = $previsualData.Gates | Where-Object Name -eq 'warning-dispositions'
    $previsualPassed = $previsualResult.ExitCode -eq 1 -and $previsualData.Decision -eq 'NOT APPROVED' -and $blockingNames.Count -eq 1 -and $blockingNames[0] -eq 'visual-inspection-input' -and $warningGate.Status -eq 'PASS'
    Add-Result 'approval-previsual-contract' $previsualPassed ($previsualData | ConvertTo-Json -Compress -Depth 12)

    $validationReport = Join-Path $previsualDirectory 'validation-summary.json'
    $cropResult = Invoke-ChildScript $cropExporter @('-PngPath',$png,'-SvgPath',$svg,'-ValidationReportPath',$validationReport,'-OutputDirectory',$cropDirectory,'-ReportPath',$cropReport)
    $cropData = Get-Content -LiteralPath $cropReport -Raw -Encoding UTF8 | ConvertFrom-Json
    $exportedCrops = @($cropData.Crops | Where-Object Status -eq 'EXPORTED')
    Add-Result 'approval-crop-export' ($cropResult.ExitCode -eq 0 -and $cropData.IssueCount -eq 1 -and $exportedCrops.Count -eq 1 -and $cropData.SkippedCount -eq 0) $cropResult.Output

    $reviewedCrops = @($exportedCrops | ForEach-Object {
        $path = [string]$_.Path
        if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path (Split-Path -Parent $cropReport) $path }
        [ordered]@{id=[System.IO.Path]::GetFileNameWithoutExtension($path);sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    $visualData = [ordered]@{
        schemaVersion=1
        assetSha256=(Get-FileHash -LiteralPath $svg -Algorithm SHA256).Hash.ToLowerInvariant()
        cropReportSha256=(Get-FileHash -LiteralPath $cropReport -Algorithm SHA256).Hash.ToLowerInvariant()
        reviewedAt='2026-08-11T00:00:00Z'
        reviewer='approval-workflow-regression'
        fullPage='PASS'
        cropsReviewed=$reviewedCrops.Count
        reviewedCrops=$reviewedCrops
        notes='The full page and every exported warning crop were reviewed against the exact SVG and PNG artifact bundle.'
    }
    Write-Utf8File $visual ($visualData | ConvertTo-Json -Depth 10)

    $finalArguments = Get-ValidationArguments $semantic $notation $artifact $warning $quality $finalDirectory $visual $cropReport
    $finalResult = Invoke-ChildScript $validator $finalArguments
    $finalData = Convert-ResultJson $finalResult
    $nonPassGates = @($finalData.Gates | Where-Object Status -ne 'PASS')
    $approved = $finalResult.ExitCode -eq 0 -and $finalData.OverallStatus -eq 'PASS' -and $finalData.Decision -eq 'APPROVED' -and $nonPassGates.Count -eq 0
    Add-Result 'approval-composed-golden-path' $approved ($finalData | ConvertTo-Json -Compress -Depth 12)

    $semanticBroken = Join-Path $scratch 'semantic-broken.json'
    $semanticData = Get-Content -LiteralPath $semantic -Raw -Encoding UTF8 | ConvertFrom-Json
    $semanticData.edges[0].target = 'task-a'
    Write-Utf8File $semanticBroken ($semanticData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-semantic-corruption' (Get-ValidationArguments $semanticBroken $notation $artifact $warning $quality (Join-Path $scratch 'negative-semantic') $visual $cropReport) 'semantic-notation-contract'

    $semanticTypeBroken = Join-Path $scratch 'semantic-type-broken.json'
    $semanticTypeData = Get-Content -LiteralPath $semantic -Raw -Encoding UTF8 | ConvertFrom-Json
    $semanticTypeData.schemaVersion = '1'
    Write-Utf8File $semanticTypeBroken ($semanticTypeData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-semantic-schema-type' (Get-ValidationArguments $semanticTypeBroken $notation $artifact $warning $quality (Join-Path $scratch 'negative-semantic-type') $visual $cropReport) 'semantic-notation-contract'

    $semanticArrayBroken = Join-Path $scratch 'semantic-array-broken.json'
    $semanticArrayData = Get-Content -LiteralPath $semantic -Raw -Encoding UTF8 | ConvertFrom-Json
    $semanticArrayData.nodes = $semanticArrayData.nodes[0]
    Write-Utf8File $semanticArrayBroken ($semanticArrayData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-semantic-array-type' (Get-ValidationArguments $semanticArrayBroken $notation $artifact $warning $quality (Join-Path $scratch 'negative-semantic-array') $visual $cropReport) 'semantic-notation-contract'

    $notationBroken = Join-Path $scratch 'notation-broken.json'
    $notationData = Get-Content -LiteralPath $notation -Raw -Encoding UTF8 | ConvertFrom-Json
    $notationData.edgeTypes.flow.style.endArrow = 'classic'
    Write-Utf8File $notationBroken ($notationData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-notation-corruption' (Get-ValidationArguments $semantic $notationBroken $artifact $warning $quality (Join-Path $scratch 'negative-notation') $visual $cropReport) 'semantic-notation-contract'

    $notationTypeBroken = Join-Path $scratch 'notation-type-broken.json'
    $notationTypeData = Get-Content -LiteralPath $notation -Raw -Encoding UTF8 | ConvertFrom-Json
    $notationTypeData.schemaVersion = '1'
    Write-Utf8File $notationTypeBroken ($notationTypeData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-notation-schema-type' (Get-ValidationArguments $semantic $notationTypeBroken $artifact $warning $quality (Join-Path $scratch 'negative-notation-type') $visual $cropReport) 'semantic-notation-contract'

    $artifactBroken = Join-Path $scratch 'artifact-broken.json'
    $artifactData = Get-Content -LiteralPath $artifact -Raw -Encoding UTF8 | ConvertFrom-Json
    ($artifactData.artifacts | Where-Object role -eq 'svg').sha256 = '0' * 64
    Write-Utf8File $artifactBroken ($artifactData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-artifact-corruption' (Get-ValidationArguments $semantic $notation $artifactBroken $warning $quality (Join-Path $scratch 'negative-artifact') $visual $cropReport) 'artifact-manifest'

    $warningBroken = Join-Path $scratch 'warning-broken.json'
    $warningBrokenData = Get-Content -LiteralPath $warning -Raw -Encoding UTF8 | ConvertFrom-Json
    $warningBrokenData.dispositions[0].element = 'wrong-element'
    Write-Utf8File $warningBroken ($warningBrokenData | ConvertTo-Json -Depth 8)
    Invoke-NegativeValidation 'approval-rejects-warning-corruption' (Get-ValidationArguments $semantic $notation $artifact $warningBroken $quality (Join-Path $scratch 'negative-warning') $visual $cropReport) 'warning-dispositions'

    $warningFixed = Join-Path $scratch 'warning-fixed.json'
    $warningFixedData = Get-Content -LiteralPath $warning -Raw -Encoding UTF8 | ConvertFrom-Json
    $warningFixedData.dispositions[0].decision = 'fixed'
    Write-Utf8File $warningFixed ($warningFixedData | ConvertTo-Json -Depth 8)
    Invoke-NegativeValidation 'approval-rejects-fixed-active-warning' (Get-ValidationArguments $semantic $notation $artifact $warningFixed $quality (Join-Path $scratch 'negative-warning-fixed') $visual $cropReport) 'warning-dispositions'

    $warningExtra = Join-Path $scratch 'warning-extra.json'
    $warningExtraData = Get-Content -LiteralPath $warning -Raw -Encoding UTF8 | ConvertFrom-Json
    $warningExtraData.dispositions = @($warningExtraData.dispositions) + [pscustomobject]@{gate='rendered-labels';type='unknown-stencil-safe-area';element='ghost';decision='accepted';reason='This entry must be rejected because no current warning matches it.'}
    Write-Utf8File $warningExtra ($warningExtraData | ConvertTo-Json -Depth 8)
    Invoke-NegativeValidation 'approval-rejects-extra-warning-disposition' (Get-ValidationArguments $semantic $notation $artifact $warningExtra $quality (Join-Path $scratch 'negative-warning-extra') $visual $cropReport) 'warning-dispositions'

    $cropBroken = Join-Path $scratch 'crop-broken.json'
    $cropBrokenData = Get-Content -LiteralPath $cropReport -Raw -Encoding UTF8 | ConvertFrom-Json
    $cropBrokenData.ValidationReportSha256 = '0' * 64
    Write-Utf8File $cropBroken ($cropBrokenData | ConvertTo-Json -Depth 12)
    $visualForBrokenCrop = Join-Path $scratch 'visual-for-broken-crop.json'
    $visualForBrokenCropData = Get-Content -LiteralPath $visual -Raw -Encoding UTF8 | ConvertFrom-Json
    $visualForBrokenCropData.cropReportSha256 = (Get-FileHash -LiteralPath $cropBroken -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8File $visualForBrokenCrop ($visualForBrokenCropData | ConvertTo-Json -Depth 10)
    Invoke-NegativeValidation 'approval-rejects-crop-corruption' (Get-ValidationArguments $semantic $notation $artifact $warning $quality (Join-Path $scratch 'negative-crop') $visualForBrokenCrop $cropBroken) 'visual-inspection'

    $fakeCrop = Join-Path $scratch 'fake-warning-crop.png'
    Copy-Item -LiteralPath $png -Destination $fakeCrop
    $pixelCropReport = Join-Path $scratch 'pixel-crop-report.json'
    $pixelCropData = Get-Content -LiteralPath $cropReport -Raw -Encoding UTF8 | ConvertFrom-Json
    $pixelCropData.Crops[0].Path = $fakeCrop
    Write-Utf8File $pixelCropReport ($pixelCropData | ConvertTo-Json -Depth 12)
    $pixelVisual = Join-Path $scratch 'pixel-visual.json'
    $pixelVisualData = Get-Content -LiteralPath $visual -Raw -Encoding UTF8 | ConvertFrom-Json
    $pixelVisualData.cropReportSha256 = (Get-FileHash -LiteralPath $pixelCropReport -Algorithm SHA256).Hash.ToLowerInvariant()
    $pixelVisualData.reviewedCrops[0].id = [System.IO.Path]::GetFileNameWithoutExtension($fakeCrop)
    $pixelVisualData.reviewedCrops[0].sha256 = (Get-FileHash -LiteralPath $fakeCrop -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8File $pixelVisual ($pixelVisualData | ConvertTo-Json -Depth 10)
    Invoke-NegativeValidation 'approval-rejects-crop-pixel-substitution' (Get-ValidationArguments $semantic $notation $artifact $warning $quality (Join-Path $scratch 'negative-crop-pixels') $pixelVisual $pixelCropReport) 'visual-inspection'

    $summaryReport = Join-Path $scratch 'summary-report.json'
    $summaryData = Get-Content -LiteralPath $validationReport -Raw -Encoding UTF8 | ConvertFrom-Json
    $summaryData.Decision = 'APPROVED'
    Write-Utf8File $summaryReport ($summaryData | ConvertTo-Json -Depth 20)
    $summaryCropReport = Join-Path $scratch 'summary-crop-report.json'
    $summaryCropData = Get-Content -LiteralPath $cropReport -Raw -Encoding UTF8 | ConvertFrom-Json
    $summaryCropData.Report = $summaryReport
    $summaryCropData.ValidationReportSha256 = (Get-FileHash -LiteralPath $summaryReport -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8File $summaryCropReport ($summaryCropData | ConvertTo-Json -Depth 12)
    $summaryVisual = Join-Path $scratch 'summary-visual.json'
    $summaryVisualData = Get-Content -LiteralPath $visual -Raw -Encoding UTF8 | ConvertFrom-Json
    $summaryVisualData.cropReportSha256 = (Get-FileHash -LiteralPath $summaryCropReport -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8File $summaryVisual ($summaryVisualData | ConvertTo-Json -Depth 10)
    Invoke-NegativeValidation 'approval-rejects-validation-summary-tamper' (Get-ValidationArguments $semantic $notation $artifact $warning $quality (Join-Path $scratch 'negative-summary') $summaryVisual $summaryCropReport) 'visual-inspection'

    $visualBroken = Join-Path $scratch 'visual-broken.json'
    $visualBrokenData = Get-Content -LiteralPath $visual -Raw -Encoding UTF8 | ConvertFrom-Json
    $visualBrokenData.assetSha256 = '0' * 64
    Write-Utf8File $visualBroken ($visualBrokenData | ConvertTo-Json -Depth 10)
    Invoke-NegativeValidation 'approval-rejects-visual-corruption' (Get-ValidationArguments $semantic $notation $artifact $warning $quality (Join-Path $scratch 'negative-visual') $visualBroken $cropReport) 'visual-inspection'

    $qualityBroken = Join-Path $scratch 'quality-broken.json'
    $qualityData = Get-Content -LiteralPath $quality -Raw -Encoding UTF8 | ConvertFrom-Json
    $qualityData.clearance.pageConnector = [double]$qualityData.clearance.pageConnector + 1
    Write-Utf8File $qualityBroken ($qualityData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-quality-contract-drift' (Get-ValidationArguments $semantic $notation $artifact $warning $qualityBroken (Join-Path $scratch 'negative-quality') $visual $cropReport) 'visual-inspection'

    $qualityTypeBroken = Join-Path $scratch 'quality-type-broken.json'
    $qualityTypeData = Get-Content -LiteralPath $quality -Raw -Encoding UTF8 | ConvertFrom-Json
    $qualityTypeData.schemaVersion = '2'
    Write-Utf8File $qualityTypeBroken ($qualityTypeData | ConvertTo-Json -Depth 12)
    Invoke-NegativeValidation 'approval-rejects-quality-schema-type' (Get-ValidationArguments $semantic $notation $artifact $warning $qualityTypeBroken (Join-Path $scratch 'negative-quality-type') $visual $cropReport) 'quality-profile'

    [pscustomobject]@{SchemaVersion=1;TestCount=$results.Count;FailureCount=$failures.Count;Failures=@($failures);Tests=@($results)} | ConvertTo-Json -Depth 14
    if ($failures.Count -gt 0) { exit 1 }
}
finally {
    if (Test-Path -LiteralPath $scratch -PathType Container) { [System.IO.Directory]::Delete($scratch,$true) }
}
