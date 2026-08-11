param(
    [Parameter(Mandatory = $true)][string]$QualityProfilePath
)

$ErrorActionPreference = 'Stop'
$issues = [System.Collections.Generic.List[object]]::new()

function Add-Issue {
    param([string]$Type,[string]$Element,[string]$Detail)
    $issues.Add([pscustomobject]@{Severity='ERROR';Type=$Type;Element=$Element;Detail=$Detail;Coordinates=$null;Evidence=$Detail;RepairClass='repair-quality-profile'})
}

function Test-JsonObject {
    param([object]$Value)
    $null -ne $Value -and $Value -isnot [System.Array] -and $Value -isnot [string] -and $Value -isnot [ValueType]
}

function Test-JsonArray {
    param([object]$Value)
    $Value -is [System.Array]
}

function Test-JsonInteger {
    param([object]$Value)
    $Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Test-PositiveNumber {
    param([object]$Value,[double]$MinimumExclusive = 0)
    if ($Value -is [string] -or $Value -is [bool] -or $null -eq $Value) { return $false }
    try { $number = [double]$Value } catch { return $false }
    -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number) -and $number -gt $MinimumExclusive
}

function Test-NonnegativeNumber {
    param([object]$Value)
    if ($Value -is [string] -or $Value -is [bool] -or $null -eq $Value) { return $false }
    try { $number = [double]$Value } catch { return $false }
    -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number) -and $number -ge 0
}

function Test-ObjectContract {
    param([object]$Value,[string]$Element,[string[]]$Required,[string[]]$Allowed)
    if (-not (Test-JsonObject $Value)) { Add-Issue 'quality-profile-type' $Element 'Expected an object'; return $false }
    foreach ($field in $Required) { if (-not $Value.PSObject.Properties[$field]) { Add-Issue 'quality-profile-field' "$Element.$field" 'Required field is missing' } }
    foreach ($property in @($Value.PSObject.Properties)) { if ($property.Name -notin $Allowed) { Add-Issue 'quality-profile-property' "$Element.$($property.Name)" 'Field is not allowed' } }
    $true
}

$quality = $null
if (-not (Test-Path -LiteralPath $QualityProfilePath -PathType Leaf)) { Add-Issue 'quality-profile-missing' '' $QualityProfilePath }
else { try { $quality = Get-Content -LiteralPath $QualityProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Add-Issue 'quality-profile-json' '' $_.Exception.Message } }

$rootFields = @('schemaVersion','profile','pages','fonts','clearance','composition','export')
if (Test-ObjectContract $quality 'quality-profile' $rootFields $rootFields) {
    if (-not (Test-JsonInteger $quality.schemaVersion) -or [int64]$quality.schemaVersion -ne 2) { Add-Issue 'quality-profile-schema' 'schemaVersion' 'schemaVersion must be the integer 2' }
    if ($quality.profile -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$quality.profile)) { Add-Issue 'quality-profile-value' 'profile' 'profile must be a nonempty string' }
    if (Test-ObjectContract $quality.pages 'pages' @('portrait','landscape') @('portrait','landscape')) {
        foreach ($orientation in @('portrait','landscape')) {
            $page = $quality.pages.$orientation
            if (Test-ObjectContract $page "pages.$orientation" @('width','height') @('width','height')) { foreach ($field in @('width','height')) { if (-not (Test-PositiveNumber $page.$field)) { Add-Issue 'quality-profile-number' "pages.$orientation.$field" 'Expected a finite positive number' } } }
        }
    }
    $fontFields = @('bodyMinimum','edgeMinimum','titleMinimum','requiredFamilies')
    if (Test-ObjectContract $quality.fonts 'fonts' $fontFields $fontFields) {
        foreach ($field in @('bodyMinimum','edgeMinimum','titleMinimum')) { if (-not (Test-PositiveNumber $quality.fonts.$field)) { Add-Issue 'quality-profile-number' "fonts.$field" 'Expected a finite positive number' } }
        if (-not (Test-JsonArray $quality.fonts.requiredFamilies) -or @($quality.fonts.requiredFamilies).Count -eq 0) { Add-Issue 'quality-profile-array' 'fonts.requiredFamilies' 'Expected a nonempty array' }
        else { foreach ($family in @($quality.fonts.requiredFamilies)) { if ($family -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$family)) { Add-Issue 'quality-profile-value' 'fonts.requiredFamilies' 'Every family must be a nonempty string' } } }
    }
    $clearanceFields = @('labelInk','nodeLabelInk','collisionOverlap','shapeOutline','arrowContact','endpointStub','parallelDivider','pageConnector','laneMinimum','lanePreferred','edgeLabelAssociation')
    if (Test-ObjectContract $quality.clearance 'clearance' $clearanceFields $clearanceFields) { foreach ($field in $clearanceFields) { if (-not (Test-PositiveNumber $quality.clearance.$field)) { Add-Issue 'quality-profile-number' "clearance.$field" 'Expected a finite positive number' } } }
    $compositionFields = @('alignmentTolerance','sizeTolerance','spacingVarianceWarning','minimumContrast')
    if (Test-ObjectContract $quality.composition 'composition' $compositionFields $compositionFields) {
        foreach ($field in @('alignmentTolerance','sizeTolerance','spacingVarianceWarning')) { if (-not (Test-NonnegativeNumber $quality.composition.$field)) { Add-Issue 'quality-profile-number' "composition.$field" 'Expected a finite nonnegative number' } }
        if (-not (Test-PositiveNumber $quality.composition.minimumContrast 0.999999)) { Add-Issue 'quality-profile-number' 'composition.minimumContrast' 'Expected a finite number greater than or equal to 1' }
    }
    if (Test-ObjectContract $quality.export 'export' @('pngScale') @('pngScale')) { if (-not (Test-PositiveNumber $quality.export.pngScale)) { Add-Issue 'quality-profile-number' 'export.pngScale' 'Expected a finite positive number' } }
}

$result = [pscustomobject]@{QualityProfile=$QualityProfilePath;ErrorCount=$issues.Count;WarningCount=0;IssueCount=$issues.Count;Issues=@($issues)}
$result | ConvertTo-Json -Depth 8
if ($issues.Count -gt 0) { exit 1 }
