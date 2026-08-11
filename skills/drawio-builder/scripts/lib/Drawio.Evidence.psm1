function Test-DrawioJsonInteger {
    param([object]$Value)
    return $Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Test-DrawioJsonArray {
    param([object]$Value)
    return $Value -is [System.Array]
}

function Test-DrawioJsonString {
    param([object]$Value,[switch]$AllowEmpty)
    if ($Value -isnot [string]) { return $false }
    if ($AllowEmpty) { return $true }
    return -not [string]::IsNullOrWhiteSpace($Value)
}

function Get-DrawioJsonTypeName {
    param([object]$Value)
    if ($null -eq $Value) { return 'null' }
    return $Value.GetType().FullName
}

function Get-DrawioFileDigest {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DrawioInputDigests {
    param(
        [string]$SourcePath,
        [string]$SvgPath,
        [string]$QualityProfilePath,
        [string]$SemanticManifestPath,
        [string]$NotationProfilePath,
        [string]$ArtifactManifestPath
    )
    return [ordered]@{
        Source = Get-DrawioFileDigest $SourcePath
        Svg = Get-DrawioFileDigest $SvgPath
        QualityProfile = Get-DrawioFileDigest $QualityProfilePath
        SemanticManifest = Get-DrawioFileDigest $SemanticManifestPath
        NotationProfile = Get-DrawioFileDigest $NotationProfilePath
        ArtifactManifest = Get-DrawioFileDigest $ArtifactManifestPath
    }
}

function Get-DrawioPreVisualGates {
    param([object[]]$Gates)
    return @($Gates | Where-Object { [string]$_.Name -notin @('visual-inspection', 'visual-inspection-input', 'warning-dispositions') })
}

function Get-DrawioGateMultiset {
    param([object[]]$Gates)
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($gate in @(Get-DrawioPreVisualGates $Gates)) {
        $items.Add("$([string]$gate.Name)|$([string]$gate.Status)|$([bool]$gate.Blocking)")
    }
    return @($items | Sort-Object)
}

function Get-DrawioIssueMultiset {
    param([object[]]$Gates)
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($gate in @(Get-DrawioPreVisualGates $Gates)) {
        foreach ($issue in @($gate.Result.Issues)) {
            $items.Add("$([string]$gate.Name)|$([string]$issue.Type)|$([string]$issue.Element)")
        }
    }
    return @($items | Sort-Object)
}

function Get-DrawioCropMultiset {
    param([object[]]$Crops)
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($crop in @($Crops)) {
        $items.Add("$([string]$crop.Gate)|$([string]$crop.Type)|$([string]$crop.Element)")
    }
    return @($items | Sort-Object)
}

function Compare-DrawioMultiset {
    param([string[]]$Reference,[string[]]$Difference)
    return @(Compare-Object -ReferenceObject @($Reference) -DifferenceObject @($Difference))
}

function Compare-DrawioDigestSet {
    param([object]$Reference,[object]$Current)
    $differences = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('Source','Svg','QualityProfile','SemanticManifest','NotationProfile','ArtifactManifest')) {
        $referenceValue = if ($Reference -is [System.Collections.IDictionary] -and $Reference.Contains($name)) { [string]$Reference[$name] } elseif ($Reference -and $Reference.PSObject.Properties[$name]) { [string]$Reference.$name } else { '' }
        $currentValue = if ($Current -is [System.Collections.IDictionary] -and $Current.Contains($name)) { [string]$Current[$name] } elseif ($Current -and $Current.PSObject.Properties[$name]) { [string]$Current.$name } else { '' }
        if ($referenceValue -ne $currentValue) { $differences.Add("$name|$referenceValue|$currentValue") }
    }
    return @($differences)
}

Export-ModuleMember -Function Test-DrawioJsonInteger,Test-DrawioJsonArray,Test-DrawioJsonString,Get-DrawioJsonTypeName,Get-DrawioFileDigest,Get-DrawioInputDigests,Get-DrawioPreVisualGates,Get-DrawioGateMultiset,Get-DrawioIssueMultiset,Get-DrawioCropMultiset,Compare-DrawioMultiset,Compare-DrawioDigestSet
