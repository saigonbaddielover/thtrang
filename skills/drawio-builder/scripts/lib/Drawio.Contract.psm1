Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Drawio.Core.psm1')

function ConvertTo-DrawioSemanticLabel {
    param([AllowNull()][string]$Value)
    if($null-eq$Value){return''}
    $decoded=[System.Net.WebUtility]::HtmlDecode($Value)
    $decoded=[regex]::Replace($decoded,'(?i)<br\s*/?>',"`n")
    $decoded=[regex]::Replace($decoded,'<[^>]+>','')
    ([regex]::Replace($decoded,'\s+',' ')).Trim()
}

function Get-StyleTokens {
    param([AllowNull()][string]$Style)
    @($Style.Split(';',[System.StringSplitOptions]::RemoveEmptyEntries)|ForEach-Object{$_.Trim()}|Where-Object{$_})
}

function Test-StyleMatcher {
    param([string[]]$Tokens,[object]$Matcher)
    if($Matcher-is[string]){$allOf=@([string]$Matcher);$noneOf=@()}
    else{$allOf=@($Matcher.allOf);$noneOf=if($Matcher.PSObject.Properties['noneOf']){@($Matcher.noneOf)}else{@()}}
    if($allOf.Count-eq0){return $false}
    foreach($required in $allOf){if([string]$required-match'^(?:LIVE_SEARCH_REQUIRED|AUTHORITATIVE_MAPPING_REQUIRED):'){return $false};if([string]$required-notin$Tokens){return $false}}
    foreach($forbidden in $noneOf){if([string]$forbidden-in$Tokens){return $false}}
    $true
}

function Test-StyleMatchers {
    param([string[]]$Tokens,[object[]]$Matchers)
    foreach($matcher in $Matchers){if(Test-StyleMatcher $Tokens $matcher){return $true}}
    $false
}

function Get-AnchorSides {
    param([hashtable]$Style,[string]$Prefix,[double]$Tolerance=0.05)
    $sides=[System.Collections.Generic.List[string]]::new();$xKey=$Prefix+'X';$yKey=$Prefix+'Y'
    if($Style.ContainsKey($xKey)){$x=ConvertTo-DrawioNumber $Style[$xKey];if([math]::Abs($x)-le$Tolerance){$sides.Add('left')};if([math]::Abs($x-1)-le$Tolerance){$sides.Add('right')}}
    if($Style.ContainsKey($yKey)){$y=ConvertTo-DrawioNumber $Style[$yKey];if([math]::Abs($y)-le$Tolerance){$sides.Add('top')};if([math]::Abs($y-1)-le$Tolerance){$sides.Add('bottom')}}
    @($sides|Sort-Object -Unique)
}

function Test-DirectionalMarker {
    param([AllowNull()][string]$Value)
    -not [string]::IsNullOrWhiteSpace($Value) -and $Value -ne 'none' -and $Value -notmatch '(?i)^ER'
}

function Add-ContractIssue {
    param([System.Collections.IList]$Issues,[string]$Type,[string]$Element,[string]$Detail,[string]$Severity='ERROR',[string]$RepairClass='correct-contract-or-xml')
    Add-DrawioIssue -Issues $Issues -Type $Type -Element $Element -Detail $Detail -Severity $Severity -Evidence $Detail -RepairClass $RepairClass
}

function Test-ContractProperties {
    param(
        [AllowNull()][object]$Value,
        [string[]]$Names,
        [System.Collections.IList]$Issues,
        [string]$Type,
        [string]$Element
    )
    if ($null -eq $Value) {
        Add-ContractIssue $Issues $Type $Element "Missing object: $Element"
        return $false
    }
    $valid = $true
    foreach ($name in $Names) {
        if (-not $Value.PSObject.Properties[$name]) {
            Add-ContractIssue $Issues $Type $Element "Missing required field: $name"
            $valid = $false
        }
    }
    $valid
}

function Test-RuleDisposition {
    param([object]$Disposition,[string]$RuleSeverity)
    if($null-eq$Disposition-or-not$Disposition.PSObject.Properties['decision']-or-not$Disposition.PSObject.Properties['evidence']){return $false}
    $decision=[string]$Disposition.decision;$evidence=$Disposition.evidence
    if($null-eq$evidence-or-not$evidence.PSObject.Properties['source']-or[string]::IsNullOrWhiteSpace([string]$evidence.source)){return $false}
    if($RuleSeverity-eq'ERROR'-and$decision-ne'verified'){return $false}
    if($decision-eq'verified'){
        $hasReference=$evidence.PSObject.Properties['reference']-and-not[string]::IsNullOrWhiteSpace([string]$evidence.reference)
        $hasDigest=$evidence.PSObject.Properties['sha256']-and[string]$evidence.sha256-match'^[0-9a-f]{64}$'
        return $hasReference-or$hasDigest
    }
    if($decision-in@('accepted','not-applicable')){return $RuleSeverity-ne'ERROR'-and$evidence.PSObject.Properties['reason']-and-not[string]::IsNullOrWhiteSpace([string]$evidence.reason)}
    $false
}

function Test-AllowedContractFields {
    param([AllowNull()][object]$Value,[string[]]$Allowed,[System.Collections.IList]$Issues,[string]$Element)
    if($null-eq$Value){return}
    foreach($property in @($Value.PSObject.Properties)){if([string]$property.Name-notin$Allowed){Add-ContractIssue $Issues 'invalid-contract-field' "$Element.$($property.Name)" 'Field is not allowed by the contract'}}
}

function Add-MissingContextFields {
    param([AllowNull()][object]$Context,[string[]]$Required,[System.Collections.IList]$Issues)
    foreach($field in $Required){if($null-eq$Context-or-not$Context.PSObject.Properties[$field]-or$null-eq$Context.$field-or($Context.$field-is[string]-and[string]::IsNullOrWhiteSpace([string]$Context.$field))){Add-ContractIssue $Issues 'unresolved-semantic-context' "diagram.context.$field" 'Required context evidence is missing' 'WARNING' 'resolve-notation-context'}}
}

function Test-EnumContractField {
    param([AllowNull()][object]$Value,[string]$Field,[string[]]$Allowed,[System.Collections.IList]$Issues,[string]$Element)
    if($null-ne$Value-and$Value.PSObject.Properties[$Field]-and[string]$Value.$Field-notin$Allowed){Add-ContractIssue $Issues 'invalid-semantic-context' "$Element.$Field" "Expected one of: $($Allowed-join',')"}
}

function Test-PositiveContractField {
    param([AllowNull()][object]$Value,[string]$Field,[System.Collections.IList]$Issues,[string]$Element)
    if($null-ne$Value-and$Value.PSObject.Properties[$Field]){try{$number=[double]$Value.$Field;if([double]::IsNaN($number)-or[double]::IsInfinity($number)-or$number-le0){throw 'range'}}catch{Add-ContractIssue $Issues 'invalid-semantic-context' "$Element.$Field" 'Expected a finite positive number'}}
}

function Test-NonemptyContractField {
    param([AllowNull()][object]$Value,[string]$Field,[System.Collections.IList]$Issues,[string]$Element)
    if($null-ne$Value-and$Value.PSObject.Properties[$Field]-and(-not($Value.$Field-is[string])-or[string]::IsNullOrWhiteSpace([string]$Value.$Field))){Add-ContractIssue $Issues 'invalid-semantic-context' "$Element.$Field" 'Expected a nonempty string'}
}

function Test-ContextObjectArray {
    param([AllowNull()][object]$Context,[string]$Field,[string[]]$Required,[string[]]$Allowed,[System.Collections.IList]$Issues)
    if($null-eq$Context-or-not$Context.PSObject.Properties[$Field]){return @()}
    $items=@($Context.$Field);if($items.Count-eq0){Add-ContractIssue $Issues 'invalid-semantic-context' "diagram.context.$Field" 'Expected at least one item';return @()}
    foreach($item in $items){Test-AllowedContractFields $item $Allowed $Issues "diagram.context.$Field";foreach($name in $Required){if($null-eq$item-or-not$item.PSObject.Properties[$name]){Add-ContractIssue $Issues 'invalid-semantic-context' "diagram.context.$Field.$name" 'Required field is missing'}}}
    @($items)
}

function Invoke-DrawioContractAudit {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$Family,
        [string]$SemanticManifestPath,
        [string]$NotationProfilePath
    )
    [xml]$source=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8;$cells=Get-DrawioCells $source;$issues=[System.Collections.Generic.List[object]]::new();$manifest=$null;$notation=$null;$manifestUsable=$false;$notationUsable=$false;$manifestFamily=''
    if($SemanticManifestPath){if(-not(Test-Path -LiteralPath $SemanticManifestPath -PathType Leaf)){Add-ContractIssue $issues 'missing-semantic-manifest' '' $SemanticManifestPath}else{try{$manifest=Get-Content -LiteralPath $SemanticManifestPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-ContractIssue $issues 'invalid-semantic-manifest' '' $_.Exception.Message}}}
    if($NotationProfilePath){if(-not(Test-Path -LiteralPath $NotationProfilePath -PathType Leaf)){Add-ContractIssue $issues 'missing-notation-profile' '' $NotationProfilePath}else{try{$notation=Get-Content -LiteralPath $NotationProfilePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-ContractIssue $issues 'invalid-notation-profile' '' $_.Exception.Message}}}
    if($manifest){
        Test-AllowedContractFields $manifest @('schemaVersion','diagram','nodes','edges','ruleDispositions') $issues 'semantic-manifest'
        $manifestUsable=Test-ContractProperties $manifest @('schemaVersion','diagram','nodes','edges') $issues 'invalid-semantic-contract' 'semantic-manifest'
        if($manifest.PSObject.Properties['diagram']){Test-AllowedContractFields $manifest.diagram @('id','family','subtype','orientation','page','standard','context') $issues 'diagram';$manifestUsable=(Test-ContractProperties $manifest.diagram @('id','family','orientation') $issues 'invalid-semantic-contract' 'diagram')-and$manifestUsable}
        if($manifest.PSObject.Properties['schemaVersion']-and[string]$manifest.schemaVersion-ne'1'){Add-ContractIssue $issues 'semantic-schema-version' '' "Expected 1, found $($manifest.schemaVersion)";$manifestUsable=$false}
        if($manifest.PSObject.Properties['diagram']){
            if($manifest.diagram.PSObject.Properties['id']-and[string]::IsNullOrWhiteSpace([string]$manifest.diagram.id)){Add-ContractIssue $issues 'invalid-semantic-contract' 'diagram.id' 'Diagram id must be nonempty';$manifestUsable=$false}
            if($manifest.diagram.PSObject.Properties['orientation']-and[string]$manifest.diagram.orientation-notin@('portrait','landscape','custom')){Add-ContractIssue $issues 'invalid-semantic-contract' 'diagram.orientation' 'Orientation is invalid';$manifestUsable=$false}
            if($manifest.diagram.PSObject.Properties['page']){$page=$manifest.diagram.page;Test-AllowedContractFields $page @('width','height') $issues 'diagram.page';foreach($field in @('width','height')){if(-not$page.PSObject.Properties[$field]){Add-ContractIssue $issues 'invalid-semantic-contract' "diagram.page.$field" 'Required field is missing'}else{Test-PositiveContractField $page $field $issues 'diagram.page'}}}
            if($manifest.diagram.PSObject.Properties['standard']){$standardValue=$manifest.diagram.standard;Test-AllowedContractFields $standardValue @('name','version','source') $issues 'diagram.standard';foreach($field in @('name','source')){if(-not$standardValue.PSObject.Properties[$field]){Add-ContractIssue $issues 'invalid-semantic-contract' "diagram.standard.$field" 'Required field is missing'}else{Test-NonemptyContractField $standardValue $field $issues 'diagram.standard'}}}
        }
        if($manifest.PSObject.Properties['diagram']-and$manifest.diagram.PSObject.Properties['family']){
            $manifestFamily=[string]$manifest.diagram.family
            if($manifestFamily-in@('bpmn','uml','erd','engineering','electrical','pid')){
                $standard=if($manifest.diagram.PSObject.Properties['standard']){$manifest.diagram.standard}else{$null}
                foreach($field in @('name','source')){if($null-eq$standard-or-not$standard.PSObject.Properties[$field]-or[string]::IsNullOrWhiteSpace([string]$standard.$field)){Add-ContractIssue $issues 'unresolved-semantic-context' "diagram.standard.$field" 'Required standard evidence is missing' 'WARNING' 'resolve-notation-context'}}
            }
            if($manifestFamily-in@('cloud','network','engineering','electrical','pid','floorplan','wireframe')){
                $context=if($manifest.diagram.PSObject.Properties['context']){$manifest.diagram.context}else{$null}
                $contextFields=switch($manifestFamily){'cloud'{@('provider','providerIconRelease','providerIconSource')};'network'{@('vendor','vendorConvention','vendorIconRelease','vendorIconSource','networkLayer')};'engineering'{@('symbolStandard','symbolMappings')};'electrical'{@('standardEdition','symbolStandard','symbolStandardEdition','symbolMappings')};'pid'{@('symbolStandard','symbolStandardEdition','instrumentStandard','instrumentStandardEdition','projectLegend','symbolMappings')};'floorplan'{@('scaleRatio','symbolStandard','symbolStandardEdition','dimensions','wallOpenings','circulationClearances')};'wireframe'{@('viewport','fidelity','designSystem','designSystemVersion','componentStates','interactionLegend','repeatedComponents')}}
                Add-MissingContextFields $context $contextFields $issues
                Test-AllowedContractFields $context @('provider','providerIconRelease','providerIconSource','vendor','vendorConvention','vendorIconRelease','vendorIconSource','networkLayer','standardEdition','symbolStandard','symbolStandardEdition','instrumentStandard','instrumentStandardEdition','projectLegend','scaleRatio','dimensions','wallOpenings','circulationClearances','fidelity','designSystem','designSystemVersion','viewport','componentStates','interactionLegend','repeatedComponents','symbolMappings') $issues 'diagram.context'
                foreach($field in @('provider','providerIconRelease','providerIconSource','vendor','vendorConvention','vendorIconRelease','vendorIconSource','standardEdition','symbolStandard','symbolStandardEdition','instrumentStandard','instrumentStandardEdition','projectLegend','designSystem','designSystemVersion')){Test-NonemptyContractField $context $field $issues 'diagram.context'}
                Test-EnumContractField $context 'networkLayer' @('logical','physical','security-zone','traffic-flow') $issues 'diagram.context';Test-EnumContractField $context 'fidelity' @('low','mid','high') $issues 'diagram.context'
                foreach($field in @('providerIconRelease','vendorConvention','vendorIconRelease','standardEdition','symbolStandard','symbolStandardEdition','instrumentStandard','instrumentStandardEdition','designSystem','designSystemVersion')){if($context-and$context.PSObject.Properties[$field]-and[string]$context.$field-eq'UNKNOWN'){Add-ContractIssue $issues 'unresolved-semantic-context' "diagram.context.$field" 'UNKNOWN is not an executable context value' 'WARNING' 'resolve-notation-context'}}
                if($context-and$context.PSObject.Properties['scaleRatio']){$item=$context.scaleRatio;Test-AllowedContractFields $item @('drawingUnits','modelUnits','modelUnit') $issues 'diagram.context.scaleRatio';foreach($field in @('drawingUnits','modelUnits','modelUnit')){if(-not$item.PSObject.Properties[$field]){Add-ContractIssue $issues 'invalid-semantic-context' "diagram.context.scaleRatio.$field" 'Required field is missing'}};Test-PositiveContractField $item 'drawingUnits' $issues 'diagram.context.scaleRatio';Test-PositiveContractField $item 'modelUnits' $issues 'diagram.context.scaleRatio';Test-EnumContractField $item 'modelUnit' @('mm','cm','m','in','ft') $issues 'diagram.context.scaleRatio'}
                if($context-and$context.PSObject.Properties['viewport']){$item=$context.viewport;Test-AllowedContractFields $item @('width','height','unit') $issues 'diagram.context.viewport';foreach($field in @('width','height','unit')){if(-not$item.PSObject.Properties[$field]){Add-ContractIssue $issues 'invalid-semantic-context' "diagram.context.viewport.$field" 'Required field is missing'}};Test-PositiveContractField $item 'width' $issues 'diagram.context.viewport';Test-PositiveContractField $item 'height' $issues 'diagram.context.viewport';Test-EnumContractField $item 'unit' @('px') $issues 'diagram.context.viewport'}
                $dimensions=Test-ContextObjectArray $context 'dimensions' @('elementId','width','height','unit','source') @('elementId','width','height','unit','source') $issues;foreach($item in $dimensions){foreach($field in @('elementId','source')){Test-NonemptyContractField $item $field $issues 'diagram.context.dimensions'};Test-PositiveContractField $item 'width' $issues 'diagram.context.dimensions';Test-PositiveContractField $item 'height' $issues 'diagram.context.dimensions';Test-EnumContractField $item 'unit' @('mm','cm','m','in','ft') $issues 'diagram.context.dimensions'}
                $openings=Test-ContextObjectArray $context 'wallOpenings' @('openingId','wallId','handedness','swing','width','unit','source') @('openingId','wallId','handedness','swing','width','unit','source') $issues;foreach($item in $openings){foreach($field in @('openingId','wallId','source')){Test-NonemptyContractField $item $field $issues 'diagram.context.wallOpenings'};Test-PositiveContractField $item 'width' $issues 'diagram.context.wallOpenings';Test-EnumContractField $item 'unit' @('mm','cm','m','in','ft') $issues 'diagram.context.wallOpenings';Test-EnumContractField $item 'handedness' @('left','right','double','not-applicable') $issues 'diagram.context.wallOpenings';Test-EnumContractField $item 'swing' @('inward','outward','both','fixed') $issues 'diagram.context.wallOpenings'}
                $clearances=Test-ContextObjectArray $context 'circulationClearances' @('id','minimumWidth','unit','source') @('id','minimumWidth','unit','source') $issues;foreach($item in $clearances){foreach($field in @('id','source')){Test-NonemptyContractField $item $field $issues 'diagram.context.circulationClearances'};Test-PositiveContractField $item 'minimumWidth' $issues 'diagram.context.circulationClearances';Test-EnumContractField $item 'unit' @('mm','cm','m','in','ft') $issues 'diagram.context.circulationClearances'}
                $states=Test-ContextObjectArray $context 'componentStates' @('componentId','state') @('componentId','state') $issues;foreach($item in $states){foreach($field in @('componentId','state')){Test-NonemptyContractField $item $field $issues 'diagram.context.componentStates'}}
                $legend=Test-ContextObjectArray $context 'interactionLegend' @('id','meaning') @('id','meaning') $issues;foreach($item in $legend){foreach($field in @('id','meaning')){Test-NonemptyContractField $item $field $issues 'diagram.context.interactionLegend'}}
                $repeated=Test-ContextObjectArray $context 'repeatedComponents' @('group','semanticType','width','height','count') @('group','semanticType','width','height','count') $issues;foreach($item in $repeated){foreach($field in @('group','semanticType')){Test-NonemptyContractField $item $field $issues 'diagram.context.repeatedComponents'};Test-PositiveContractField $item 'width' $issues 'diagram.context.repeatedComponents';Test-PositiveContractField $item 'height' $issues 'diagram.context.repeatedComponents';$count=0;if(-not$item.PSObject.Properties['count']-or-not[int]::TryParse([string]$item.count,[ref]$count)-or$count-lt2){Add-ContractIssue $issues 'invalid-semantic-context' 'diagram.context.repeatedComponents.count' 'Expected an integer greater than or equal to 2'}}
                $mappingRequired=if($manifestFamily-eq'electrical'){@('nodeId','semanticType','reference','source','orientation','ports')}elseif($manifestFamily-eq'pid'){@('nodeId','semanticType','reference','source','tag','ports')}else{@('nodeId','semanticType','reference','source')}
                $mappings=Test-ContextObjectArray $context 'symbolMappings' $mappingRequired @('nodeId','semanticType','reference','source','tag','orientation','ports') $issues;foreach($item in $mappings){foreach($field in @('nodeId','semanticType','reference','source','tag')){Test-NonemptyContractField $item $field $issues 'diagram.context.symbolMappings'};if($item.PSObject.Properties['reference']-and[string]$item.reference-eq'UNKNOWN'){Add-ContractIssue $issues 'unresolved-semantic-context' 'diagram.context.symbolMappings.reference' 'UNKNOWN is not an executable symbol reference' 'WARNING' 'resolve-notation-context'};Test-EnumContractField $item 'orientation' @('north','east','south','west') $issues 'diagram.context.symbolMappings';if($item.PSObject.Properties['ports']){$ports=@($item.ports);if($ports.Count-eq0){Add-ContractIssue $issues 'invalid-semantic-context' 'diagram.context.symbolMappings.ports' 'Expected at least one port'};foreach($port in $ports){Test-AllowedContractFields $port @('id','role','side') $issues 'diagram.context.symbolMappings.ports';foreach($field in @('id','role','side')){if(-not$port.PSObject.Properties[$field]){Add-ContractIssue $issues 'invalid-semantic-context' "diagram.context.symbolMappings.ports.$field" 'Required field is missing'}};Test-NonemptyContractField $port 'id' $issues 'diagram.context.symbolMappings.ports';Test-NonemptyContractField $port 'role' $issues 'diagram.context.symbolMappings.ports';Test-EnumContractField $port 'side' @('top','right','bottom','left') $issues 'diagram.context.symbolMappings.ports'}}}
            }
        }
        foreach($node in $(if($manifest.PSObject.Properties['nodes']){@($manifest.nodes)}else{@()})){Test-AllowedContractFields $node @('id','label','semanticType','shapeClass','parent','lane','copyLineage','tag','orientation','componentState','repeatGroup') $issues "nodes.$($node.id)";$manifestUsable=(Test-ContractProperties $node @('id','label','semanticType') $issues 'invalid-semantic-node' $(if($node.PSObject.Properties['id']){[string]$node.id}else{'node'}))-and$manifestUsable;if($node.PSObject.Properties['id']-and[string]::IsNullOrWhiteSpace([string]$node.id)){Add-ContractIssue $issues 'invalid-semantic-node' '' 'Node id must be nonempty';$manifestUsable=$false};if($node.PSObject.Properties['semanticType']-and[string]::IsNullOrWhiteSpace([string]$node.semanticType)){Add-ContractIssue $issues 'invalid-semantic-node' ([string]$node.id) 'semanticType must be nonempty';$manifestUsable=$false};Test-EnumContractField $node 'orientation' @('north','east','south','west') $issues "nodes.$($node.id)"}
        foreach($edge in $(if($manifest.PSObject.Properties['edges']){@($manifest.edges)}else{@()})){Test-AllowedContractFields $edge @('id','source','target','label','direction','relationType','sourceSides','targetSides','copyLineage','boundaryFlowId','sourcePort','targetPort','lineClass','flowDirection','conductorType','connectionSemantics','interactionLegendId') $issues "edges.$($edge.id)";$manifestUsable=(Test-ContractProperties $edge @('id','source','target','label','direction') $issues 'invalid-semantic-edge' $(if($edge.PSObject.Properties['id']){[string]$edge.id}else{'edge'}))-and$manifestUsable;foreach($field in @('id','source','target')){if($edge.PSObject.Properties[$field]-and[string]::IsNullOrWhiteSpace([string]$edge.$field)){Add-ContractIssue $issues 'invalid-semantic-edge' ([string]$edge.id) "$field must be nonempty";$manifestUsable=$false}};if($edge.PSObject.Properties['direction']-and[string]$edge.direction-notin@('directed','undirected','bidirectional')){Add-ContractIssue $issues 'invalid-semantic-edge' ([string]$edge.id) 'direction is invalid';$manifestUsable=$false};Test-EnumContractField $edge 'flowDirection' @('source-to-target','target-to-source','bidirectional','none') $issues "edges.$($edge.id)";Test-EnumContractField $edge 'connectionSemantics' @('connected','crossing-without-connection') $issues "edges.$($edge.id)";foreach($sideField in @('sourceSides','targetSides')){if($edge.PSObject.Properties[$sideField]){foreach($side in @($edge.$sideField)){if([string]$side-notin@('top','right','bottom','left')){Add-ContractIssue $issues 'invalid-semantic-edge' ([string]$edge.id) "$sideField contains an invalid side"}}}};$requiredEdgeFields=if($manifestFamily-eq'electrical'){@('sourcePort','targetPort','conductorType','connectionSemantics')}elseif($manifestFamily-eq'pid'){@('sourcePort','targetPort','lineClass','flowDirection')}else{@()};foreach($field in $requiredEdgeFields){if(-not$edge.PSObject.Properties[$field]-or[string]::IsNullOrWhiteSpace([string]$edge.$field)){Add-ContractIssue $issues 'unresolved-semantic-context' "edges.$($edge.id).$field" 'Required technical connection evidence is missing' 'WARNING' 'resolve-notation-context'}}}
        foreach($disposition in $(if($manifest.PSObject.Properties['ruleDispositions']){@($manifest.ruleDispositions)}else{@()})){Test-AllowedContractFields $disposition @('ruleId','decision','evidence') $issues 'ruleDispositions';foreach($field in @('ruleId','decision','evidence')){if(-not$disposition.PSObject.Properties[$field]){Add-ContractIssue $issues 'invalid-rule-disposition' $field 'Required field is missing'}};Test-EnumContractField $disposition 'decision' @('verified','accepted','not-applicable') $issues 'ruleDispositions';if($disposition.PSObject.Properties['ruleId']-and[string]::IsNullOrWhiteSpace([string]$disposition.ruleId)){Add-ContractIssue $issues 'invalid-rule-disposition' 'ruleId' 'Expected a nonempty string'};if($disposition.PSObject.Properties['evidence']){$evidence=$disposition.evidence;Test-AllowedContractFields $evidence @('source','reference','sha256','reason') $issues 'ruleDispositions.evidence';if(-not$evidence.PSObject.Properties['source']-or[string]::IsNullOrWhiteSpace([string]$evidence.source)){Add-ContractIssue $issues 'invalid-rule-disposition' 'evidence.source' 'Expected a nonempty string'};if($evidence.PSObject.Properties['sha256']-and[string]$evidence.sha256-notmatch'^[0-9a-f]{64}$'){Add-ContractIssue $issues 'invalid-rule-disposition' 'evidence.sha256' 'Expected a lowercase SHA-256 digest'};if([string]$disposition.decision-eq'verified'-and(-not$evidence.PSObject.Properties['reference']-or[string]::IsNullOrWhiteSpace([string]$evidence.reference))-and(-not$evidence.PSObject.Properties['sha256']-or[string]$evidence.sha256-notmatch'^[0-9a-f]{64}$')){Add-ContractIssue $issues 'invalid-rule-disposition' ([string]$disposition.ruleId) 'Verified evidence requires reference or sha256'};if([string]$disposition.decision-in@('accepted','not-applicable')-and(-not$evidence.PSObject.Properties['reason']-or[string]::IsNullOrWhiteSpace([string]$evidence.reason))){Add-ContractIssue $issues 'invalid-rule-disposition' ([string]$disposition.ruleId) 'Accepted or not-applicable evidence requires reason'}}}
    }
    if($notation){
        Test-AllowedContractFields $notation @('schemaVersion','id','family','subtype','provenance','nodeTypes','edgeTypes','rules') $issues 'notation-profile'
        $notationUsable=Test-ContractProperties $notation @('schemaVersion','id','family','provenance','nodeTypes','edgeTypes') $issues 'invalid-notation-contract' 'notation-profile'
        if($notation.PSObject.Properties['provenance']){Test-AllowedContractFields $notation.provenance @('standard','version','source','verifiedAt','mcpDiscovery') $issues 'provenance';$notationUsable=(Test-ContractProperties $notation.provenance @('standard','source') $issues 'invalid-notation-contract' 'provenance')-and$notationUsable}
        if($notation.PSObject.Properties['schemaVersion']-and[string]$notation.schemaVersion-ne'1'){Add-ContractIssue $issues 'notation-schema-version' '' "Expected 1, found $($notation.schemaVersion)";$notationUsable=$false}
        if($notation.PSObject.Properties['id']-and[string]$notation.id-notmatch'^[a-z0-9][a-z0-9-]*$'){Add-ContractIssue $issues 'invalid-notation-contract' 'id' 'Profile id is invalid';$notationUsable=$false}
        if($notation.PSObject.Properties['provenance']){foreach($field in @('standard','source')){if($notation.provenance.PSObject.Properties[$field]-and[string]::IsNullOrWhiteSpace([string]$notation.provenance.$field)){Add-ContractIssue $issues 'invalid-notation-contract' "provenance.$field" 'Value must be nonempty';$notationUsable=$false}}}
        if($notation.PSObject.Properties['nodeTypes']){foreach($entry in @($notation.nodeTypes.PSObject.Properties)){Test-AllowedContractFields $entry.Value @('styleMatchers','shapeClass','container') $issues "nodeTypes.$($entry.Name)";$notationUsable=(Test-ContractProperties $entry.Value @('shapeClass','styleMatchers') $issues 'invalid-notation-node-type' $entry.Name)-and$notationUsable;if($entry.Value.PSObject.Properties['styleMatchers']){$matchers=@($entry.Value.styleMatchers);if($matchers.Count-eq0){Add-ContractIssue $issues 'invalid-notation-node-type' $entry.Name 'styleMatchers must contain at least one entry';$notationUsable=$false};foreach($matcher in $matchers){Test-AllowedContractFields $matcher @('allOf','noneOf') $issues "nodeTypes.$($entry.Name).styleMatchers";if(-not$matcher.PSObject.Properties['allOf']-or@($matcher.allOf).Count-eq0){Add-ContractIssue $issues 'invalid-notation-node-type' $entry.Name 'Matcher allOf must contain at least one token';$notationUsable=$false}}}}}
        if($notation.PSObject.Properties['edgeTypes']){foreach($entry in @($notation.edgeTypes.PSObject.Properties)){Test-AllowedContractFields $entry.Value @('direction','style','allowedSourceTypes','allowedTargetTypes') $issues "edgeTypes.$($entry.Name)";$notationUsable=(Test-ContractProperties $entry.Value @('direction','style') $issues 'invalid-notation-edge-type' $entry.Name)-and$notationUsable;Test-EnumContractField $entry.Value 'direction' @('directed','undirected','bidirectional') $issues "edgeTypes.$($entry.Name)"}}
        if($notation.PSObject.Properties['rules']){foreach($rule in @($notation.rules)){Test-AllowedContractFields $rule @('id','severity','description') $issues 'rules';foreach($field in @('id','severity','description')){if(-not$rule.PSObject.Properties[$field]){Add-ContractIssue $issues 'invalid-notation-rule' ([string]$rule.id) "$field is required";$notationUsable=$false}};Test-EnumContractField $rule 'severity' @('ERROR','WARNING','INFO') $issues 'rules'}}
    }
    if($manifestUsable){
        if([int]$manifest.schemaVersion-ne1){Add-ContractIssue $issues 'semantic-schema-version' '' "Expected 1, found $($manifest.schemaVersion)"}
        if([string]$manifest.diagram.family-ne$Family){Add-ContractIssue $issues 'semantic-family' '' "Expected $Family, found $($manifest.diagram.family)"}
        $model=$source.SelectSingleNode('/mxGraphModel');if($manifest.diagram.PSObject.Properties['page']){if([math]::Abs((ConvertTo-DrawioNumber $model.pageWidth)-[double]$manifest.diagram.page.width)-gt0.05-or[math]::Abs((ConvertTo-DrawioNumber $model.pageHeight)-[double]$manifest.diagram.page.height)-gt0.05){Add-ContractIssue $issues 'semantic-page' '' 'Canonical page does not match the semantic manifest'}}
        $manifestNodeIds=@{};foreach($node in @($manifest.nodes)){
            $id=[string]$node.id;$manifestNodeIds[$id]=$true
            if(-not$cells.ContainsKey($id)-or[string]$cells[$id].vertex-ne'1'){Add-ContractIssue $issues 'semantic-node-missing' $id 'Manifest node is not a canonical vertex';continue}
            $cell=$cells[$id];$actual=ConvertTo-DrawioSemanticLabel ([string]$cell.value);$expected=ConvertTo-DrawioSemanticLabel ([string]$node.label);if($actual-ne$expected){Add-ContractIssue $issues 'semantic-node-label' $id "Expected '$expected', found '$actual'"}
            if($node.PSObject.Properties['parent']-and[string]$cell.parent-ne[string]$node.parent){Add-ContractIssue $issues 'semantic-node-parent' $id "Expected $($node.parent), found $($cell.parent)"}
            if($node.PSObject.Properties['lane']-and[string]$cell.parent-ne[string]$node.lane){Add-ContractIssue $issues 'semantic-node-lane' $id "Expected $($node.lane), found $($cell.parent)"}
        }
        foreach($cell in $source.SelectNodes('//mxCell[@vertex="1"]')){if([string]$cell.id-notin@('0','1','title')-and-not$manifestNodeIds.ContainsKey([string]$cell.id)){Add-ContractIssue $issues 'semantic-node-unmapped' ([string]$cell.id) 'Canonical vertex is absent from the semantic manifest' 'WARNING'}}
        $manifestEdgeIds=@{};foreach($edge in @($manifest.edges)){
            $id=[string]$edge.id;$manifestEdgeIds[$id]=$true
            if(-not$cells.ContainsKey($id)-or[string]$cells[$id].edge-ne'1'){Add-ContractIssue $issues 'semantic-edge-missing' $id 'Manifest edge is not a canonical edge';continue}
            $cell=$cells[$id];if([string]$cell.source-ne[string]$edge.source-or[string]$cell.target-ne[string]$edge.target){Add-ContractIssue $issues 'semantic-edge-endpoints' $id "Expected $($edge.source) -> $($edge.target), found $($cell.source) -> $($cell.target)"}
            $actual=ConvertTo-DrawioSemanticLabel ([string]$cell.value);$expected=ConvertTo-DrawioSemanticLabel ([string]$edge.label);if($actual-ne$expected){Add-ContractIssue $issues 'semantic-edge-label' $id "Expected '$expected', found '$actual'"}
            $style=Get-DrawioStyleMap ([string]$cell.style);$startArrow=if($style.ContainsKey('startArrow')){[string]$style.startArrow}else{'none'};$endArrow=if($style.ContainsKey('endArrow')){[string]$style.endArrow}else{'none'}
            $hasSourceDirection=Test-DirectionalMarker $startArrow;$hasTargetDirection=Test-DirectionalMarker $endArrow
            if($edge.direction-eq'directed'-and-not$hasTargetDirection){Add-ContractIssue $issues 'semantic-edge-direction' $id 'Directed edge has no target arrow'}
            if($edge.direction-eq'undirected'-and($hasSourceDirection-or$hasTargetDirection)){Add-ContractIssue $issues 'semantic-edge-direction' $id 'Undirected edge contains a directional arrow'}
            if($edge.direction-eq'bidirectional'-and(-not$hasSourceDirection-or-not$hasTargetDirection)){Add-ContractIssue $issues 'semantic-edge-direction' $id 'Bidirectional edge requires both directional arrows'}
            foreach($side in $(if($edge.PSObject.Properties['sourceSides']){@($edge.sourceSides)}else{@()})){if([string]$side-notin@(Get-AnchorSides $style 'exit')){Add-ContractIssue $issues 'semantic-source-side' $id "Required side $side is not declared"}}
            foreach($side in $(if($edge.PSObject.Properties['targetSides']){@($edge.targetSides)}else{@()})){if([string]$side-notin@(Get-AnchorSides $style 'entry')){Add-ContractIssue $issues 'semantic-target-side' $id "Required side $side is not declared"}}
        }
        foreach($cell in $source.SelectNodes('//mxCell[@edge="1"]')){if(-not$manifestEdgeIds.ContainsKey([string]$cell.id)){Add-ContractIssue $issues 'semantic-edge-unmapped' ([string]$cell.id) 'Canonical edge is absent from the semantic manifest' 'WARNING'}}
    }
    if($notationUsable){
        if([int]$notation.schemaVersion-ne1){Add-ContractIssue $issues 'notation-schema-version' '' "Expected 1, found $($notation.schemaVersion)"}
        if([string]$notation.family-ne$Family){Add-ContractIssue $issues 'notation-family' '' "Expected $Family, found $($notation.family)"}
        if($manifestUsable){
            $nodeSemantic=@{}
            foreach($node in @($manifest.nodes)){
                $semanticType=[string]$node.semanticType
                $nodeSemantic[[string]$node.id]=$semanticType
                if(-not$cells.ContainsKey([string]$node.id)){continue}
                if($semanticType-in@('annotation','scaffold','provenance','standard','legend','viewpoint','contract')){continue}
                $definition=$notation.nodeTypes.PSObject.Properties[$semanticType]
                if(-not$definition){Add-ContractIssue $issues 'notation-node-type' ([string]$node.id) "Unknown semantic type: $semanticType";continue}
                $unresolved=@()
                foreach($matcher in @($definition.Value.styleMatchers)){
                    $items=if($matcher-is[string]){@([string]$matcher)}else{@($matcher.allOf)+$(if($matcher.PSObject.Properties['noneOf']){@($matcher.noneOf)}else{@()})}
                    $unresolved+=@($items|Where-Object{[string]$_-match'^(?:LIVE_SEARCH_REQUIRED|AUTHORITATIVE_MAPPING_REQUIRED):'})
                }
                if($unresolved.Count-gt0){Add-ContractIssue $issues 'notation-mapping-unresolved' ([string]$node.id) ($unresolved-join',') 'WARNING' 'resolve-notation-mapping';continue}
                $tokens=Get-StyleTokens ([string]$cells[[string]$node.id].style)
                if(-not(Test-StyleMatchers $tokens @($definition.Value.styleMatchers))){Add-ContractIssue $issues 'notation-node-style' ([string]$node.id) "Style does not match semantic type $semanticType"}
            }
            foreach($edge in @($manifest.edges)){
                if(-not$cells.ContainsKey([string]$edge.id)){continue};$relation=if($edge.PSObject.Properties['relationType']){[string]$edge.relationType}else{''};if(-not$relation){if(@($notation.edgeTypes.PSObject.Properties).Count-eq1){$relation=[string]@($notation.edgeTypes.PSObject.Properties)[0].Name}else{Add-ContractIssue $issues 'notation-edge-type' ([string]$edge.id) 'relationType is required when the profile has multiple edge types';continue}}
                $definition=$notation.edgeTypes.PSObject.Properties[$relation];if(-not$definition){Add-ContractIssue $issues 'notation-edge-type' ([string]$edge.id) "Unknown relation type: $relation";continue};$style=Get-DrawioStyleMap ([string]$cells[[string]$edge.id].style)
                foreach($expected in @($definition.Value.style.PSObject.Properties)){if($expected.Name-match'REQUIRED'-or[string]$expected.Value-match'REQUIRED'){Add-ContractIssue $issues 'notation-mapping-unresolved' ([string]$edge.id) "$($expected.Name)=$($expected.Value)" 'WARNING' 'resolve-notation-mapping';continue};$actual=if($style.ContainsKey($expected.Name)){[string]$style[$expected.Name]}else{''};if($actual-ne[string]$expected.Value){Add-ContractIssue $issues 'notation-edge-style' ([string]$edge.id) "Expected $($expected.Name)=$($expected.Value), found $actual"}}
                if($definition.Value.PSObject.Properties['allowedSourceTypes']-and$nodeSemantic[[string]$edge.source]-notin@($definition.Value.allowedSourceTypes)){Add-ContractIssue $issues 'notation-source-type' ([string]$edge.id) "$($nodeSemantic[[string]$edge.source]) is not allowed"}
                if($definition.Value.PSObject.Properties['allowedTargetTypes']-and$nodeSemantic[[string]$edge.target]-notin@($definition.Value.allowedTargetTypes)){Add-ContractIssue $issues 'notation-target-type' ([string]$edge.id) "$($nodeSemantic[[string]$edge.target]) is not allowed"}
            }
        }
    }
    $manualRules=@($(if($notationUsable-and$notation.PSObject.Properties['rules']){@($notation.rules)}else{@()}))
    $ruleDispositions=@($(if($manifestUsable-and$manifest.PSObject.Properties['ruleDispositions']){@($manifest.ruleDispositions)}else{@()}))
    $unresolvedRules=[System.Collections.Generic.List[object]]::new()
    foreach($rule in $manualRules){
        $ruleId=if($rule.PSObject.Properties['id']){[string]$rule.id}else{[string]$rule}
        $ruleSeverity=if($rule.PSObject.Properties['severity']){[string]$rule.severity}else{'ERROR'}
        $matches=@($ruleDispositions|Where-Object{$_.PSObject.Properties['ruleId']-and[string]$_.ruleId-eq$ruleId})
        if($matches.Count-ne1-or-not(Test-RuleDisposition $matches[0] $ruleSeverity)){$unresolvedRules.Add([pscustomobject]@{RuleId=$ruleId;Severity=$ruleSeverity;Reason='Disposition is missing, ambiguous, or lacks evidence permitted for this rule severity'})}
    }
    $unique=@($issues|Sort-Object Severity,Type,Element,Detail -Unique)
    $errorCount=@($unique|Where-Object{$_.Severity-eq'ERROR'}).Count
    $uncertaintyIssues=@($unique|Where-Object{$_.Type-in@('notation-mapping-unresolved','unresolved-semantic-context')})
    $overallStatus=if($errorCount-gt0){'FAIL'}elseif($uncertaintyIssues.Count-gt0-or$unresolvedRules.Count-gt0){'UNKNOWN'}else{'PASS'}
    $reasons=[System.Collections.Generic.List[object]]::new();foreach($issue in $uncertaintyIssues){$reasons.Add([pscustomobject]@{Type=$issue.Type;Element=$issue.Element;Detail=$issue.Detail})};foreach($rule in $unresolvedRules){$reasons.Add([pscustomobject]@{Type='manual-rule-unresolved';Element=$rule.RuleId;Detail=$rule.Reason})};if($overallStatus-eq'FAIL'){foreach($issue in @($unique|Where-Object{$_.Severity-eq'ERROR'})){$reasons.Add([pscustomobject]@{Type=$issue.Type;Element=$issue.Element;Detail=$issue.Detail})}}
    [pscustomobject]@{Source=$SourcePath;Family=$Family;SemanticManifest=$SemanticManifestPath;NotationProfile=$NotationProfilePath;OverallStatus=$overallStatus;Reasons=@($reasons);ManualRuleCount=$manualRules.Count;UnresolvedManualRuleCount=$unresolvedRules.Count;UnresolvedManualRules=@($unresolvedRules);ErrorCount=$errorCount;WarningCount=@($unique|Where-Object{$_.Severity-eq'WARNING'}).Count;IssueCount=$unique.Count;Issues=$unique}
}

Export-ModuleMember -Function ConvertTo-DrawioSemanticLabel, Test-StyleMatcher, Test-StyleMatchers, Invoke-DrawioContractAudit
