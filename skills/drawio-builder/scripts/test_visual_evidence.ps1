param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$SvgPath,
    [Parameter(Mandatory = $true)][string]$PngPath,
    [Parameter(Mandatory = $true)][string]$ScratchDirectory
)

$ErrorActionPreference = 'Stop'
$SourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$SvgPath = (Resolve-Path -LiteralPath $SvgPath).Path
$PngPath = (Resolve-Path -LiteralPath $PngPath).Path
$ScratchDirectory = (Resolve-Path -LiteralPath $ScratchDirectory).Path
$engine = (Get-Process -Id $PID).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-Validator {
    param([string[]]$Arguments)
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine -NoProfile -File (Join-Path $PSScriptRoot 'validate_drawio.ps1') @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prior }
    [pscustomobject]@{ ExitCode=$exitCode; Output=($output -join "`n") }
}

function Write-Utf8File {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-EvidenceBundle {
    param([string]$ValidationReportContent,[object]$CropReport,[object]$VisualEvidence)
    Write-Utf8File $validationReportPath $ValidationReportContent
    $CropReport.ValidationReportSha256=(Get-FileHash -LiteralPath $validationReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8File $cropReportPath ($CropReport|ConvertTo-Json -Depth 12)
    $VisualEvidence.cropReportSha256=(Get-FileHash -LiteralPath $cropReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8File $visualEvidencePath ($VisualEvidence|ConvertTo-Json -Depth 12)
}

$approval = Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-ValidationMode','Approval')
$approvalData = $approval.Output | ConvertFrom-Json
$missingGate = $approvalData.Gates | Where-Object Name -eq 'visual-inspection-input'
if ($approval.ExitCode -ne 1 -or $missingGate.Status -ne 'UNKNOWN' -or -not $missingGate.Blocking -or $approvalData.Decision -ne 'NOT APPROVED') { $failures.Add('missing-visual-evidence') }

$roleContract=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-ValidationMode','Approval','-RequiredArtifactRoles','canonical,wrapper,svg,png,pdf')
$roleContractData=$roleContract.Output|ConvertFrom-Json
$expectedRoles=@('canonical','pdf','png','svg','wrapper')
if(@(Compare-Object $expectedRoles @($roleContractData.RequiredArtifactRoles|Sort-Object)).Count-ne0){$failures.Add('required-artifact-role-cli-contract')}

$validationReportPath = Join-Path $ScratchDirectory 'visual-validation-summary.json'
$baseline = Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process')
Write-Utf8File $validationReportPath $baseline.Output
$cropReportPath = Join-Path $ScratchDirectory 'crop-report.json'
Write-Utf8File $cropReportPath ([ordered]@{ SchemaVersion=1; Png=$PngPath; Svg=$SvgPath; Report=$validationReportPath; ValidationReportSha256=(Get-FileHash -LiteralPath $validationReportPath -Algorithm SHA256).Hash.ToLowerInvariant(); IssueCount=0; ExportedCount=0; SkippedCount=0; Crops=@() } | ConvertTo-Json)
$visualEvidencePath = Join-Path $ScratchDirectory 'visual-inspection.json'
$visualEvidence = [ordered]@{ schemaVersion=1; assetSha256=('0' * 64); cropReportSha256=(Get-FileHash -LiteralPath $cropReportPath -Algorithm SHA256).Hash.ToLowerInvariant(); reviewedAt='2026-08-11T00:00:00Z'; reviewer='test-suite'; fullPage='PASS'; cropsReviewed=0; reviewedCrops=@(); notes='Hash-binding regression evidence.' }
Write-Utf8File $visualEvidencePath ($visualEvidence | ConvertTo-Json)
$stale = Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$staleData = $stale.Output | ConvertFrom-Json
$staleGate = $staleData.Gates | Where-Object Name -eq 'visual-inspection'
if ($stale.ExitCode -ne 1 -or 'visual-inspection-stale-asset' -notin @($staleGate.Result.Issues.Type)) { $failures.Add('stale-visual-evidence') }

$visualEvidence.assetSha256 = (Get-FileHash -LiteralPath $SvgPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Utf8File $visualEvidencePath ($visualEvidence | ConvertTo-Json)
$matching = Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$matchingData = $matching.Output | ConvertFrom-Json
$matchingGate = $matchingData.Gates | Where-Object Name -eq 'visual-inspection'
if ($matching.ExitCode -ne 0 -or $matchingGate.Status -ne 'PASS') { $failures.Add('matching-visual-evidence') }

$visualEvidence.reviewedAt='2026-08-11'
Write-Utf8File $visualEvidencePath ($visualEvidence|ConvertTo-Json -Depth 6)
$dateOnly=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$dateOnlyData=$dateOnly.Output|ConvertFrom-Json
$dateOnlyGate=$dateOnlyData.Gates|Where-Object Name -eq 'visual-inspection'
if($dateOnly.ExitCode-ne1-or'visual-inspection-reviewed-at'-notin@($dateOnlyGate.Result.Issues.Type)){$failures.Add('rfc3339-date-time-required')}
$visualEvidence.reviewedAt='2026-08-11T00:00:00Z'
Write-Utf8File $visualEvidencePath ($visualEvidence|ConvertTo-Json -Depth 6)

$duplicateReviewedAt=($visualEvidence|ConvertTo-Json -Depth 6)-replace '"reviewedAt"\s*:\s*"[^"]+"','"reviewedAt":"2026-08-11T00:00:00Z","reviewedAt":123'
Write-Utf8File $visualEvidencePath $duplicateReviewedAt
$duplicateReviewedAtResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$duplicateReviewedAtData=$duplicateReviewedAtResult.Output|ConvertFrom-Json
$duplicateReviewedAtGate=$duplicateReviewedAtData.Gates|Where-Object Name -eq 'visual-inspection'
if($duplicateReviewedAtResult.ExitCode-ne1-or'visual-inspection-reviewed-at'-notin@($duplicateReviewedAtGate.Result.Issues.Type)){$failures.Add('duplicate-reviewed-at-rejected')}
Write-Utf8File $visualEvidencePath ($visualEvidence|ConvertTo-Json -Depth 6)

$baselineContent=$baseline.Output
$validCropReport=Get-Content -LiteralPath $cropReportPath -Raw -Encoding UTF8|ConvertFrom-Json
$validVisualEvidence=Get-Content -LiteralPath $visualEvidencePath -Raw -Encoding UTF8|ConvertFrom-Json

$crossContract=$baselineContent|ConvertFrom-Json
$crossContract.Family='generic'
Write-EvidenceBundle ($crossContract|ConvertTo-Json -Depth 12) $validCropReport $validVisualEvidence
$crossContractResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$crossContractGate=(($crossContractResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($crossContractResult.ExitCode-ne1-or'visual-inspection-validation-contract'-notin@($crossContractGate.Result.Issues.Type)){$failures.Add('cross-contract-family-binding')}

$gateState=$baselineContent|ConvertFrom-Json
$gateState.Gates[0].Status='FAIL'
$gateState.Gates[0].Blocking=$false
Write-EvidenceBundle ($gateState|ConvertTo-Json -Depth 12) $validCropReport $validVisualEvidence
$gateStateResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$gateStateGate=(($gateStateResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($gateStateResult.ExitCode-ne1-or'visual-inspection-gate-contract'-notin@($gateStateGate.Result.Issues.Type)){$failures.Add('cross-contract-gate-state')}

$mappingCrop=($validCropReport|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$mappingCrop.IssueCount=1;$mappingCrop.ExportedCount=1;$mappingCrop.Crops=@([pscustomobject]@{Gate='connector-geometry';Element='missing';Type='fabricated';Status='EXPORTED';Path=$PngPath;PixelBounds=[pscustomobject]@{X=0;Y=0;Width=1;Height=1}})
$mappingVisual=($validVisualEvidence|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$mappingVisual.cropsReviewed=1;$mappingVisual.reviewedCrops=@([pscustomobject]@{id=[System.IO.Path]::GetFileNameWithoutExtension($PngPath);sha256=(Get-FileHash -LiteralPath $PngPath -Algorithm SHA256).Hash.ToLowerInvariant()})
Write-EvidenceBundle $baselineContent $mappingCrop $mappingVisual
$mappingResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$mappingGate=(($mappingResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($mappingResult.ExitCode-ne1-or'visual-inspection-crop-issue-mapping'-notin@($mappingGate.Result.Issues.Type)){$failures.Add('crop-issue-multiplicity')}

$typedVisual=($validVisualEvidence|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$typedVisual.schemaVersion='1';$typedVisual.cropsReviewed='0'
Write-EvidenceBundle $baselineContent $validCropReport $typedVisual
$typedVisualResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$typedVisualGate=(($typedVisualResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($typedVisualResult.ExitCode-ne1-or'visual-inspection-schema'-notin@($typedVisualGate.Result.Issues.Type)-or'visual-inspection-crops'-notin@($typedVisualGate.Result.Issues.Type)){$failures.Add('visual-schema-types')}

$typedCrop=($validCropReport|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$typedCrop.IssueCount='0';$typedCrop.ExportedCount='0';$typedCrop.SkippedCount='0'
Write-EvidenceBundle $baselineContent $typedCrop $validVisualEvidence
$typedCropResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$typedCropGate=(($typedCropResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($typedCropResult.ExitCode-ne1-or'visual-inspection-crop-report-count'-notin@($typedCropGate.Result.Issues.Type)){$failures.Add('crop-count-types')}

$boundsCrop=($mappingCrop|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$boundsCrop.Crops[0].PixelBounds.X='0';$boundsCrop.Crops[0].PixelBounds.Width=0
Write-EvidenceBundle $baselineContent $boundsCrop $mappingVisual
$boundsResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$boundsGate=(($boundsResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($boundsResult.ExitCode-ne1-or'visual-inspection-crop-bounds'-notin@($boundsGate.Result.Issues.Type)){$failures.Add('crop-bounds-types')}

$conditionalCrop=($mappingCrop|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$conditionalCrop.Crops[0].PSObject.Properties.Remove('Path');$conditionalCrop.Crops[0].PSObject.Properties.Remove('PixelBounds')
Write-EvidenceBundle $baselineContent $conditionalCrop $mappingVisual
$conditionalResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$conditionalGate=(($conditionalResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($conditionalResult.ExitCode-ne1-or'visual-inspection-crop-path'-notin@($conditionalGate.Result.Issues.Type)-or'visual-inspection-crop-bounds'-notin@($conditionalGate.Result.Issues.Type)){$failures.Add('crop-exported-conditional-fields')}

$invalidStatusCrop=($mappingCrop|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$invalidStatusCrop.ExportedCount=0;$invalidStatusCrop.Crops[0].Status='BROKEN'
Write-EvidenceBundle $baselineContent $invalidStatusCrop $mappingVisual
$invalidStatusResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$invalidStatusGate=(($invalidStatusResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($invalidStatusResult.ExitCode-ne1-or'visual-inspection-crop-status'-notin@($invalidStatusGate.Result.Issues.Type)){$failures.Add('crop-invalid-status')}

$skippedCrop=($mappingCrop|ConvertTo-Json -Depth 12)|ConvertFrom-Json
$skippedCrop.ExportedCount=0;$skippedCrop.SkippedCount=1;$skippedCrop.Crops[0].Status='SKIPPED';$skippedCrop.Crops[0].PSObject.Properties.Remove('Reason')
Write-EvidenceBundle $baselineContent $skippedCrop $mappingVisual
$skippedResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$skippedGate=(($skippedResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($skippedResult.ExitCode-ne1-or'visual-inspection-crop-reason'-notin@($skippedGate.Result.Issues.Type)){$failures.Add('crop-skipped-reason')}

Write-EvidenceBundle $baselineContent $validCropReport $validVisualEvidence
$matchingAgain=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$matchingAgainGate=(($matchingAgain.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($matchingAgain.ExitCode-ne0-or$matchingAgainGate.Status-ne'PASS'){$failures.Add('matching-visual-evidence-after-negatives')}

Write-EvidenceBundle $baselineContent $validCropReport $validVisualEvidence
$crossModeResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-ValidationMode','Approval','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$crossModeGate=(($crossModeResult.Output|ConvertFrom-Json).Gates|Where-Object Name -eq 'visual-inspection')
if($crossModeResult.ExitCode-ne1-or'visual-inspection-validation-contract'-notin@($crossModeGate.Result.Issues.Type)){$failures.Add('approval-rejects-audit-report')}

$approvalBaseline=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-ValidationMode','Approval')
Write-EvidenceBundle $approvalBaseline.Output $validCropReport $validVisualEvidence
$approvalEvidenceResult=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-ValidationMode','Approval','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$approvalEvidenceData=$approvalEvidenceResult.Output|ConvertFrom-Json
$approvalEvidenceGate=$approvalEvidenceData.Gates|Where-Object Name -eq 'visual-inspection'
if($approvalEvidenceGate.Status-ne'PASS'){$failures.Add('approval-previsual-workflow')}

$artifactDirectory=Join-Path $ScratchDirectory 'artifact-binding'
New-Item -ItemType Directory -Path $artifactDirectory -Force|Out-Null
$artifactSource=Join-Path $artifactDirectory 'canonical.xml';$artifactSvg=Join-Path $artifactDirectory 'render.svg';$artifactPng=Join-Path $artifactDirectory 'render.png';$artifactWrapper=Join-Path $artifactDirectory 'wrapper.drawio';$artifactManifestPath=Join-Path $artifactDirectory 'manifest.json'
Copy-Item -LiteralPath $SourcePath -Destination $artifactSource -Force;Copy-Item -LiteralPath $SvgPath -Destination $artifactSvg -Force;Copy-Item -LiteralPath $PngPath -Destination $artifactPng -Force
$syncOutput=@(&$engine -NoProfile -File (Join-Path $PSScriptRoot 'sync_drawio.ps1') -Direction ToDrawio -CanonicalPath $artifactSource -DrawioPath $artifactWrapper -PageId artifact-page -PageName 'Artifact Page' 2>&1);$syncExit=$LASTEXITCODE
[xml]$artifactCanonical=Get-Content -LiteralPath $artifactSource -Raw -Encoding UTF8
$artifactEntries=@();foreach($entry in @([pscustomobject]@{role='canonical';path='canonical.xml'},[pscustomobject]@{role='wrapper';path='wrapper.drawio'},[pscustomobject]@{role='svg';path='render.svg'},[pscustomobject]@{role='png';path='render.png'})){$artifactEntries+=[ordered]@{role=$entry.role;path=$entry.path;sha256=(Get-FileHash -LiteralPath (Join-Path $artifactDirectory $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant()}}
$artifactManifest=[ordered]@{schemaVersion=1;page=[ordered]@{id='artifact-page';width=[double]$artifactCanonical.mxGraphModel.pageWidth;height=[double]$artifactCanonical.mxGraphModel.pageHeight};renderer=[ordered]@{name='draw.io';version='test'};artifacts=$artifactEntries}
Write-Utf8File $artifactManifestPath ($artifactManifest|ConvertTo-Json -Depth 8)
$artifactBaseline=Invoke-Validator @('-SourcePath',$artifactSource,'-SvgPath',$artifactSvg,'-Profile','process','-ArtifactManifestPath',$artifactManifestPath)
$artifactCrop=($validCropReport|ConvertTo-Json -Depth 12)|ConvertFrom-Json;$artifactCrop.Svg=$artifactSvg;$artifactCrop.Png=$PngPath
$artifactVisual=($validVisualEvidence|ConvertTo-Json -Depth 12)|ConvertFrom-Json;$artifactVisual.assetSha256=(Get-FileHash -LiteralPath $artifactSvg -Algorithm SHA256).Hash.ToLowerInvariant()
Write-EvidenceBundle $artifactBaseline.Output $artifactCrop $artifactVisual
$artifactMismatchResult=Invoke-Validator @('-SourcePath',$artifactSource,'-SvgPath',$artifactSvg,'-Profile','process','-ArtifactManifestPath',$artifactManifestPath,'-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$artifactMismatchData=$artifactMismatchResult.Output|ConvertFrom-Json;$artifactMismatchGate=$artifactMismatchData.Gates|Where-Object Name -eq 'visual-inspection';$artifactAuditGate=$artifactMismatchData.Gates|Where-Object Name -eq 'artifact-manifest'
if($syncExit-ne0-or$artifactAuditGate.Status-ne'PASS'-or$artifactMismatchResult.ExitCode-ne1-or'visual-inspection-artifact-binding'-notin@($artifactMismatchGate.Result.Issues.Type)){$failures.Add('artifact-png-binding')}

Write-EvidenceBundle $baselineContent $validCropReport $validVisualEvidence

$visualEvidence=Get-Content -LiteralPath $visualEvidencePath -Raw -Encoding UTF8|ConvertFrom-Json
$visualEvidence|Add-Member -NotePropertyName unexpected -NotePropertyValue 'value'
Write-Utf8File $visualEvidencePath ($visualEvidence | ConvertTo-Json)
$unknownVisual = Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$unknownVisualData=$unknownVisual.Output|ConvertFrom-Json
$unknownVisualGate=$unknownVisualData.Gates|Where-Object Name -eq 'visual-inspection'
if($unknownVisual.ExitCode-ne1-or'visual-inspection-property'-notin@($unknownVisualGate.Result.Issues.Type)){$failures.Add('unknown-visual-property')}
$visualEvidence.PSObject.Properties.Remove('unexpected')

$cropReport=Get-Content -LiteralPath $cropReportPath -Raw -Encoding UTF8|ConvertFrom-Json
$cropReport|Add-Member -NotePropertyName unexpected -NotePropertyValue 'value'
Write-Utf8File $cropReportPath ($cropReport|ConvertTo-Json)
$visualEvidence.cropReportSha256=(Get-FileHash -LiteralPath $cropReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Utf8File $visualEvidencePath ($visualEvidence|ConvertTo-Json)
$unknownCrop=Invoke-Validator @('-SourcePath',$SourcePath,'-SvgPath',$SvgPath,'-Profile','process','-VisualInspectionPath',$visualEvidencePath,'-CropReportPath',$cropReportPath)
$unknownCropData=$unknownCrop.Output|ConvertFrom-Json
$unknownCropGate=$unknownCropData.Gates|Where-Object Name -eq 'visual-inspection'
if($unknownCrop.ExitCode-ne1-or'visual-inspection-crop-report-property'-notin@($unknownCropGate.Result.Issues.Type)){$failures.Add('unknown-crop-report-property')}

[pscustomobject]@{ SchemaVersion=1; FailureCount=$failures.Count; Failures=@($failures) } | ConvertTo-Json -Depth 4
if ($failures.Count -gt 0) { exit 1 }
