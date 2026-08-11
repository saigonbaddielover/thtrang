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
        [string]$ArtifactManifestPath,
        [string]$WarningDispositionPath
    )
    return [ordered]@{
        Source = Get-DrawioFileDigest $SourcePath
        Svg = Get-DrawioFileDigest $SvgPath
        QualityProfile = Get-DrawioFileDigest $QualityProfilePath
        SemanticManifest = Get-DrawioFileDigest $SemanticManifestPath
        NotationProfile = Get-DrawioFileDigest $NotationProfilePath
        ArtifactManifest = Get-DrawioFileDigest $ArtifactManifestPath
        WarningDispositions = Get-DrawioFileDigest $WarningDispositionPath
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
    foreach ($name in @('Source','Svg','QualityProfile','SemanticManifest','NotationProfile','ArtifactManifest','WarningDispositions')) {
        $referenceValue = if ($Reference -is [System.Collections.IDictionary] -and $Reference.Contains($name)) { [string]$Reference[$name] } elseif ($Reference -and $Reference.PSObject.Properties[$name]) { [string]$Reference.$name } else { '' }
        $currentValue = if ($Current -is [System.Collections.IDictionary] -and $Current.Contains($name)) { [string]$Current[$name] } elseif ($Current -and $Current.PSObject.Properties[$name]) { [string]$Current.$name } else { '' }
        if ($referenceValue -ne $currentValue) { $differences.Add("$name|$referenceValue|$currentValue") }
    }
    return @($differences)
}

function Test-DrawioCropPixels {
    param(
        [string]$SourcePngPath,
        [string]$CropPath,
        [object]$PixelBounds
    )
    Add-Type -AssemblyName System.Drawing
    $source = [System.Drawing.Bitmap]::new($SourcePngPath)
    $crop = [System.Drawing.Bitmap]::new($CropPath)
    $sourceRegion = $null
    $cropRegion = $null
    $sourceData = $null
    $cropData = $null
    try {
        $x = [int]$PixelBounds.X
        $y = [int]$PixelBounds.Y
        $width = [int]$PixelBounds.Width
        $height = [int]$PixelBounds.Height
        if ($x -lt 0 -or $y -lt 0 -or $width -le 0 -or $height -le 0) { return $false }
        if ($x + $width -gt $source.Width -or $y + $height -gt $source.Height) { return $false }
        if ($crop.Width -ne $width -or $crop.Height -ne $height) { return $false }
        $pixelFormat = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        $sourceRegion = $source.Clone([System.Drawing.Rectangle]::new($x,$y,$width,$height),$pixelFormat)
        $cropRegion = $crop.Clone([System.Drawing.Rectangle]::new(0,0,$width,$height),$pixelFormat)
        $rectangle = [System.Drawing.Rectangle]::new(0,0,$width,$height)
        $sourceData = $sourceRegion.LockBits($rectangle,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,$pixelFormat)
        $cropData = $cropRegion.LockBits($rectangle,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,$pixelFormat)
        if ($sourceData.Stride -ne $cropData.Stride) { return $false }
        $byteCount = [math]::Abs($sourceData.Stride) * $height
        $sourceBytes = [byte[]]::new($byteCount)
        $cropBytes = [byte[]]::new($byteCount)
        [System.Runtime.InteropServices.Marshal]::Copy($sourceData.Scan0,$sourceBytes,0,$byteCount)
        [System.Runtime.InteropServices.Marshal]::Copy($cropData.Scan0,$cropBytes,0,$byteCount)
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try { return [Convert]::ToBase64String($hasher.ComputeHash($sourceBytes)) -eq [Convert]::ToBase64String($hasher.ComputeHash($cropBytes)) }
        finally { $hasher.Dispose() }
    }
    finally {
        if ($sourceData) { $sourceRegion.UnlockBits($sourceData) }
        if ($cropData) { $cropRegion.UnlockBits($cropData) }
        if ($sourceRegion) { $sourceRegion.Dispose() }
        if ($cropRegion) { $cropRegion.Dispose() }
        $crop.Dispose()
        $source.Dispose()
    }
}

Export-ModuleMember -Function Test-DrawioJsonInteger,Test-DrawioJsonArray,Test-DrawioJsonString,Get-DrawioJsonTypeName,Get-DrawioFileDigest,Get-DrawioInputDigests,Get-DrawioPreVisualGates,Get-DrawioGateMultiset,Get-DrawioIssueMultiset,Get-DrawioCropMultiset,Compare-DrawioMultiset,Compare-DrawioDigestSet,Test-DrawioCropPixels
