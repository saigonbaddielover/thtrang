param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [string]$SourcePath,
    [string]$SvgPath,
    [string[]]$RequiredRoles = @('canonical','wrapper','svg','png')
)

$ErrorActionPreference = 'Stop'
$issues = [System.Collections.Generic.List[object]]::new()

function Add-Issue {
    param(
        [string]$Type,
        [string]$Severity,
        [string]$Element,
        [string]$Evidence,
        [string]$RepairClass
    )
    $issues.Add([pscustomobject]@{
        Type=$Type
        Severity=$Severity
        Element=$Element
        Coordinates=$null
        Evidence=$Evidence
        RepairClass=$RepairClass
    })
}

function Add-UnknownProperties {
    param([object]$Value,[string[]]$Allowed,[string]$Element)
    foreach($property in @($Value.PSObject.Properties.Name|Where-Object{$_-notin$Allowed})){Add-Issue 'artifact-schema-property' 'ERROR' $Element $property 'repair-artifact-manifest'}
}

function Test-JsonInteger {
    param([object]$Value)
    $Value-is[sbyte]-or$Value-is[byte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]
}

function Test-JsonNumber {
    param([object]$Value)
    (Test-JsonInteger $Value)-or$Value-is[single]-or$Value-is[double]-or$Value-is[decimal]
}

function Test-PositiveFiniteNumber {
    param([object]$Value)
    if(-not(Test-JsonNumber $Value)){return $false}
    $number=[double]$Value
    -not[double]::IsNaN($number)-and-not[double]::IsInfinity($number)-and$number-gt0
}

function Test-JsonString {
    param([object]$Value)
    $Value-is[string]-and-not[string]::IsNullOrWhiteSpace($Value)
}

function Test-JsonObject {
    param([object]$Value)
    $Value-is[pscustomobject]
}

function Expand-DiagramPayload {
    param([System.Xml.XmlElement]$Diagram)
    $embedded=$Diagram.SelectSingleNode('./mxGraphModel')
    if($embedded){return $embedded.OuterXml}
    $payload=([string]$Diagram.InnerText).Trim()
    if(-not$payload){throw "Diagram page has no mxGraphModel payload: $($Diagram.id)"}
    $bytes=[Convert]::FromBase64String($payload)
    $input=[System.IO.MemoryStream]::new($bytes)
    $deflate=[System.IO.Compression.DeflateStream]::new($input,[System.IO.Compression.CompressionMode]::Decompress)
    $output=[System.IO.MemoryStream]::new()
    try{$deflate.CopyTo($output);[uri]::UnescapeDataString([System.Text.Encoding]::UTF8.GetString($output.ToArray()))}
    finally{$output.Dispose();$deflate.Dispose();$input.Dispose()}
}

function Get-XmlSignature {
    param([System.Xml.XmlNode]$Node)
    if($Node.NodeType-eq[System.Xml.XmlNodeType]::Text){$text=$Node.Value.Trim();if($text){return "T:$text"};return''}
    if($Node.NodeType-ne[System.Xml.XmlNodeType]::Element){return''}
    $attributes=@($Node.Attributes|ForEach-Object{"$($_.Name)=$($_.Value)"}|Sort-Object)-join'|'
    $children=@($Node.ChildNodes|ForEach-Object{Get-XmlSignature $_}|Where-Object{$_})-join''
    "<$($Node.Name)|$attributes>$children</$($Node.Name)>"
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Add-Issue 'missing-artifact-manifest' 'ERROR' '' $ManifestPath 'regenerate-artifacts'
}
else {
    try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Add-Issue 'invalid-artifact-manifest' 'ERROR' '' $_.Exception.Message 'regenerate-artifacts' }
}

if($null-ne$manifest-and-not(Test-JsonObject $manifest)){Add-Issue 'artifact-schema-type' 'ERROR' 'manifest' ([string]$manifest) 'repair-artifact-manifest';$manifest=$null}

if ($manifest) {
    Add-UnknownProperties $manifest @('schemaVersion','page','renderer','delivery','artifacts') 'manifest'
    foreach($field in @('schemaVersion','page','renderer','delivery','artifacts')){if(-not$manifest.PSObject.Properties[$field]){Add-Issue 'artifact-schema-field' 'ERROR' 'manifest' $field 'repair-artifact-manifest'}}
    if(-not(Test-JsonInteger $manifest.schemaVersion)-or[int64]$manifest.schemaVersion-ne2){Add-Issue 'unsupported-artifact-schema' 'ERROR' '' ([string]$manifest.schemaVersion) 'upgrade-manifest'}
    if(-not(Test-JsonObject $manifest.page)){Add-Issue 'artifact-schema-type' 'ERROR' 'page' ([string]$manifest.page) 'repair-artifact-manifest'}
    else{
        Add-UnknownProperties $manifest.page @('id','width','height') 'page'
        foreach($field in @('id','width','height')){if(-not$manifest.page.PSObject.Properties[$field]){Add-Issue 'artifact-schema-field' 'ERROR' 'page' $field 'repair-artifact-manifest'}}
        if(-not(Test-JsonString $manifest.page.id)-or-not(Test-PositiveFiniteNumber $manifest.page.width)-or-not(Test-PositiveFiniteNumber $manifest.page.height)){Add-Issue 'artifact-page-contract' 'ERROR' 'page' ($manifest.page|ConvertTo-Json -Compress) 'repair-artifact-manifest'}
    }
    if(-not(Test-JsonObject $manifest.renderer)){Add-Issue 'artifact-schema-type' 'ERROR' 'renderer' ([string]$manifest.renderer) 'repair-artifact-manifest'}
    else{Add-UnknownProperties $manifest.renderer @('name','version') 'renderer';if(-not(Test-JsonString $manifest.renderer.name)-or-not(Test-JsonString $manifest.renderer.version)){Add-Issue 'missing-renderer-provenance' 'ERROR' '' 'Renderer name and version must be nonempty strings' 'rerender-assets'}}
    if(-not(Test-JsonObject $manifest.delivery)){Add-Issue 'artifact-schema-type' 'ERROR' 'delivery' ([string]$manifest.delivery) 'repair-artifact-manifest'}
    else{
        $deliveryFields=@('frameWidthMm','frameHeightMm','densityPpi','minimumEffectiveFontPoints','cropBorder')
        Add-UnknownProperties $manifest.delivery $deliveryFields 'delivery'
        foreach($field in $deliveryFields){if(-not$manifest.delivery.PSObject.Properties[$field]){Add-Issue 'artifact-schema-field' 'ERROR' 'delivery' $field 'repair-artifact-manifest'}}
        foreach($field in @('frameWidthMm','frameHeightMm','minimumEffectiveFontPoints')){if(-not(Test-PositiveFiniteNumber $manifest.delivery.$field)){Add-Issue 'artifact-delivery-contract' 'ERROR' $field ([string]$manifest.delivery.$field) 'repair-artifact-manifest'}}
        if(-not(Test-JsonInteger $manifest.delivery.densityPpi)-or[int64]$manifest.delivery.densityPpi-lt72){Add-Issue 'artifact-delivery-contract' 'ERROR' 'densityPpi' ([string]$manifest.delivery.densityPpi) 'repair-artifact-manifest'}
        if(-not(Test-JsonNumber $manifest.delivery.cropBorder)-or[double]$manifest.delivery.cropBorder-lt0){Add-Issue 'artifact-delivery-contract' 'ERROR' 'cropBorder' ([string]$manifest.delivery.cropBorder) 'repair-artifact-manifest'}
    }
    $baseDirectory = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestPath).Path
    if($manifest.artifacts-isnot[System.Array]){$artifactType=if($null-eq$manifest.artifacts){'null'}else{$manifest.artifacts.GetType().FullName};Add-Issue 'artifact-schema-type' 'ERROR' 'artifacts' $artifactType 'repair-artifact-manifest'}
    $artifactEntries=if($manifest.artifacts-is[System.Array]){@($manifest.artifacts)}else{@()}
    if($artifactEntries.Count-lt2){Add-Issue 'artifact-entry-count' 'ERROR' 'artifacts' ([string]$artifactEntries.Count) 'repair-artifact-manifest'}
    $roles = @($artifactEntries | ForEach-Object { [string]$_.role })
    foreach ($requiredRole in $RequiredRoles) {
        if ($requiredRole -notin $roles) { Add-Issue 'missing-artifact-role' 'ERROR' $requiredRole $requiredRole 'regenerate-artifacts' }
    }
    foreach ($duplicate in @($roles | Group-Object | Where-Object Count -gt 1)) {
        Add-Issue 'duplicate-artifact-role' 'ERROR' $duplicate.Name ([string]$duplicate.Count) 'regenerate-artifacts'
    }
    $artifactPaths=@{}
    foreach ($artifact in $artifactEntries) {
        if(-not(Test-JsonObject $artifact)){Add-Issue 'artifact-schema-type' 'ERROR' 'artifact' ([string]$artifact) 'repair-artifact-manifest';continue}
        Add-UnknownProperties $artifact @('role','path','sha256') ([string]$artifact.role)
        foreach($field in @('role','path','sha256')){if(-not$artifact.PSObject.Properties[$field]){Add-Issue 'artifact-schema-field' 'ERROR' ([string]$artifact.role) $field 'repair-artifact-manifest'}}
        $role = [string]$artifact.role
        if(-not(Test-JsonString $artifact.role)-or$role-notin@('canonical','wrapper','svg','png','word-png','pdf')){Add-Issue 'unsupported-artifact-role' 'ERROR' $role $role 'repair-artifact-manifest'}
        if(-not(Test-JsonString $artifact.path)){Add-Issue 'artifact-path-contract' 'ERROR' $role ([string]$artifact.path) 'repair-artifact-manifest';continue}
        if(-not(Test-JsonString $artifact.sha256)-or[string]$artifact.sha256-notmatch'^[A-Fa-f0-9]{64}$'){Add-Issue 'artifact-hash-contract' 'ERROR' $role ([string]$artifact.sha256) 'repair-artifact-manifest'}
        $path = Join-Path $baseDirectory ([string]$artifact.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Issue 'missing-artifact' 'ERROR' $role $path 'regenerate-artifacts'
            continue
        }
        $path=(Resolve-Path -LiteralPath $path).Path
        $artifactPaths[$role]=$path
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne [string]$artifact.sha256) {
            Add-Issue 'artifact-hash-mismatch' 'ERROR' $role "$actual != $($artifact.sha256)" 'regenerate-artifacts'
        }
        if ($role -eq 'canonical') {
            try {
                [xml]$canonical = Get-Content -LiteralPath $path -Raw -Encoding UTF8
                $width = [double]$canonical.mxGraphModel.pageWidth
                $height = [double]$canonical.mxGraphModel.pageHeight
                if ([math]::Abs($width - [double]$manifest.page.width) -gt 0.01 -or [math]::Abs($height - [double]$manifest.page.height) -gt 0.01) {
                    Add-Issue 'artifact-page-mismatch' 'ERROR' $role "$width x $height" 'regenerate-artifacts'
                }
            }
            catch { Add-Issue 'invalid-canonical-artifact' 'ERROR' $role $_.Exception.Message 'repair-canonical' }
        }
    }
    if($SourcePath-and$artifactPaths.ContainsKey('canonical')){$expected=(Resolve-Path -LiteralPath $SourcePath).Path;if($artifactPaths.canonical-ne$expected){Add-Issue 'artifact-path-mismatch' 'ERROR' 'canonical' "$($artifactPaths.canonical) != $expected" 'regenerate-artifacts'}}
    if($SvgPath-and$artifactPaths.ContainsKey('svg')){$expected=(Resolve-Path -LiteralPath $SvgPath).Path;if($artifactPaths.svg-ne$expected){Add-Issue 'artifact-path-mismatch' 'ERROR' 'svg' "$($artifactPaths.svg) != $expected" 'regenerate-artifacts'}}
    if($artifactPaths.ContainsKey('canonical')-and$artifactPaths.ContainsKey('wrapper')){
        try{
            [xml]$canonical=Get-Content -LiteralPath $artifactPaths.canonical -Raw -Encoding UTF8
            [xml]$wrapper=Get-Content -LiteralPath $artifactPaths.wrapper -Raw -Encoding UTF8
            $pages=@($wrapper.SelectNodes('/mxfile/diagram'))
            $selected=@($pages|Where-Object{[string]$_.id-eq[string]$manifest.page.id})
            if($selected.Count-ne1){Add-Issue 'artifact-wrapper-page' 'ERROR' 'wrapper' "Expected page $($manifest.page.id)" 'sync-wrapper'}
            else{[xml]$wrapperModel=Expand-DiagramPayload $selected[0];if((Get-XmlSignature $canonical.DocumentElement)-ne(Get-XmlSignature $wrapperModel.DocumentElement)){Add-Issue 'artifact-wrapper-parity' 'ERROR' 'wrapper' 'Selected wrapper page differs from canonical XML' 'sync-wrapper'}}
        }
        catch{Add-Issue 'artifact-wrapper-parity' 'ERROR' 'wrapper' $_.Exception.Message 'sync-wrapper'}
    }
}

$result = [pscustomobject]@{
    Manifest=$ManifestPath
    IssueCount=$issues.Count
    ErrorCount=@($issues|Where-Object Severity -eq 'ERROR').Count
    WarningCount=@($issues|Where-Object Severity -eq 'WARNING').Count
    Issues=@($issues)
}
$result | ConvertTo-Json -Depth 8
if ($issues.Count -gt 0) { exit 1 }
