param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$SvgPath,

    [Alias('Profile')]
    [ValidateSet('process', 'data-flow', 'bpmn', 'uml', 'erd', 'architecture', 'cloud', 'network', 'engineering', 'electrical', 'pid', 'floorplan', 'wireframe', 'generic')]
    [string]$Family = 'process',

    [string]$QualityProfilePath,
    [string]$NotationProfilePath,
    [string]$SemanticManifestPath,
    [string]$ArtifactManifestPath,
    [string]$RequiredArtifactRoles = 'canonical,wrapper,svg,png',
    [string]$VisualInspectionPath,
    [string]$CropReportPath,
    [string]$WarningDispositionPath,
    [string]$ReportDirectory,

    [ValidateSet('Audit', 'Approval')]
    [string]$ValidationMode = 'Audit'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Contract.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\Drawio.Evidence.psm1') -Force

if (-not $QualityProfilePath) { $QualityProfilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\quality-profile.json' }
if (-not (Test-Path -LiteralPath $QualityProfilePath -PathType Leaf)) { throw "Quality profile not found: $QualityProfilePath" }
$quality = $null
try { $quality = Get-Content -LiteralPath $QualityProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $quality = $null }
$requiredArtifactRoleList=@($RequiredArtifactRoles.Split(',')|ForEach-Object{$_.Trim()}|Where-Object{$_}|Sort-Object -Unique)
if($requiredArtifactRoleList.Count-eq0-or@($requiredArtifactRoleList|Where-Object{$_-notin@('canonical','wrapper','svg','png','word-png','pdf')}).Count-gt0){throw "RequiredArtifactRoles must be a comma-separated subset of canonical,wrapper,svg,png,word-png,pdf: $RequiredArtifactRoles"}
$inputDigests = Get-DrawioInputDigests -SourcePath $SourcePath -SvgPath $SvgPath -QualityProfilePath $QualityProfilePath -SemanticManifestPath $SemanticManifestPath -NotationProfilePath $NotationProfilePath -ArtifactManifestPath $ArtifactManifestPath -WarningDispositionPath $WarningDispositionPath

$gates = [System.Collections.Generic.List[object]]::new()
function Invoke-Gate {
    param([string]$Name,[scriptblock]$Command)
    $output = @()
    try { $output = @(& $Command) }
    catch { $output = @(([pscustomobject]@{ IssueCount=1; ErrorCount=1; WarningCount=0; Issues=@((New-DrawioIssue -Type 'gate-exception' -Element $Name -Detail $_.Exception.Message -RepairClass 'repair-validator')) } | ConvertTo-Json -Depth 8)) }
    $parsed = $null
    try { $parsed = ($output -join "`n") | ConvertFrom-Json }
    catch { $parsed = [pscustomobject]@{ IssueCount=1; ErrorCount=1; WarningCount=0; Issues=@((New-DrawioIssue -Type 'invalid-gate-output' -Element $Name -Detail ($output -join "`n") -RepairClass 'repair-validator')) } }
    $errorCount = if($parsed.PSObject.Properties['ErrorCount']){[int]$parsed.ErrorCount}else{@($parsed.Issues|Where-Object{$_.Severity-eq'ERROR'}).Count}
    $reportedStatus=if($parsed.PSObject.Properties['OverallStatus']-and[string]$parsed.OverallStatus-in@('PASS','UNKNOWN','FAIL')){[string]$parsed.OverallStatus}else{$null}
    $status=if($reportedStatus){$reportedStatus}elseif($errorCount-eq0){'PASS'}else{'FAIL'}
    $passed=$status-eq'PASS';$blocking=if($status-eq'UNKNOWN'){$ValidationMode-eq'Approval'}else{$true}
    $gates.Add([pscustomobject]@{ Name=$Name; Status=$status; Passed=$passed; Blocking=$blocking; ExitCode=$(if($passed-or-not$blocking){0}else{1}); Reason=''; ResidualRisk=''; Result=$parsed })
}

function Add-StateGate {
    param([string]$Name,[ValidateSet('SKIPPED','UNKNOWN')][string]$Status,[string]$Reason,[string]$ResidualRisk)
    $blocking=$ValidationMode-eq'Approval'
    $result=[pscustomobject]@{IssueCount=0;ErrorCount=0;WarningCount=0;Status=$Status;Reason=$Reason;ResidualRisk=$ResidualRisk;Issues=@()}
    $gates.Add([pscustomobject]@{Name=$Name;Status=$Status;Passed=$false;Blocking=$blocking;ExitCode=$(if($blocking){1}else{0});Reason=$Reason;ResidualRisk=$ResidualRisk;Result=$result})
}

function Add-PassGate {
    param([string]$Name,[object]$Result)
    $gates.Add([pscustomobject]@{Name=$Name;Status='PASS';Passed=$true;Blocking=$true;ExitCode=0;Reason='';ResidualRisk='';Result=$Result})
}

function Add-UnknownPropertyIssues {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [object]$Value,
        [string[]]$Allowed,
        [string]$Type,
        [string]$Element,
        [string]$RepairClass
    )
    if(-not$Value){return}
    foreach($property in @($Value.PSObject.Properties.Name|Where-Object{$_-notin$Allowed})){
        Add-DrawioIssue -Issues $Issues -Type $Type -Element $Element -Detail "Unknown property: $property" -Evidence $property -RepairClass $RepairClass
    }
}

Invoke-Gate 'quality-profile' { & (Join-Path $PSScriptRoot 'audit_drawio_quality_profile.ps1') -QualityProfilePath $QualityProfilePath }
Invoke-Gate 'canonical-preflight' { & (Join-Path $PSScriptRoot 'preflight_drawio.ps1') -SourcePath $SourcePath }
Invoke-Gate 'composition-word-fit' { & (Join-Path $PSScriptRoot 'audit_drawio_composition.ps1') -SourcePath $SourcePath -QualityProfilePath $QualityProfilePath }
if ($SemanticManifestPath) {
    Invoke-Gate 'semantic-notation-contract' { Invoke-DrawioContractAudit -SourcePath $SourcePath -Family $Family -SemanticManifestPath $SemanticManifestPath -NotationProfilePath $NotationProfilePath | ConvertTo-Json -Depth 10 }
    if($NotationProfilePath){
        $contractGate=$gates[$gates.Count-1]
        if($contractGate.Result.PSObject.Properties['UnresolvedManualRuleCount']-and[int]$contractGate.Result.UnresolvedManualRuleCount-gt0){Add-StateGate 'manual-notation-rules' 'UNKNOWN' 'Notation profile contains prose rules without valid semantic rule dispositions' 'Manual rules remain unverified'}
        else{Add-PassGate 'manual-notation-rules' ([pscustomobject]@{IssueCount=0;ErrorCount=0;WarningCount=0;ManualRuleCount=$(if($contractGate.Result.PSObject.Properties['ManualRuleCount']){[int]$contractGate.Result.ManualRuleCount}else{0});Issues=@()})}
    }
}
if(-not$SemanticManifestPath){Add-StateGate 'semantic-manifest-input' 'SKIPPED' 'SemanticManifestPath was not supplied' 'Business narrative, exact endpoints, labels, and ownership are unverified'}
if(-not$NotationProfilePath){Add-StateGate 'notation-profile-input' 'UNKNOWN' 'NotationProfilePath was not supplied' 'Notation correctness cannot be established from appearance alone'}
elseif(-not$SemanticManifestPath){Add-StateGate 'notation-contract' 'UNKNOWN' 'Notation profile cannot be applied without SemanticManifestPath' 'Used semantic types and scaffold roles are unknown'}
$connectorFamily = if ($Family -in @('process','data-flow')) { $Family } else { $Family }
Invoke-Gate 'connector-geometry' {
    & (Join-Path $PSScriptRoot 'audit_drawio_connectors.ps1') -SourcePath $SourcePath -SvgPath $SvgPath -MinimumStub ([double]$quality.clearance.endpointStub) -DividerClearance ([double]$quality.clearance.parallelDivider) -PageClearance ([double]$quality.clearance.pageConnector) -Profile $connectorFamily
}
Invoke-Gate 'route-efficiency' {
    & (Join-Path $PSScriptRoot 'audit_drawio_route_efficiency.ps1') -SourcePath $SourcePath -SvgPath $SvgPath -QualityProfilePath $QualityProfilePath
}
Invoke-Gate 'archive-labels' {
    & (Join-Path $PSScriptRoot 'audit_drawio_archive_labels.ps1') -SourcePath $SourcePath -SvgPath $SvgPath -MinimumClearance ([double]$quality.clearance.labelInk)
}
Invoke-Gate 'rendered-labels' {
    & (Join-Path $PSScriptRoot 'audit_drawio_labels.ps1') -SourcePath $SourcePath -SvgPath $SvgPath -QualityProfilePath $QualityProfilePath
}
if ($ArtifactManifestPath) {
    Invoke-Gate 'artifact-manifest' { & (Join-Path $PSScriptRoot 'audit_drawio_artifacts.ps1') -ManifestPath $ArtifactManifestPath -SourcePath $SourcePath -SvgPath $SvgPath -RequiredRoles $requiredArtifactRoleList }
}
else { Add-StateGate 'artifact-manifest-input' 'SKIPPED' 'ArtifactManifestPath was not supplied' 'Canonical, wrapper, and exported assets may not share one revision' }

if($VisualInspectionPath){
    Invoke-Gate 'visual-inspection' {
        $visualIssues=[System.Collections.Generic.List[object]]::new();$visual=$null;$visualRaw=''
        try{$visualRaw=Get-Content -LiteralPath $VisualInspectionPath -Raw -Encoding UTF8;$visual=$visualRaw|ConvertFrom-Json}catch{Add-DrawioIssue -Issues $visualIssues -Type 'invalid-visual-inspection' -Element '' -Detail $_.Exception.Message -Evidence $_.Exception.Message -RepairClass 'repeat-visual-inspection'}
        if($visual){
            Add-UnknownPropertyIssues -Issues $visualIssues -Value $visual -Allowed @('schemaVersion','assetSha256','cropReportSha256','reviewedAt','reviewer','fullPage','cropsReviewed','reviewedCrops','notes') -Type 'visual-inspection-property' -Element 'visual-inspection' -RepairClass 'repeat-visual-inspection'
            foreach($field in @('schemaVersion','assetSha256','cropReportSha256','reviewedAt','reviewer','fullPage','cropsReviewed','reviewedCrops','notes')){if(-not$visual.PSObject.Properties[$field]){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-field' -Element $field -Detail 'Required field is missing' -Evidence $field -RepairClass 'repeat-visual-inspection'}}
            if($visual.PSObject.Properties['schemaVersion']-and(-not(Test-DrawioJsonInteger $visual.schemaVersion)-or[int64]$visual.schemaVersion-ne1)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-schema' -Element '' -Detail 'schemaVersion must be the integer 1' -Evidence ([string]$visual.schemaVersion) -RepairClass 'repeat-visual-inspection'}
            foreach($field in @('assetSha256','cropReportSha256','reviewer','fullPage','notes')){if($visual.PSObject.Properties[$field]-and-not(Test-DrawioJsonString $visual.$field)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-field-type' -Element $field -Detail 'Field must be a nonempty string' -Evidence ([string]$visual.$field) -RepairClass 'repeat-visual-inspection'}}
            if($visual.PSObject.Properties['assetSha256']-and[string]$visual.assetSha256-notmatch'^[0-9a-f]{64}$'){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-asset-hash' -Element '' -Detail 'assetSha256 must be a lowercase 64-character hexadecimal digest' -Evidence ([string]$visual.assetSha256) -RepairClass 'repeat-visual-inspection'}
            elseif($visual.PSObject.Properties['assetSha256']){
                $actualAssetSha256=(Get-FileHash -LiteralPath $SvgPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if([string]$visual.assetSha256-ne$actualAssetSha256){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-stale-asset' -Element '' -Detail 'assetSha256 does not match SvgPath' -Evidence "expected=$($visual.assetSha256);actual=$actualAssetSha256" -RepairClass 'repeat-visual-inspection'}
            }
            $reviewedAt=[DateTimeOffset]::MinValue
            $reviewedAtMembers=[regex]::Matches($visualRaw,'(?<!\\)"reviewedAt"\s*:')
            $reviewedAtMatch=[regex]::Match($visualRaw,'"reviewedAt"\s*:\s*"(?<value>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))"')
            $reviewedAtTypeValid=$visual.reviewedAt-is[string]-or$visual.reviewedAt-is[datetime]-or$visual.reviewedAt-is[datetimeoffset]
            if($visual.PSObject.Properties['reviewedAt']-and($reviewedAtMembers.Count-ne1-or-not$reviewedAtTypeValid-or-not$reviewedAtMatch.Success-or-not[DateTimeOffset]::TryParse($reviewedAtMatch.Groups['value'].Value,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind,[ref]$reviewedAt))){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-reviewed-at' -Element '' -Detail 'reviewedAt must be one RFC 3339 date-time string with timezone' -Evidence ([string]$visual.reviewedAt) -RepairClass 'repeat-visual-inspection'}
            if($visual.PSObject.Properties['reviewer']-and[string]::IsNullOrWhiteSpace([string]$visual.reviewer)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-reviewer' -Element '' -Detail 'reviewer must be nonempty' -Evidence '' -RepairClass 'repeat-visual-inspection'}
            if($visual.PSObject.Properties['notes']-and[string]::IsNullOrWhiteSpace([string]$visual.notes)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-notes' -Element '' -Detail 'notes must be nonempty' -Evidence '' -RepairClass 'repeat-visual-inspection'}
            if($visual.PSObject.Properties['fullPage']){if([string]$visual.fullPage-notin@('PASS','FAIL')){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-full-page' -Element '' -Detail 'fullPage must be PASS or FAIL' -Evidence ([string]$visual.fullPage) -RepairClass 'repeat-visual-inspection'}elseif([string]$visual.fullPage-eq'FAIL'){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-full-page' -Element '' -Detail 'Full-page inspection failed' -Evidence 'FAIL' -RepairClass 'repair-visual-layout'}}
            $cropCount=0
            if($visual.PSObject.Properties['cropsReviewed']){if(-not(Test-DrawioJsonInteger $visual.cropsReviewed)-or[int64]$visual.cropsReviewed-lt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crops' -Element '' -Detail 'cropsReviewed must be a nonnegative integer' -Evidence ([string]$visual.cropsReviewed) -RepairClass 'repeat-visual-inspection'}else{$cropCount=[int64]$visual.cropsReviewed}}
            $reviewedCrops=@()
            if($visual.PSObject.Properties['reviewedCrops']){if(-not(Test-DrawioJsonArray $visual.reviewedCrops)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-reviewed-crops-type' -Element 'reviewedCrops' -Detail 'reviewedCrops must be an array' -Evidence (Get-DrawioJsonTypeName $visual.reviewedCrops) -RepairClass 'repeat-visual-inspection'}else{$reviewedCrops=@($visual.reviewedCrops)}}
            foreach($reviewed in $reviewedCrops){Add-UnknownPropertyIssues -Issues $visualIssues -Value $reviewed -Allowed @('id','sha256') -Type 'visual-inspection-reviewed-crop-property' -Element ([string]$reviewed.id) -RepairClass 'repeat-visual-inspection';if(-not$reviewed.PSObject.Properties['id']-or-not(Test-DrawioJsonString $reviewed.id)-or-not$reviewed.PSObject.Properties['sha256']-or-not(Test-DrawioJsonString $reviewed.sha256)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-reviewed-crop' -Element ([string]$reviewed.id) -Detail 'Reviewed crop fields must be strings with a nonempty id' -Evidence ([string]$reviewed.sha256) -RepairClass 'repeat-visual-inspection'}}
            if($visual.PSObject.Properties['cropsReviewed']-and$cropCount-ne$reviewedCrops.Count){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-count' -Element '' -Detail 'cropsReviewed does not equal reviewedCrops count' -Evidence "declared=$cropCount;listed=$($reviewedCrops.Count)" -RepairClass 'repeat-visual-inspection'}
            if(-not$CropReportPath){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report' -Element '' -Detail 'CropReportPath is required with VisualInspectionPath' -Evidence '' -RepairClass 'repeat-visual-inspection'}
            elseif(-not(Test-Path -LiteralPath $CropReportPath -PathType Leaf)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report' -Element '' -Detail 'CropReportPath does not exist' -Evidence $CropReportPath -RepairClass 'repeat-visual-inspection'}
            else{
                $cropReport=$null
                try{$cropReport=Get-Content -LiteralPath $CropReportPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report' -Element '' -Detail $_.Exception.Message -Evidence $CropReportPath -RepairClass 'repeat-visual-inspection'}
                $actualCropReportSha256=(Get-FileHash -LiteralPath $CropReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
                if(-not$visual.PSObject.Properties['cropReportSha256']-or[string]$visual.cropReportSha256-notmatch'^[0-9a-f]{64}$'){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-hash' -Element '' -Detail 'cropReportSha256 must be a lowercase 64-character hexadecimal digest' -Evidence ([string]$visual.cropReportSha256) -RepairClass 'repeat-visual-inspection'}
                elseif([string]$visual.cropReportSha256-ne$actualCropReportSha256){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-stale-crop-report' -Element '' -Detail 'cropReportSha256 does not match CropReportPath' -Evidence "expected=$($visual.cropReportSha256);actual=$actualCropReportSha256" -RepairClass 'repeat-visual-inspection'}
                if($cropReport){
                    Add-UnknownPropertyIssues -Issues $visualIssues -Value $cropReport -Allowed @('SchemaVersion','Png','Svg','Report','ValidationReportSha256','IssueCount','ExportedCount','SkippedCount','Crops') -Type 'visual-inspection-crop-report-property' -Element 'crop-report' -RepairClass 'repeat-crop-export'
                    foreach($field in @('SchemaVersion','Png','Svg','Report','ValidationReportSha256','IssueCount','ExportedCount','SkippedCount','Crops')){if(-not$cropReport.PSObject.Properties[$field]){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-field' -Element $field -Detail 'Required crop-report field is missing' -Evidence $field -RepairClass 'repeat-crop-export'}}
                    if($cropReport.PSObject.Properties['SchemaVersion']-and(-not(Test-DrawioJsonInteger $cropReport.SchemaVersion)-or[int64]$cropReport.SchemaVersion-ne1)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-schema' -Element '' -Detail 'SchemaVersion must be the integer 1' -Evidence ([string]$cropReport.SchemaVersion) -RepairClass 'repeat-crop-export'}
                    foreach($field in @('Png','Svg','Report','ValidationReportSha256')){if($cropReport.PSObject.Properties[$field]-and-not(Test-DrawioJsonString $cropReport.$field)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-field-type' -Element $field -Detail 'Field must be a nonempty string' -Evidence ([string]$cropReport.$field) -RepairClass 'repeat-crop-export'}}
                    $reportCrops=@();if($cropReport.PSObject.Properties['Crops']){if(-not(Test-DrawioJsonArray $cropReport.Crops)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-crops-type' -Element 'Crops' -Detail 'Crops must be an array' -Evidence (Get-DrawioJsonTypeName $cropReport.Crops) -RepairClass 'repeat-crop-export'}else{$reportCrops=@($cropReport.Crops)}}
                    foreach($crop in $reportCrops){
                        Add-UnknownPropertyIssues -Issues $visualIssues -Value $crop -Allowed @('Gate','Element','Type','Status','Reason','Path','PixelBounds') -Type 'visual-inspection-crop-property' -Element ([string]$crop.Element) -RepairClass 'repeat-crop-export'
                        foreach($field in @('Gate','Element','Type','Status')){if(-not$crop.PSObject.Properties[$field]){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-field' -Element $field -Detail 'Required crop field is missing' -Evidence ([string]$crop.Element) -RepairClass 'repeat-crop-export'}}
                        foreach($field in @('Gate','Type','Status')){if($crop.PSObject.Properties[$field]-and-not(Test-DrawioJsonString $crop.$field)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-field-type' -Element $field -Detail 'Field must be a nonempty string' -Evidence ([string]$crop.$field) -RepairClass 'repeat-crop-export'}}
                        if($crop.PSObject.Properties['Element']-and-not(Test-DrawioJsonString $crop.Element -AllowEmpty)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-field-type' -Element 'Element' -Detail 'Element must be a string' -Evidence ([string]$crop.Element) -RepairClass 'repeat-crop-export'}
                        if($crop.PSObject.Properties['Status']-and[string]$crop.Status-notin@('EXPORTED','SKIPPED')){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-status' -Element ([string]$crop.Element) -Detail 'Status must be EXPORTED or SKIPPED' -Evidence ([string]$crop.Status) -RepairClass 'repeat-crop-export'}
                        if([string]$crop.Status-eq'EXPORTED'){
                            if(-not$crop.PSObject.Properties['Path']-or-not(Test-DrawioJsonString $crop.Path)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-path' -Element ([string]$crop.Element) -Detail 'EXPORTED crop requires a nonempty string Path' -Evidence ([string]$crop.Path) -RepairClass 'repeat-crop-export'}
                            if(-not$crop.PSObject.Properties['PixelBounds']){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-bounds' -Element ([string]$crop.Element) -Detail 'EXPORTED crop requires PixelBounds' -Evidence '' -RepairClass 'repeat-crop-export'}
                        }
                        elseif([string]$crop.Status-eq'SKIPPED' -and (-not$crop.PSObject.Properties['Reason']-or-not(Test-DrawioJsonString $crop.Reason))){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-reason' -Element ([string]$crop.Element) -Detail 'SKIPPED crop requires a nonempty string Reason' -Evidence ([string]$crop.Reason) -RepairClass 'repeat-crop-export'}
                        if($crop.PSObject.Properties['PixelBounds']){
                            Add-UnknownPropertyIssues -Issues $visualIssues -Value $crop.PixelBounds -Allowed @('X','Y','Width','Height') -Type 'visual-inspection-crop-bounds-property' -Element ([string]$crop.Element) -RepairClass 'repeat-crop-export'
                            foreach($field in @('X','Y','Width','Height')){if(-not$crop.PixelBounds.PSObject.Properties[$field]-or-not(Test-DrawioJsonInteger $crop.PixelBounds.$field)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-bounds' -Element ([string]$crop.Element) -Detail "$field must be an integer" -Evidence ([string]$crop.PixelBounds.$field) -RepairClass 'repeat-crop-export'}}
                            foreach($field in @('X','Y')){if($crop.PixelBounds.PSObject.Properties[$field]-and(Test-DrawioJsonInteger $crop.PixelBounds.$field)-and[int64]$crop.PixelBounds.$field-lt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-bounds' -Element ([string]$crop.Element) -Detail "$field must be nonnegative" -Evidence ([string]$crop.PixelBounds.$field) -RepairClass 'repeat-crop-export'}}
                            foreach($field in @('Width','Height')){if($crop.PixelBounds.PSObject.Properties[$field]-and(Test-DrawioJsonInteger $crop.PixelBounds.$field)-and[int64]$crop.PixelBounds.$field-le0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-bounds' -Element ([string]$crop.Element) -Detail "$field must be positive" -Evidence ([string]$crop.PixelBounds.$field) -RepairClass 'repeat-crop-export'}}
                        }
                    }
                    $actualExportedCount=@($reportCrops|Where-Object{[string]$_.Status-eq'EXPORTED'}).Count;$actualSkippedCount=@($reportCrops|Where-Object{[string]$_.Status-eq'SKIPPED'}).Count
                    $reportCounts=@{};foreach($field in @('IssueCount','ExportedCount','SkippedCount')){if($cropReport.PSObject.Properties[$field]-and(Test-DrawioJsonInteger $cropReport.$field)-and[int64]$cropReport.$field-ge0){$reportCounts[$field]=[int64]$cropReport.$field}else{Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-count' -Element $field -Detail 'Count must be a nonnegative integer' -Evidence ([string]$cropReport.$field) -RepairClass 'repeat-crop-export'}}
                    if($reportCounts.ContainsKey('IssueCount')-and$reportCounts.IssueCount-ne$reportCrops.Count){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-count' -Element 'IssueCount' -Detail 'IssueCount does not equal Crops count' -Evidence "declared=$($reportCounts.IssueCount);actual=$($reportCrops.Count)" -RepairClass 'repeat-crop-export'}
                    if($reportCounts.ContainsKey('ExportedCount')-and$reportCounts.ExportedCount-ne$actualExportedCount){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-count' -Element 'ExportedCount' -Detail 'ExportedCount does not match EXPORTED statuses' -Evidence "declared=$($reportCounts.ExportedCount);actual=$actualExportedCount" -RepairClass 'repeat-crop-export'}
                    if($reportCounts.ContainsKey('SkippedCount')-and$reportCounts.SkippedCount-ne$actualSkippedCount){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-count' -Element 'SkippedCount' -Detail 'SkippedCount does not match SKIPPED statuses' -Evidence "declared=$($reportCounts.SkippedCount);actual=$actualSkippedCount" -RepairClass 'repeat-crop-export'}
                    if($reportCounts.ContainsKey('IssueCount')-and$reportCounts.IssueCount-ne($actualExportedCount+$actualSkippedCount)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-count' -Element 'StatusCount' -Detail 'EXPORTED and SKIPPED counts do not cover every issue' -Evidence "issues=$($reportCounts.IssueCount);statuses=$($actualExportedCount+$actualSkippedCount)" -RepairClass 'repeat-crop-export'}
                    $reportDirectory=Split-Path -Parent (Resolve-Path -LiteralPath $CropReportPath).Path
                    if($cropReport.PSObject.Properties['Report']){$declaredReport=[string]$cropReport.Report;if(-not[System.IO.Path]::IsPathRooted($declaredReport)){$declaredReport=Join-Path $reportDirectory $declaredReport};if(-not(Test-Path -LiteralPath $declaredReport -PathType Leaf)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-report' -Element 'Report' -Detail 'Validation report does not exist' -Evidence ([string]$cropReport.Report) -RepairClass 'repeat-crop-export'}else{$actualValidationReportSha256=(Get-FileHash -LiteralPath $declaredReport -Algorithm SHA256).Hash.ToLowerInvariant();if(-not$cropReport.PSObject.Properties['ValidationReportSha256']-or[string]$cropReport.ValidationReportSha256-notmatch'^[0-9a-f]{64}$'){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-report-hash' -Element '' -Detail 'ValidationReportSha256 must be a lowercase SHA-256 digest' -Evidence ([string]$cropReport.ValidationReportSha256) -RepairClass 'repeat-crop-export'}elseif([string]$cropReport.ValidationReportSha256-ne$actualValidationReportSha256){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-stale-validation-report' -Element '' -Detail 'ValidationReportSha256 does not match Report' -Evidence "expected=$($cropReport.ValidationReportSha256);actual=$actualValidationReportSha256" -RepairClass 'repeat-crop-export'}else{$validationReport=$null;try{$validationReport=Get-Content -LiteralPath $declaredReport -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-report' -Element 'Report' -Detail $_.Exception.Message -Evidence $declaredReport -RepairClass 'repeat-crop-export'};if($validationReport){if(-not$validationReport.PSObject.Properties['Source']-or-not(Test-Path -LiteralPath ([string]$validationReport.Source) -PathType Leaf)-or(Resolve-Path -LiteralPath ([string]$validationReport.Source)).Path-ne(Resolve-Path -LiteralPath $SourcePath).Path){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-binding' -Element 'Source' -Detail 'Validation report does not identify SourcePath' -Evidence ([string]$validationReport.Source) -RepairClass 'repeat-validation'};if(-not$validationReport.PSObject.Properties['Svg']-or-not(Test-Path -LiteralPath ([string]$validationReport.Svg) -PathType Leaf)-or(Resolve-Path -LiteralPath ([string]$validationReport.Svg)).Path-ne(Resolve-Path -LiteralPath $SvgPath).Path){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-binding' -Element 'Svg' -Detail 'Validation report does not identify SvgPath' -Evidence ([string]$validationReport.Svg) -RepairClass 'repeat-validation'};$reportedFingerprints=@();foreach($reportedGate in @($validationReport.Gates|Where-Object{[string]$_.Name-notin@('visual-inspection','visual-inspection-input','warning-dispositions')})){foreach($reportedIssue in @($reportedGate.Result.Issues)){$reportedFingerprints+="$($reportedGate.Name)|$($reportedIssue.Severity)|$($reportedIssue.Type)|$($reportedIssue.Element)|$($reportedIssue.Detail)"}};$currentFingerprints=@();foreach($currentGate in @($gates|Where-Object{[string]$_.Name-notin@('visual-inspection','visual-inspection-input','warning-dispositions')})){foreach($currentIssue in @($currentGate.Result.Issues)){$currentFingerprints+="$($currentGate.Name)|$($currentIssue.Severity)|$($currentIssue.Type)|$($currentIssue.Element)|$($currentIssue.Detail)"}};$issueSetDelta=@(Compare-Object @($reportedFingerprints|Sort-Object) @($currentFingerprints|Sort-Object));if($issueSetDelta.Count-gt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-issue-set' -Element 'Report' -Detail 'Validation report findings differ from the current audit gates' -Evidence ($issueSetDelta|ConvertTo-Json -Compress) -RepairClass 'repeat-validation'}}}}}
                    if($validationReport){
                        if(-not$validationReport.PSObject.Properties['InputDigests']){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-contract' -Element 'InputDigests' -Detail 'Validation report lacks input digests' -Evidence '' -RepairClass 'repeat-validation'}else{$digestDelta=@(Compare-DrawioDigestSet -Reference $validationReport.InputDigests -Current $inputDigests);if($digestDelta.Count-gt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-contract' -Element 'InputDigests' -Detail 'Validation report input digests differ from the current audit' -Evidence ($digestDelta|ConvertTo-Json -Compress) -RepairClass 'repeat-validation'}}
                        if(-not$validationReport.PSObject.Properties['Family']-or[string]$validationReport.Family-ne$Family){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-contract' -Element 'Family' -Detail 'Validation report family differs from the current audit' -Evidence "reported=$($validationReport.Family);current=$Family" -RepairClass 'repeat-validation'}
                        if(-not$validationReport.PSObject.Properties['ValidationMode']-or[string]$validationReport.ValidationMode-ne$ValidationMode){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-contract' -Element 'ValidationMode' -Detail 'Validation report mode differs from the current audit' -Evidence "reported=$($validationReport.ValidationMode);current=$ValidationMode" -RepairClass 'repeat-validation'}
                        if($ValidationMode-eq'Approval'-and[string]$validationReport.ValidationMode-ne'Approval'){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-contract' -Element 'ValidationMode' -Detail 'Approval requires a pre-visual Approval validation report' -Evidence ([string]$validationReport.ValidationMode) -RepairClass 'repeat-validation'}
                        $reportedRoles=@();if($validationReport.PSObject.Properties['RequiredArtifactRoles']){$reportedRoles=@($validationReport.RequiredArtifactRoles|ForEach-Object{[string]$_}|Sort-Object)};$currentRoles=@($requiredArtifactRoleList|Sort-Object);$roleDelta=@(Compare-Object $reportedRoles $currentRoles);if($roleDelta.Count-gt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-contract' -Element 'RequiredArtifactRoles' -Detail 'Validation report artifact roles differ from the current audit' -Evidence ($roleDelta|ConvertTo-Json -Compress) -RepairClass 'repeat-validation'}
                        $gateDelta=@(Compare-DrawioMultiset -Reference (Get-DrawioGateMultiset $validationReport.Gates) -Difference (Get-DrawioGateMultiset $gates));if($gateDelta.Count-gt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-gate-contract' -Element 'Gates' -Detail 'Validation report gate states differ from the current pre-visual audit' -Evidence ($gateDelta|ConvertTo-Json -Compress) -RepairClass 'repeat-validation'}
                        $reportedIssueMultiset=@(Get-DrawioIssueMultiset $validationReport.Gates);$currentIssueMultiset=@(Get-DrawioIssueMultiset $gates);$currentIssueDelta=@(Compare-DrawioMultiset -Reference $reportedIssueMultiset -Difference $currentIssueMultiset);if($currentIssueDelta.Count-gt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-issue-contract' -Element 'Gates' -Detail 'Validation report issue multiplicity differs from the current pre-visual audit' -Evidence ($currentIssueDelta|ConvertTo-Json -Compress) -RepairClass 'repeat-validation'}
                        $cropIssueMultiset=@(Get-DrawioCropMultiset $reportCrops);$reportedCropDelta=@(Compare-DrawioMultiset -Reference $reportedIssueMultiset -Difference $cropIssueMultiset);$currentCropDelta=@(Compare-DrawioMultiset -Reference $currentIssueMultiset -Difference $cropIssueMultiset);if($reportedCropDelta.Count-gt0-or$currentCropDelta.Count-gt0){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-issue-mapping' -Element 'Crops' -Detail 'Crop rows do not exactly match validation issues by Gate, Type, Element, and multiplicity' -Evidence ([ordered]@{Reported=$reportedCropDelta;Current=$currentCropDelta}|ConvertTo-Json -Compress) -RepairClass 'repeat-crop-export'}
                        $reportedGates=@($validationReport.Gates);$reportedFailed=@($reportedGates|Where-Object{$_.Blocking-and-not$_.Passed}).Count;$reportedIncomplete=@($reportedGates|Where-Object{$_.Status-in@('SKIPPED','UNKNOWN')}).Count;$expectedOverall=if($reportedFailed-gt0){'FAIL'}elseif($reportedIncomplete-gt0){'PARTIAL'}else{'PASS'};$expectedDecision=if($expectedOverall-eq'PASS'){'APPROVED'}else{'NOT APPROVED'}
                        if(-not$validationReport.PSObject.Properties['GateCount']-or-not(Test-DrawioJsonInteger $validationReport.GateCount)-or[int64]$validationReport.GateCount-ne$reportedGates.Count-or-not$validationReport.PSObject.Properties['FailedGateCount']-or-not(Test-DrawioJsonInteger $validationReport.FailedGateCount)-or[int64]$validationReport.FailedGateCount-ne$reportedFailed-or-not$validationReport.PSObject.Properties['IncompleteGateCount']-or-not(Test-DrawioJsonInteger $validationReport.IncompleteGateCount)-or[int64]$validationReport.IncompleteGateCount-ne$reportedIncomplete-or[string]$validationReport.OverallStatus-ne$expectedOverall-or[string]$validationReport.Decision-ne$expectedDecision){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-validation-summary' -Element 'Report' -Detail 'Validation report summary is inconsistent with its gate states' -Evidence "gates=$($reportedGates.Count);failed=$reportedFailed;incomplete=$reportedIncomplete;status=$expectedOverall;decision=$expectedDecision" -RepairClass 'repeat-validation'}
                    }
                    if($cropReport.PSObject.Properties['Svg']){$declaredSvg=[string]$cropReport.Svg;if(-not[System.IO.Path]::IsPathRooted($declaredSvg)){$declaredSvg=Join-Path $reportDirectory $declaredSvg};if(-not(Test-Path -LiteralPath $declaredSvg -PathType Leaf)-or(Resolve-Path -LiteralPath $declaredSvg).Path -ne (Resolve-Path -LiteralPath $SvgPath).Path){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-binding' -Element 'Svg' -Detail 'Crop report does not identify SvgPath' -Evidence ([string]$cropReport.Svg) -RepairClass 'repeat-crop-export'}}
                    $resolvedCropSourcePng='';if($cropReport.PSObject.Properties['Png']){$declaredPng=[string]$cropReport.Png;if(-not[System.IO.Path]::IsPathRooted($declaredPng)){$declaredPng=Join-Path $reportDirectory $declaredPng};if(-not(Test-Path -LiteralPath $declaredPng -PathType Leaf)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-report-binding' -Element 'Png' -Detail 'Crop report source PNG does not exist' -Evidence ([string]$cropReport.Png) -RepairClass 'repeat-crop-export'}else{$resolvedCropSourcePng=(Resolve-Path -LiteralPath $declaredPng).Path;if($ArtifactManifestPath){try{$artifactManifest=Get-Content -LiteralPath $ArtifactManifestPath -Raw -Encoding UTF8|ConvertFrom-Json;$artifactBase=Split-Path -Parent (Resolve-Path -LiteralPath $ArtifactManifestPath).Path;$pngArtifacts=@($artifactManifest.artifacts|Where-Object{[string]$_.role-eq'png'});if($pngArtifacts.Count-ne1){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-artifact-binding' -Element 'Png' -Detail 'Artifact manifest must contain exactly one PNG' -Evidence ([string]$pngArtifacts.Count) -RepairClass 'regenerate-artifacts'}else{$artifactPng=Join-Path $artifactBase ([string]$pngArtifacts[0].path);if(-not(Test-Path -LiteralPath $artifactPng -PathType Leaf)-or(Resolve-Path -LiteralPath $artifactPng).Path-ne$resolvedCropSourcePng){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-artifact-binding' -Element 'Png' -Detail 'Crop report PNG differs from artifact manifest PNG' -Evidence "$declaredPng != $artifactPng" -RepairClass 'regenerate-artifacts'}}}catch{Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-artifact-binding' -Element 'Png' -Detail $_.Exception.Message -Evidence $ArtifactManifestPath -RepairClass 'regenerate-artifacts'}}}}
                    $expectedCrops=[System.Collections.Generic.List[object]]::new()
                    foreach($crop in $reportCrops){
                        if([string]$crop.Status-ne'EXPORTED'){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-unavailable' -Element ([string]$crop.Element) -Detail "Crop status is $($crop.Status)" -Evidence ([string]$crop.Path) -RepairClass 'repeat-crop-export';continue}
                        $cropPath=[string]$crop.Path;if(-not[System.IO.Path]::IsPathRooted($cropPath)){$cropPath=Join-Path $reportDirectory $cropPath}
                        if(-not(Test-Path -LiteralPath $cropPath -PathType Leaf)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-missing' -Element ([string]$crop.Element) -Detail 'Exported crop file does not exist' -Evidence $cropPath -RepairClass 'repeat-crop-export';continue}
                        if($resolvedCropSourcePng-and$crop.PSObject.Properties['PixelBounds']){try{if(-not(Test-DrawioCropPixels -SourcePngPath $resolvedCropSourcePng -CropPath $cropPath -PixelBounds $crop.PixelBounds)){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-pixels' -Element ([string]$crop.Element) -Detail 'Exported crop pixels do not match the declared source PNG and PixelBounds' -Evidence $cropPath -RepairClass 'repeat-crop-export'}}catch{Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-crop-pixels' -Element ([string]$crop.Element) -Detail $_.Exception.Message -Evidence $cropPath -RepairClass 'repeat-crop-export'}}
                        $cropId=[System.IO.Path]::GetFileNameWithoutExtension($cropPath);$cropSha256=(Get-FileHash -LiteralPath $cropPath -Algorithm SHA256).Hash.ToLowerInvariant()
                        $expectedCrops.Add([pscustomobject]@{Id=$cropId;Sha256=$cropSha256})
                    }
                    foreach($reviewed in $reviewedCrops){
                        if(-not$reviewed.PSObject.Properties['id']-or[string]::IsNullOrWhiteSpace([string]$reviewed.id)-or-not$reviewed.PSObject.Properties['sha256']-or[string]$reviewed.sha256-notmatch'^[0-9a-f]{64}$'){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-reviewed-crop' -Element ([string]$reviewed.id) -Detail 'Reviewed crop requires a nonempty id and lowercase SHA-256' -Evidence ([string]$reviewed.sha256) -RepairClass 'repeat-visual-inspection';continue}
                        $matches=@($expectedCrops|Where-Object{$_.Id-eq[string]$reviewed.id-and$_.Sha256-eq[string]$reviewed.sha256})
                        if($matches.Count-ne1){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-reviewed-crop-mismatch' -Element ([string]$reviewed.id) -Detail 'Reviewed crop is absent from the report or its digest is stale' -Evidence ([string]$reviewed.sha256) -RepairClass 'repeat-visual-inspection'}
                    }
                    foreach($expected in $expectedCrops){if(@($reviewedCrops|Where-Object{[string]$_.id-eq$expected.Id-and[string]$_.sha256-eq$expected.Sha256}).Count-ne1){Add-DrawioIssue -Issues $visualIssues -Type 'visual-inspection-unreviewed-crop' -Element $expected.Id -Detail 'Exported problem crop lacks matching review evidence' -Evidence $expected.Sha256 -RepairClass 'repeat-visual-inspection'}}
                }
            }
        }
        [pscustomobject]@{SchemaVersion=1;IssueCount=$visualIssues.Count;ErrorCount=@($visualIssues|Where-Object{$_.Severity-eq'ERROR'}).Count;WarningCount=@($visualIssues|Where-Object{$_.Severity-eq'WARNING'}).Count;Issues=@($visualIssues)}|ConvertTo-Json -Depth 8
    }
}
else{Add-StateGate 'visual-inspection-input' 'UNKNOWN' 'VisualInspectionPath was not supplied' 'Rendered visual quality has no explicit human-review evidence'}

$warningRecords=[System.Collections.Generic.List[object]]::new()
foreach($gate in $gates){foreach($issue in @($gate.Result.Issues)){if($issue.Severity-eq'WARNING'){$warningRecords.Add([pscustomobject]@{Gate=$gate.Name;Type=[string]$issue.Type;Element=[string]$issue.Element})}}}
if($warningRecords.Count-gt0){
    if(-not$WarningDispositionPath){Add-StateGate 'warning-dispositions' 'UNKNOWN' 'Warnings were emitted and WarningDispositionPath was not supplied' 'Every warning requires an accepted or fixed disposition before approval'}
    else{
        Invoke-Gate 'warning-dispositions' {
            $dispositionIssues=[System.Collections.Generic.List[object]]::new();$dispositions=$null
            try{$dispositions=Get-Content -LiteralPath $WarningDispositionPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-DrawioIssue -Issues $dispositionIssues -Type 'invalid-warning-dispositions' -Element '' -Detail $_.Exception.Message -Evidence $_.Exception.Message -RepairClass 'repair-warning-dispositions'}
            Add-UnknownPropertyIssues -Issues $dispositionIssues -Value $dispositions -Allowed @('schemaVersion','dispositions') -Type 'warning-disposition-property' -Element 'warning-dispositions' -RepairClass 'repair-warning-dispositions'
            foreach($field in @('schemaVersion','dispositions')){if($dispositions-and-not$dispositions.PSObject.Properties[$field]){Add-DrawioIssue -Issues $dispositionIssues -Type 'warning-disposition-field' -Element $field -Detail 'Required field is missing' -Evidence $field -RepairClass 'repair-warning-dispositions'}}
            if($dispositions-and$dispositions.PSObject.Properties['schemaVersion']-and(-not(Test-DrawioJsonInteger $dispositions.schemaVersion)-or[int64]$dispositions.schemaVersion-ne1)){Add-DrawioIssue -Issues $dispositionIssues -Type 'warning-disposition-schema' -Element '' -Detail 'schemaVersion must be the integer 1' -Evidence ([string]$dispositions.schemaVersion) -RepairClass 'repair-warning-dispositions'}
            $availableDispositions=@();if($dispositions-and$dispositions.PSObject.Properties['dispositions']){if(-not(Test-DrawioJsonArray $dispositions.dispositions)){Add-DrawioIssue -Issues $dispositionIssues -Type 'warning-disposition-array' -Element 'dispositions' -Detail 'dispositions must be an array' -Evidence (Get-DrawioJsonTypeName $dispositions.dispositions) -RepairClass 'repair-warning-dispositions'}else{$availableDispositions=@($dispositions.dispositions)}}
            foreach($disposition in $availableDispositions){Add-UnknownPropertyIssues -Issues $dispositionIssues -Value $disposition -Allowed @('gate','type','element','decision','reason') -Type 'warning-disposition-property' -Element ([string]$disposition.element) -RepairClass 'repair-warning-dispositions';foreach($field in @('gate','type','element','decision','reason')){if(-not$disposition.PSObject.Properties[$field]){Add-DrawioIssue -Issues $dispositionIssues -Type 'warning-disposition-field' -Element $field -Detail 'Required disposition field is missing' -Evidence ([string]$disposition.element) -RepairClass 'repair-warning-dispositions'}};foreach($field in @('gate','type','decision','reason')){if($disposition.PSObject.Properties[$field]-and-not(Test-DrawioJsonString $disposition.$field)){Add-DrawioIssue -Issues $dispositionIssues -Type 'warning-disposition-field-type' -Element $field -Detail 'Field must be a nonempty string' -Evidence ([string]$disposition.$field) -RepairClass 'repair-warning-dispositions'}};if($disposition.PSObject.Properties['element']-and-not(Test-DrawioJsonString $disposition.element -AllowEmpty)){Add-DrawioIssue -Issues $dispositionIssues -Type 'warning-disposition-field-type' -Element 'element' -Detail 'element must be a string' -Evidence ([string]$disposition.element) -RepairClass 'repair-warning-dispositions'};if($disposition.PSObject.Properties['decision']-and[string]$disposition.decision-notin@('accepted','fixed')){Add-DrawioIssue -Issues $dispositionIssues -Type 'warning-disposition-decision' -Element ([string]$disposition.element) -Detail 'decision must be accepted or fixed' -Evidence ([string]$disposition.decision) -RepairClass 'repair-warning-dispositions'}}
            foreach($warning in $warningRecords){
                $match=@($availableDispositions|Where-Object{$_.gate-eq$warning.Gate-and$_.type-eq$warning.Type-and[string]$_.element-eq$warning.Element})
                if($match.Count-ne1-or$match[0].decision-ne'accepted'-or[string]::IsNullOrWhiteSpace([string]$match[0].reason)){Add-DrawioIssue -Issues $dispositionIssues -Type 'missing-warning-disposition' -Element $warning.Element -Detail "$($warning.Gate)/$($warning.Type)" -Evidence "$($warning.Gate)/$($warning.Type)/$($warning.Element)" -RepairClass 'disposition-warning'}
            }
            foreach($disposition in $availableDispositions){if(@($warningRecords|Where-Object{$_.Gate-eq$disposition.gate-and$_.Type-eq$disposition.type-and[string]$_.Element-eq[string]$disposition.element}).Count-ne1){Add-DrawioIssue -Issues $dispositionIssues -Type 'unmatched-warning-disposition' -Element ([string]$disposition.element) -Detail "$($disposition.gate)/$($disposition.type) does not match exactly one current warning" -Evidence "$($disposition.gate)/$($disposition.type)/$($disposition.element)" -RepairClass 'repair-warning-dispositions'}}
            [pscustomobject]@{SchemaVersion=1;WarningCount=$warningRecords.Count;IssueCount=$dispositionIssues.Count;Issues=@($dispositionIssues)}|ConvertTo-Json -Depth 8
        }
    }
}

$failed = @($gates | Where-Object { $_.Blocking -and -not $_.Passed })
$incomplete = @($gates | Where-Object { $_.Status -in @('SKIPPED','UNKNOWN') })
$overallStatus = if($failed.Count-gt0){'FAIL'}elseif($incomplete.Count-gt0){'PARTIAL'}else{'PASS'}
$result = [pscustomobject]@{
    Source = $SourcePath
    Svg = $SvgPath
    Family = $Family
    Profile = $Family
    NotationProfile = $NotationProfilePath
    SemanticManifest = $SemanticManifestPath
    ArtifactManifest = $ArtifactManifestPath
    VisualInspection = $VisualInspectionPath
    CropReport = $CropReportPath
    WarningDispositions = $WarningDispositionPath
    ValidationMode = $ValidationMode
    RequiredArtifactRoles = @($requiredArtifactRoleList)
    InputDigests = $inputDigests
    OverallStatus = $overallStatus
    Decision = $(if($overallStatus-eq'PASS'){'APPROVED'}else{'NOT APPROVED'})
    GateCount = $gates.Count
    FailedGateCount = $failed.Count
    IncompleteGateCount = $incomplete.Count
    Gates = @($gates)
}

if ($ReportDirectory) {
    if (-not (Test-Path -LiteralPath $ReportDirectory)) { New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null }
    foreach ($gate in $gates) { $gate.Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $ReportDirectory ($gate.Name + '.json')) -Encoding UTF8 }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $ReportDirectory 'validation-summary.json') -Encoding UTF8
}

$result | ConvertTo-Json -Depth 12
if ($failed.Count -gt 0) { exit 1 }
