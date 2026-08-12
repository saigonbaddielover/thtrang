param(
    [Parameter(Mandatory = $true)]
    [string]$SkillPath
)

$ErrorActionPreference = 'Stop'
$issues = [System.Collections.Generic.List[string]]::new()

function Add-Issue {
    param([string]$Message)
    $issues.Add($Message)
}

$skillFile = Join-Path $SkillPath 'SKILL.md'
$metadataFile = Join-Path $SkillPath 'agents\openai.yaml'
if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { Add-Issue 'SKILL.md not found' }
if (-not (Test-Path -LiteralPath $metadataFile -PathType Leaf)) { Add-Issue 'agents/openai.yaml not found' }

$requiredPaths = @(
    'assets\quality-profile.json',
    'references\validation-contract.md',
    'references\audit-recipes.md',
    'references\failure-catalog.md',
    'references\visual-quality.md',
    'references\construction-gates.md',
    'references\layout-routing.md',
    'references\lifecycle.md',
    'schemas\diagram-contract.schema.json',
    'schemas\notation-profile.schema.json',
    'schemas\quality-profile.schema.json',
    'schemas\artifact-manifest.schema.json',
    'schemas\warning-dispositions.schema.json',
    'schemas\visual-inspection.schema.json',
    'schemas\crop-report.schema.json',
    'scripts\preflight_drawio.ps1',
    'scripts\sync_drawio.ps1',
    'scripts\export_drawio.ps1',
    'scripts\build_drawio_corpus.ps1',
    'scripts\inspect_drawio_cells.ps1',
    'scripts\update_drawio_cells.ps1',
    'scripts\validate_drawio.ps1',
    'scripts\audit_drawio_quality_profile.ps1',
    'scripts\audit_drawio_artifacts.ps1',
    'scripts\audit_drawio_connectors.ps1',
    'scripts\audit_drawio_labels.ps1',
    'scripts\audit_drawio_archive_labels.ps1',
    'scripts\export_drawio_crops.ps1',
    'scripts\sync_personal_skill.ps1',
    'scripts\publish_personal_skill.ps1',
    'scripts\test_drawio_builder.ps1',
    'scripts\test_family_fixtures.ps1',
    'scripts\test_profile_fixtures.ps1',
    'scripts\test_artifact_binding.ps1',
    'scripts\test_visual_evidence.ps1',
    'scripts\test_approval_workflow.ps1',
    'scripts\test_export_transaction.ps1',
    'scripts\compare_drawio_reports.ps1',
    'scripts\test_repair_loop.ps1',
    'scripts\test_cell_tools.ps1',
    'scripts\lib\Drawio.Contract.psm1',
    'scripts\lib\Drawio.Core.psm1',
    'scripts\lib\Drawio.Evidence.psm1',
    'scripts\lib\Drawio.Shapes.psm1',
    'scripts\lib\Svg.Geometry.psm1',
    'scripts\lib\Svg.Ink.psm1',
    'scripts\fixtures\profiles\index.json',
    'scripts\fixtures\families\coverage.json'
    'scripts\fixtures\approval\approved-process.xml'
    'scripts\fixtures\approval\approved-process.manifest.json'
)
foreach ($requiredPath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $SkillPath $requiredPath) -PathType Leaf)) { Add-Issue "Required file not found: $requiredPath" }
}

if ($issues.Count -eq 0) {
    $content = Get-Content -LiteralPath $skillFile -Raw -Encoding UTF8
    $frontmatterMatch = [regex]::Match($content, '^---\r?\n(?<body>.*?)\r?\n---', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $frontmatterMatch.Success) {
        Add-Issue 'Invalid SKILL.md frontmatter format'
    }
    else {
        $properties = @{}
        foreach ($line in $frontmatterMatch.Groups['body'].Value -split '\r?\n') {
            if ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') { $properties[$Matches[1]] = $Matches[2].Trim() }
            elseif ($line.Trim()) { Add-Issue "Invalid frontmatter line: $line" }
        }
        foreach ($required in @('name', 'description')) {
            if (-not $properties.ContainsKey($required) -or -not $properties[$required]) { Add-Issue "Missing '$required' in frontmatter" }
        }
        $unexpected = @($properties.Keys | Where-Object { $_ -notin @('name', 'description') })
        if ($unexpected.Count -gt 0) { Add-Issue "Unexpected frontmatter keys: $($unexpected -join ', ')" }
        $name = $properties['name']
        if ($name -and ($name -notmatch '^[a-z0-9-]+$' -or $name.StartsWith('-') -or $name.EndsWith('-') -or $name.Contains('--') -or $name.Length -gt 64)) {
            Add-Issue "Invalid skill name: $name"
        }
        $description = $properties['description']
        if ($description -and ($description.Contains('<') -or $description.Contains('>') -or $description.Length -gt 1024)) {
            Add-Issue 'Invalid skill description'
        }
    }
    if ($content -match '\bTODO\b') { Add-Issue 'SKILL.md contains TODO' }
    if (($content -split '\r?\n').Count -ge 500) { Add-Issue 'SKILL.md must remain under 500 lines' }
    foreach ($match in [regex]::Matches($content, '\[[^\]]+\]\((?<path>[^)]+)\)')) {
        $target = Join-Path $SkillPath $match.Groups['path'].Value
        if (-not (Test-Path -LiteralPath $target)) { Add-Issue "Broken SKILL.md reference: $($match.Groups['path'].Value)" }
    }

    $metadata = Get-Content -LiteralPath $metadataFile -Raw -Encoding UTF8
    if ($metadata -notmatch '(?m)^\s*display_name:\s*"Draw\.io Builder"\s*$') { Add-Issue 'Invalid display_name' }
    $shortMatch = [regex]::Match($metadata, '(?m)^\s*short_description:\s*"(?<value>[^"]+)"\s*$')
    if (-not $shortMatch.Success -or $shortMatch.Groups['value'].Value.Length -lt 25 -or $shortMatch.Groups['value'].Value.Length -gt 64) { Add-Issue 'Invalid short_description' }
    if ($metadata -notmatch '\$drawio-builder') { Add-Issue 'default_prompt must mention $drawio-builder' }
    if ($metadata -notmatch '(?ms)type:\s*"mcp".*?value:\s*"drawio"') { Add-Issue 'Draw.io MCP dependency is missing' }
}

foreach ($jsonFile in @(Get-ChildItem -LiteralPath $SkillPath -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
    try { [void](Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { Add-Issue "Invalid JSON: $($jsonFile.FullName.Substring($SkillPath.Length + 1))" }
}

foreach ($xmlFile in @(Get-ChildItem -LiteralPath (Join-Path $SkillPath 'assets') -Recurse -Filter '*.xml' -File -ErrorAction SilentlyContinue; Get-ChildItem -LiteralPath (Join-Path $SkillPath 'scripts\fixtures') -Recurse -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
    try { [xml](Get-Content -LiteralPath $xmlFile.FullName -Raw -Encoding UTF8) | Out-Null }
    catch { Add-Issue "Invalid XML: $($xmlFile.FullName.Substring($SkillPath.Length + 1))" }
}

$familyNames = @('process','data-flow','bpmn','uml','erd','architecture','cloud','network','engineering','electrical','pid','floorplan','wireframe')
foreach ($familyName in $familyNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $SkillPath "references\families\$familyName.md") -PathType Leaf)) { Add-Issue "Family reference not found: $familyName" }
}

$profileFiles = @(Get-ChildItem -LiteralPath (Join-Path $SkillPath 'profiles') -Filter '*.json' -File -ErrorAction SilentlyContinue)
foreach ($familyName in $familyNames) {
    $matchingProfile = @($profileFiles | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).family -eq $familyName })
    if ($matchingProfile.Count -eq 0) { Add-Issue "Notation profile not found: $familyName" }
}

if (@(Get-ChildItem -LiteralPath (Join-Path $SkillPath 'assets\templates') -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count -eq 0) { Add-Issue 'No family templates found' }

$unexpectedDocs = @('README.md', 'INSTALLATION_GUIDE.md', 'QUICK_REFERENCE.md', 'CHANGELOG.md') | Where-Object { Test-Path -LiteralPath (Join-Path $SkillPath $_) }
foreach ($file in $unexpectedDocs) { Add-Issue "Extraneous file: $file" }

$result = [pscustomobject]@{
    Skill = $SkillPath
    IssueCount = @($issues | Sort-Object -Unique).Count
    Issues = @($issues | Sort-Object -Unique)
}
$result | ConvertTo-Json -Depth 4
if ($result.IssueCount -gt 0) { exit 1 }
