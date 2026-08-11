param(
    [string]$SkillPath = (Split-Path -Parent $PSScriptRoot),
    [string]$DrawioExecutable,
    [string]$CorpusRoot,
    [string]$OfficialValidatorPath,
    [string]$PythonExecutable,
    [switch]$SkipSyncTests
)

$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$tests = [System.Collections.Generic.List[object]]::new()
$skipped = [System.Collections.Generic.List[object]]::new()

function Add-TestResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )
    $tests.Add([pscustomobject]@{ Name=$Name; Passed=$Passed; Detail=$Detail })
    if (-not $Passed) { throw "$Name failed: $Detail" }
}

function Add-SkippedResult {
    param(
        [string]$Name,
        [string]$Reason
    )
    $skipped.Add([pscustomobject]@{ Name=$Name; Reason=$Reason })
}

function Invoke-Tool {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine -NoProfile -File $ScriptPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    [pscustomobject]@{ ExitCode=$exitCode; Output=($output -join "`n") }
}

function Convert-ToCompressedPayload {
    param([string]$Xml)
    $encoded = [uri]::EscapeDataString($Xml)
    $output = [System.IO.MemoryStream]::new()
    $deflate = [System.IO.Compression.DeflateStream]::new($output, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($encoded)
        $deflate.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $deflate.Dispose()
    }
    try { [Convert]::ToBase64String($output.ToArray()) } finally { $output.Dispose() }
}

function Get-ModelSignature {
    param([string]$Path)
    [xml]$model = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $model.OuterXml
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-PythonCommand {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = @(& $Path --version 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prior
    }
    $exitCode -eq 0
}

function Resolve-PythonCommand {
    param(
        [string]$ExplicitPath,
        [string]$AnchorPath
    )
    if ($ExplicitPath) {
        if (-not (Test-PythonCommand $ExplicitPath)) { throw "Python executable is invalid: $ExplicitPath" }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    $cursor = [System.IO.Path]::GetFullPath($AnchorPath)
    if (Test-Path -LiteralPath $cursor -PathType Leaf) { $cursor = Split-Path -Parent $cursor }
    while ($cursor) {
        foreach ($relative in @('.venv\Scripts\python.exe', '.venv\bin\python', '.venv\bin\python3')) {
            $candidate = Join-Path $cursor $relative
            if (Test-PythonCommand $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    foreach ($name in @('python', 'python3')) {
        $candidate = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $candidate) { continue }
        if (Test-PythonCommand $candidate.Source) { return $candidate.Source }
    }
    $null
}

function Invoke-ExternalTool {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prior
    }
    [pscustomobject]@{ ExitCode=$exitCode; Output=($output -join "`n") }
}

function Get-TreeHashes {
    param(
        [string]$Root,
        [string[]]$RelativeDirectories
    )
    $hashes = @{}
    foreach ($relativeDirectory in $RelativeDirectories) {
        $directory = Join-Path $Root $relativeDirectory
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $directory -File -Recurse) {
            $relative = $file.FullName.Substring((Resolve-Path -LiteralPath $Root).Path.TrimEnd('\').Length + 1).Replace('\', '/')
            $hashes[$relative] = Get-Sha256 $file.FullName
        }
    }
    $hashes
}

function Compare-HashMaps {
    param(
        [hashtable]$Left,
        [hashtable]$Right
    )
    if ($Left.Count -ne $Right.Count) { return $false }
    foreach ($key in $Left.Keys) {
        if (-not $Right.ContainsKey($key) -or $Left[$key] -ne $Right[$key]) { return $false }
    }
    $true
}

$fixtures = Join-Path $PSScriptRoot 'fixtures'
$scratchBase = Join-Path (Get-Location).Path '.tmp'
$scratch = Join-Path $scratchBase ('drawio-builder-test-' + [guid]::NewGuid().ToString('N'))
if (-not (Test-Path -LiteralPath $scratchBase)) { New-Item -ItemType Directory -Path $scratchBase -Force | Out-Null }
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    $skillValidation = Invoke-Tool (Join-Path $PSScriptRoot 'validate_skill.ps1') @('-SkillPath', $SkillPath)
    Add-TestResult 'skill-contract' ($skillValidation.ExitCode -eq 0) $skillValidation.Output

    $schemaFiles = @(Get-ChildItem -LiteralPath (Join-Path $SkillPath 'schemas') -Filter '*.schema.json' -File)
    $schemaParseFailures = [System.Collections.Generic.List[string]]::new()
    foreach ($schemaFile in $schemaFiles) {
        try {
            $schema = Get-Content -LiteralPath $schemaFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$schema.'$schema' -ne 'https://json-schema.org/draft/2020-12/schema' -or -not [string]$schema.'$id') { $schemaParseFailures.Add($schemaFile.Name) }
        }
        catch { $schemaParseFailures.Add($schemaFile.Name) }
    }
    Add-TestResult 'schema-documents-parse' ($schemaFiles.Count -ge 4 -and $schemaParseFailures.Count -eq 0) (($schemaParseFailures | Sort-Object -Unique) -join ', ')

    $infrastructureFixtures = Join-Path $fixtures 'infrastructure'
    $toolchainPath = Join-Path $infrastructureFixtures 'toolchain.json'
    $toolchain = Get-Content -LiteralPath $toolchainPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $toolchainValid = [int]$toolchain.schemaVersion -eq 1 -and [string]$toolchain.drawio.version -and [string]$toolchain.drawio.downloadUrl -and [string]$toolchain.drawio.sha256 -match '^[a-f0-9]{64}$' -and [string]$toolchain.officialSkillValidator.commit -match '^[a-f0-9]{40}$' -and [string]$toolchain.officialSkillValidator.sha256 -match '^[a-f0-9]{64}$'
    Add-TestResult 'pinned-toolchain-contract' $toolchainValid ($toolchain | ConvertTo-Json -Compress -Depth 5)

    $corpusExpectationPath = Join-Path $SkillPath 'tests\corpus-expectations.json'
    $corpusExpectationData = Get-Content -LiteralPath $corpusExpectationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $findingKeys = @($corpusExpectationData.findings | ForEach-Object { "$($_.diagram)|$($_.gate)|$($_.type)|$($_.element)" })
    $expectedFindingTotal = @($corpusExpectationData.findings | ForEach-Object { [int]$_.count } | Measure-Object -Sum).Sum
    $allowedDispositions = @('expected-issue', 'expected-false-positive', 'visual-only')
    $invalidDispositions = @($corpusExpectationData.findings | Where-Object { $_.disposition -notin $allowedDispositions })
    $invalidCounts = @($corpusExpectationData.findings | Where-Object { [int]$_.count -lt 1 })
    $expectationContractValid = [int]$corpusExpectationData.schemaVersion -eq 1 -and @($corpusExpectationData.findings).Count -gt 0 -and @($corpusExpectationData.findings | Where-Object disposition -eq 'expected-issue').Count -gt 0 -and @($corpusExpectationData.visualOnly).Count -gt 0 -and @($findingKeys | Sort-Object -Unique).Count -eq $findingKeys.Count -and $invalidDispositions.Count -eq 0 -and $invalidCounts.Count -eq 0 -and [int]$corpusExpectationData.findingCount -eq [int]$expectedFindingTotal
    Add-TestResult 'corpus-expectations-contract' $expectationContractValid ($corpusExpectationData | ConvertTo-Json -Compress -Depth 5)

    $familyFixtureArguments = @('-SkillPath',$SkillPath,'-ScratchDirectory',(Join-Path $scratch 'family-fixtures'))
    if ($DrawioExecutable) { $familyFixtureArguments += @('-DrawioExecutable',$DrawioExecutable) }
    $familyFixtureSuite = Invoke-Tool (Join-Path $PSScriptRoot 'test_family_fixtures.ps1') $familyFixtureArguments
    Add-TestResult 'family-fixture-suite' ($familyFixtureSuite.ExitCode -eq 0) $familyFixtureSuite.Output
    $profileFixtureArguments = @('-SkillPath', $SkillPath, '-ScratchDirectory', $scratch)
    if ($DrawioExecutable) { $profileFixtureArguments += @('-DrawioExecutable', $DrawioExecutable) }
    $profileFixtureSuite = Invoke-Tool (Join-Path $PSScriptRoot 'test_profile_fixtures.ps1') $profileFixtureArguments
    Add-TestResult 'profile-fixture-suite' ($profileFixtureSuite.ExitCode -eq 0) $profileFixtureSuite.Output
    $transactionSuite = Invoke-Tool (Join-Path $PSScriptRoot 'test_export_transaction.ps1') @('-SkillPath', $SkillPath)
    Add-TestResult 'export-transaction-contract' ($transactionSuite.ExitCode -eq 0) $transactionSuite.Output
    $artifactScratchRoot = Join-Path $SkillPath '.tmp'
    $artifactScratchExisted = Test-Path -LiteralPath $artifactScratchRoot
    $artifactBindingSuite = Invoke-Tool (Join-Path $PSScriptRoot 'test_artifact_binding.ps1') @('-SkillPath',$SkillPath)
    if (-not $artifactScratchExisted -and (Test-Path -LiteralPath $artifactScratchRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $artifactScratchRoot -Force).Count -eq 0) { [System.IO.Directory]::Delete($artifactScratchRoot) }
    Add-TestResult 'artifact-binding-contract' ($artifactBindingSuite.ExitCode -eq 0) $artifactBindingSuite.Output

    $python = Resolve-PythonCommand $PythonExecutable $SkillPath
    if ($python) {
        $schemaValidation = Invoke-ExternalTool $python @((Join-Path $SkillPath 'tests\validate_json_schemas.py'), $SkillPath)
        Add-TestResult 'json-schema-fixtures' ($schemaValidation.ExitCode -eq 0) $schemaValidation.Output
        if ($OfficialValidatorPath) {
            $officialValidation = Invoke-ExternalTool $python @($OfficialValidatorPath, $SkillPath)
            Add-TestResult 'official-skill-validation' ($officialValidation.ExitCode -eq 0) $officialValidation.Output
        }
        else {
            Add-SkippedResult 'official-skill-validation' 'OfficialValidatorPath was not provided'
        }
    }
    else {
        Add-SkippedResult 'json-schema-fixtures' 'Python is unavailable'
        Add-SkippedResult 'official-skill-validation' 'Python is unavailable'
    }

    $validPath = Join-Path $fixtures 'valid-process.xml'
    $valid = Invoke-Tool (Join-Path $PSScriptRoot 'preflight_drawio.ps1') @('-SourcePath', $validPath)
    Add-TestResult 'valid-preflight' ($valid.ExitCode -eq 0) $valid.Output

    $duplicate = Invoke-Tool (Join-Path $PSScriptRoot 'preflight_drawio.ps1') @('-SourcePath', (Join-Path $fixtures 'invalid-duplicate-id.xml'))
    $duplicateData = $duplicate.Output | ConvertFrom-Json
    Add-TestResult 'duplicate-id-rejected' ($duplicate.ExitCode -eq 1 -and 'duplicate-id' -in @($duplicateData.Issues.Type)) $duplicate.Output

    $dangling = Invoke-Tool (Join-Path $PSScriptRoot 'preflight_drawio.ps1') @('-SourcePath', (Join-Path $fixtures 'invalid-dangling-edge.xml'))
    $danglingData = $dangling.Output | ConvertFrom-Json
    Add-TestResult 'dangling-edge-rejected' ($dangling.ExitCode -eq 1 -and 'invalid-edge-target' -in @($danglingData.Issues.Type)) $dangling.Output

    $invalidVisualPath = Join-Path $fixtures 'invalid-visual-process.xml'
    $invalidVisualPreflight = Invoke-Tool (Join-Path $PSScriptRoot 'preflight_drawio.ps1') @('-SourcePath', $invalidVisualPath)
    Add-TestResult 'visual-failure-fixture-preflight' ($invalidVisualPreflight.ExitCode -eq 0) $invalidVisualPreflight.Output

    $singleDrawio = Join-Path $scratch 'single.drawio'
    $singleImport = Join-Path $scratch 'single-import.xml'
    $toSingle = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','ToDrawio','-CanonicalPath',$validPath,'-DrawioPath',$singleDrawio,'-PageId','single-page','-PageName','Single Page')
    Add-TestResult 'single-page-export' ($toSingle.ExitCode -eq 0 -and (Test-Path -LiteralPath $singleDrawio)) $toSingle.Output
    $fromSingle = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','FromDrawio','-CanonicalPath',$singleImport,'-DrawioPath',$singleDrawio)
    Add-TestResult 'single-page-import' ($fromSingle.ExitCode -eq 0 -and (Get-ModelSignature $singleImport) -eq (Get-ModelSignature $validPath)) $fromSingle.Output

    $noWriteRenderer = Join-Path $scratch 'no-write-renderer.cmd'
    Write-Utf8File $noWriteRenderer "@exit /b 0`r`n"
    $staleSvg = Join-Path $scratch 'stale.svg'
    Write-Utf8File $staleSvg '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>'
    $staleSvgHash = Get-Sha256 $staleSvg
    $noWriteExport = Invoke-Tool (Join-Path $PSScriptRoot 'export_drawio.ps1') @('-CanonicalPath',$validPath,'-DrawioPath',$singleDrawio,'-DrawioExecutable',$noWriteRenderer,'-SvgPath',$staleSvg)
    $staleTemporaries = @(Get-ChildItem -LiteralPath $scratch -Filter '.stale.*.svg' -File -ErrorAction SilentlyContinue)
    Add-TestResult 'stale-output-rejected' ($noWriteExport.ExitCode -ne 0 -and $noWriteExport.Output -match 'did not produce a fresh file' -and (Get-Sha256 $staleSvg) -eq $staleSvgHash -and $staleTemporaries.Count -eq 0) $noWriteExport.Output

    $wrongPdfSource = Join-Path $scratch 'wrong-orientation-source.pdf'
    Write-Utf8File $wrongPdfSource "%PDF-1.4`n1 0 obj << /Type /Page /MediaBox [ 0 0 841.92 594.96 ] >> endobj`n%%EOF`n"
    $wrongPdfRenderer = Join-Path $scratch 'wrong-pdf-renderer.cmd'
    $wrongPdfRendererText = "@echo off`r`nset `"capture=`"`r`nfor %%A in (%*) do (`r`n  if defined capture (`r`n    copy /y `"$wrongPdfSource`" `"%%~A`" >nul`r`n    exit /b 0`r`n  )`r`n  if `"%%~A`"==`"-o`" set `"capture=1`"`r`n)`r`nexit /b 3`r`n"
    Write-Utf8File $wrongPdfRenderer $wrongPdfRendererText
    $preservedPdf = Join-Path $scratch 'preserved.pdf'
    Write-Utf8File $preservedPdf 'preserve-destination'
    $preservedPdfHash = Get-Sha256 $preservedPdf
    $wrongPdfExport = Invoke-Tool (Join-Path $PSScriptRoot 'export_drawio.ps1') @('-CanonicalPath',$validPath,'-DrawioPath',$singleDrawio,'-DrawioExecutable',$wrongPdfRenderer,'-PdfPath',$preservedPdf)
    $pdfTemporaries = @(Get-ChildItem -LiteralPath $scratch -Filter '.preserved.*.pdf' -File -ErrorAction SilentlyContinue)
    Add-TestResult 'wrong-orientation-pdf-rejected' ($wrongPdfExport.ExitCode -ne 0 -and $wrongPdfExport.Output -match 'PDF MediaBox does not match canonical page' -and (Get-Sha256 $preservedPdf) -eq $preservedPdfHash -and $pdfTemporaries.Count -eq 0) $wrongPdfExport.Output

    $mismatchDrawio = Join-Path $scratch 'mismatch.drawio'
    $mismatchSync = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','ToDrawio','-CanonicalPath',$invalidVisualPath,'-DrawioPath',$mismatchDrawio,'-PageId','mismatch-page','-PageName','Mismatch Page')
    Add-TestResult 'parity-mismatch-fixture-sync' ($mismatchSync.ExitCode -eq 0) $mismatchSync.Output
    $markerRenderer = Join-Path $scratch 'marker-renderer.cmd'
    $rendererMarker = Join-Path $scratch 'renderer-invoked.txt'
    Write-Utf8File $markerRenderer "@echo invoked> `"$rendererMarker`"`r`n@exit /b 0`r`n"
    $parityOutput = Join-Path $scratch 'parity-output.svg'
    Write-Utf8File $parityOutput 'preserve-parity-output'
    $parityOutputHash = Get-Sha256 $parityOutput
    $parityExport = Invoke-Tool (Join-Path $PSScriptRoot 'export_drawio.ps1') @('-CanonicalPath',$validPath,'-DrawioPath',$mismatchDrawio,'-PageId','mismatch-page','-DrawioExecutable',$markerRenderer,'-SvgPath',$parityOutput)
    Add-TestResult 'parity-mismatch-rejected-before-render' ($parityExport.ExitCode -ne 0 -and $parityExport.Output -match 'Canonical XML does not match selected Draw.io page' -and -not (Test-Path -LiteralPath $rendererMarker) -and (Get-Sha256 $parityOutput) -eq $parityOutputHash) $parityExport.Output

    $discoveryProject = Join-Path $scratch 'discovery-project'
    $discoveryCandidates = Join-Path $discoveryProject '.tmp\drawio'
    $olderCandidate = Join-Path $discoveryCandidates 'app-2.9.0\draw.io.exe'
    $newerCandidate = Join-Path $discoveryCandidates 'app-2.10.0\draw.io.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $olderCandidate),(Split-Path -Parent $newerCandidate) -Force | Out-Null
    Write-Utf8File $olderCandidate 'older'
    Write-Utf8File $newerCandidate 'newer'
    $discoveryAnchor = Join-Path $discoveryProject 'anchor.drawio'
    Write-Utf8File $discoveryAnchor '<mxfile/>'
    $exporterPath = Join-Path $PSScriptRoot 'export_drawio.ps1'
    $tokens = $null
    $parseErrors = $null
    $exporterAst = [System.Management.Automation.Language.Parser]::ParseFile($exporterPath, [ref]$tokens, [ref]$parseErrors)
    $resolverAst = $exporterAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-DrawioExecutable' }, $true)
    . ([scriptblock]::Create($resolverAst.Extent.Text))
    $savedPath = $env:PATH
    try {
        $env:PATH = ''
        $discoveredExecutable = Resolve-DrawioExecutable '' $discoveryAnchor
    }
    finally {
        $env:PATH = $savedPath
    }
    $discoveredParent = Split-Path -Leaf (Split-Path -Parent ([string]$discoveredExecutable.Path))
    Add-TestResult 'automatic-cli-newest-semver' ([string]$discoveredExecutable.Version -eq '2.10.0' -and $discoveredParent -eq 'app-2.10.0') ($discoveredExecutable | ConvertTo-Json -Compress)

    if ($DrawioExecutable) {
        $svgPath = Join-Path $scratch 'single.svg'
        $pngPath = Join-Path $scratch 'single.png'
        $pdfPath = Join-Path $scratch 'single.pdf'
        $export = Invoke-Tool (Join-Path $PSScriptRoot 'export_drawio.ps1') @('-CanonicalPath',$validPath,'-DrawioPath',$singleDrawio,'-DrawioExecutable',$DrawioExecutable,'-SvgPath',$svgPath,'-PngPath',$pngPath,'-PdfPath',$pdfPath)
        $assetsExist = (Test-Path -LiteralPath $svgPath) -and (Test-Path -LiteralPath $pngPath) -and (Test-Path -LiteralPath $pdfPath)
        Add-TestResult 'page-aware-export' ($export.ExitCode -eq 0 -and $assetsExist) $export.Output
        [xml]$finalSvg = Get-Content -LiteralPath $svgPath -Raw -Encoding UTF8
        $sentinelNode = $finalSvg.SelectSingleNode("//*[@data-cell-id='__drawio_builder_page_bounds__']")
        Add-TestResult 'svg-sentinel-removed' (-not $sentinelNode -and -not (Get-Content -LiteralPath $svgPath -Raw -Encoding UTF8).Contains('__drawio_builder_page_bounds__')) $svgPath
        $validation = Invoke-Tool (Join-Path $PSScriptRoot 'validate_drawio.ps1') @('-SourcePath',$validPath,'-SvgPath',$svgPath,'-Profile','process')
        Add-TestResult 'rendered-validation' ($validation.ExitCode -eq 0) $validation.Output

        $visualEvidenceSuite = Invoke-Tool (Join-Path $PSScriptRoot 'test_visual_evidence.ps1') @('-SourcePath',$validPath,'-SvgPath',$svgPath,'-PngPath',$pngPath,'-ScratchDirectory',$scratch)
        Add-TestResult 'visual-evidence-contract' ($visualEvidenceSuite.ExitCode -eq 0) $visualEvidenceSuite.Output

        $approvalSuite = Invoke-Tool (Join-Path $PSScriptRoot 'test_approval_workflow.ps1') @('-SkillPath',$SkillPath,'-DrawioExecutable',$DrawioExecutable,'-ScratchDirectory',$scratch)
        Add-TestResult 'approval-workflow-contract' ($approvalSuite.ExitCode -eq 0) $approvalSuite.Output

        $invalidVisualDrawio = Join-Path $scratch 'invalid-visual.drawio'
        $invalidVisualSvg = Join-Path $scratch 'invalid-visual.svg'
        $invalidVisualPng = Join-Path $scratch 'invalid-visual.png'
        $invalidVisualSync = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','ToDrawio','-CanonicalPath',$invalidVisualPath,'-DrawioPath',$invalidVisualDrawio,'-PageId','invalid-visual','-PageName','Invalid Visual Process')
        Add-TestResult 'visual-failure-fixture-sync' ($invalidVisualSync.ExitCode -eq 0) $invalidVisualSync.Output
        $invalidVisualExport = Invoke-Tool (Join-Path $PSScriptRoot 'export_drawio.ps1') @('-CanonicalPath',$invalidVisualPath,'-DrawioPath',$invalidVisualDrawio,'-DrawioExecutable',$DrawioExecutable,'-SvgPath',$invalidVisualSvg,'-PngPath',$invalidVisualPng)
        Add-TestResult 'visual-failure-fixture-export' ($invalidVisualExport.ExitCode -eq 0 -and (Test-Path -LiteralPath $invalidVisualSvg) -and (Test-Path -LiteralPath $invalidVisualPng)) $invalidVisualExport.Output
        $invalidVisualValidation = Invoke-Tool (Join-Path $PSScriptRoot 'validate_drawio.ps1') @('-SourcePath',$invalidVisualPath,'-SvgPath',$invalidVisualSvg,'-Profile','process')
        $invalidVisualData = $invalidVisualValidation.Output | ConvertFrom-Json
        $connectorIssues = @(($invalidVisualData.Gates | Where-Object { $_.Name -eq 'connector-geometry' }).Result.Issues.Type)
        $archiveIssues = @(($invalidVisualData.Gates | Where-Object { $_.Name -eq 'archive-labels' }).Result.Issues.Type)
        $labelIssues = @(($invalidVisualData.Gates | Where-Object { $_.Name -eq 'rendered-labels' }).Result.Issues.Type)
        Add-TestResult 'detect-internal-micro-jog' ($invalidVisualValidation.ExitCode -eq 1 -and 'internal-micro-jog' -in $connectorIssues) $invalidVisualValidation.Output
        Add-TestResult 'detect-divider-clearance' ($invalidVisualValidation.ExitCode -eq 1 -and 'divider-clearance' -in $connectorIssues) $invalidVisualValidation.Output
        Add-TestResult 'detect-edge-label-node-collision' ($invalidVisualValidation.ExitCode -eq 1 -and 'edge-label-node-collision' -in $labelIssues) $invalidVisualValidation.Output
        Add-TestResult 'detect-archive-slope-overflow' ($invalidVisualValidation.ExitCode -eq 1 -and ('left-slope-clearance' -in $archiveIssues -or 'right-slope-clearance' -in $archiveIssues)) $invalidVisualValidation.Output
        $invalidVisualReport = Join-Path $scratch 'invalid-visual-report.json'
        Write-Utf8File $invalidVisualReport $invalidVisualValidation.Output
        $cropDirectory = Join-Path $scratch 'invalid-visual-crops'
        $cropReportOutput = Join-Path $scratch 'invalid-visual-crop-report.json'
        $cropExport = Invoke-Tool (Join-Path $PSScriptRoot 'export_drawio_crops.ps1') @('-PngPath',$invalidVisualPng,'-SvgPath',$invalidVisualSvg,'-ValidationReportPath',$invalidVisualReport,'-OutputDirectory',$cropDirectory,'-ReportPath',$cropReportOutput)
        $cropData = $cropExport.Output | ConvertFrom-Json
        Add-TestResult 'problem-crops-exported' ($cropExport.ExitCode -eq 0 -and $cropData.IssueCount -gt 0 -and $cropData.ExportedCount -eq $cropData.IssueCount -and (Test-Path -LiteralPath $cropReportOutput -PathType Leaf) -and @(Get-ChildItem -LiteralPath $cropDirectory -Filter '*.png' -File).Count -eq $cropData.IssueCount) $cropExport.Output
    }

    $multiSource = Join-Path $fixtures 'multi-page-uncompressed.drawio'
    $missingSelection = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','FromDrawio','-CanonicalPath',(Join-Path $scratch 'ambiguous.xml'),'-DrawioPath',$multiSource)
    Add-TestResult 'multi-page-selection-required' ($missingSelection.ExitCode -ne 0 -and $missingSelection.Output -match 'PageId is required') $missingSelection.Output

    $pageTwo = Join-Path $scratch 'page-two.xml'
    $selectedPage = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','FromDrawio','-CanonicalPath',$pageTwo,'-DrawioPath',$multiSource,'-PageId','page-two')
    Add-TestResult 'multi-page-import-created' ($selectedPage.ExitCode -eq 0 -and (Test-Path -LiteralPath $pageTwo)) $selectedPage.Output
    [xml]$selectedModel = Get-Content -LiteralPath $pageTwo -Raw -Encoding UTF8
    Add-TestResult 'multi-page-import' ([string]$selectedModel.mxGraphModel.pageWidth -eq '1169') $selectedPage.Output

    $multiWorking = Join-Path $scratch 'multi-page.drawio'
    Copy-Item -LiteralPath $multiSource -Destination $multiWorking
    $updatedPage = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','ToDrawio','-CanonicalPath',$validPath,'-DrawioPath',$multiWorking,'-PageId','page-two','-PageName','Updated Page')
    [xml]$updatedWrapper = Get-Content -LiteralPath $multiWorking -Raw -Encoding UTF8
    $firstPreserved = $updatedWrapper.SelectSingleNode('/mxfile/diagram[@id="page-one"]//mxCell[@id="first"]')
    $secondUpdated = $updatedWrapper.SelectSingleNode('/mxfile/diagram[@id="page-two"]//mxCell[@id="start"]')
    Add-TestResult 'multi-page-update' ($updatedPage.ExitCode -eq 0 -and $firstPreserved -and $secondUpdated -and [string]$updatedWrapper.mxfile.compressed -eq 'false') $updatedPage.Output

    $payload = Convert-ToCompressedPayload ((Get-Content -LiteralPath $validPath -Raw -Encoding UTF8).Trim())
    $compressedPath = Join-Path $scratch 'compressed.drawio'
    $compressedText = '<mxfile host="app.diagrams.net" compressed="true"><diagram id="compressed-page" name="Compressed Page">' + $payload + '</diagram></mxfile>'
    [System.IO.File]::WriteAllText($compressedPath, $compressedText, [System.Text.UTF8Encoding]::new($false))
    $compressedImport = Join-Path $scratch 'compressed-import.xml'
    $fromCompressed = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','FromDrawio','-CanonicalPath',$compressedImport,'-DrawioPath',$compressedPath)
    Add-TestResult 'compressed-import' ($fromCompressed.ExitCode -eq 0 -and (Get-ModelSignature $compressedImport) -eq (Get-ModelSignature $validPath)) $fromCompressed.Output

    if (-not $SkipSyncTests) {
        $syncSource = Join-Path $scratch 'sync-source'
        $syncDestination = Join-Path $scratch 'sync-destination'
        New-Item -ItemType Directory -Path (Join-Path $syncSource 'agents'),(Join-Path $syncSource 'scripts') -Force | Out-Null
        $minimalSkill = "---`nname: drawio-builder`ndescription: Use for deterministic Draw.io skill synchronization tests.`n---`n`n# Draw.io Builder`n`nRun deterministic tests.`n"
        Write-Utf8File (Join-Path $syncSource 'SKILL.md') $minimalSkill
        Copy-Item -LiteralPath (Join-Path $SkillPath 'agents\openai.yaml') -Destination (Join-Path $syncSource 'agents\openai.yaml')
        $minimalValidator = "param([Parameter(Mandatory=`$true)][string]`$SkillPath)`n`$passed = Test-Path -LiteralPath (Join-Path `$SkillPath 'SKILL.md') -PathType Leaf`n[pscustomobject]@{Skill=`$SkillPath;IssueCount=if(`$passed){0}else{1};Issues=if(`$passed){@()}else{@('SKILL.md not found')}} | ConvertTo-Json`nif(-not `$passed){exit 1}`n"
        Write-Utf8File (Join-Path $syncSource 'scripts\validate_skill.ps1') $minimalValidator
        $minimalRunner = "param([string]`$SkillPath,[string]`$DrawioExecutable,[string]`$CorpusRoot,[string]`$OfficialValidatorPath,[string]`$PythonExecutable,[switch]`$SkipSyncTests)`n[pscustomobject]@{ Engine=(Get-Process -Id `$PID).Path; TestCount=1; FailedCount=0; Tests=@([pscustomobject]@{Name='fixture';Passed=`$true;Detail='pass'}); SkippedCount=0; Skipped=@() } | ConvertTo-Json -Depth 5`n"
        Write-Utf8File (Join-Path $syncSource 'scripts\test_drawio_builder.ps1') $minimalRunner
        $null = & git -C $syncSource init -q
        $null = & git -C $syncSource config user.name 'Draw.io Builder Test'
        $null = & git -C $syncSource config user.email 'drawio-builder-test@invalid.local'
        $null = & git -C $syncSource config core.autocrlf false
        $null = & git -C $syncSource add . 2>$null
        $null = & git -C $syncSource commit -q -m 'test(sync): create source fixture' 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create the synchronization source fixture' }
        $syncScript = Join-Path $PSScriptRoot 'sync_personal_skill.ps1'
        $install = Invoke-Tool $syncScript @('-Mode','Install','-SourcePath',$syncSource,'-DestinationPath',$syncDestination)
        if ($install.ExitCode -ne 0) { Add-TestResult 'personal-sync-install' $false $install.Output }
        $installData = $install.Output | ConvertFrom-Json
        Add-TestResult 'personal-sync-install' ($install.ExitCode -eq 0 -and $installData.Passed -and (Test-Path -LiteralPath (Join-Path $syncDestination '.drawio-builder-install.json'))) $install.Output
        $installedManifest = Get-Content -LiteralPath (Join-Path $syncDestination '.drawio-builder-install.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $sourceCommit = @(& git -C $syncSource rev-parse HEAD)
        Add-TestResult 'personal-sync-provenance' ([string]$installedManifest.sourceCommit -eq ([string]$sourceCommit[0]).Trim() -and [string]$installedManifest.contentDigest -match '^[a-f0-9]{64}$' -and @($installedManifest.files).Count -ge 4) ($installedManifest | ConvertTo-Json -Compress -Depth 5)
        $check = Invoke-Tool $syncScript @('-Mode','Check','-SourcePath',$syncSource,'-DestinationPath',$syncDestination)
        if ($check.ExitCode -ne 0) { Add-TestResult 'personal-sync-check' $false $check.Output }
        $checkData = $check.Output | ConvertFrom-Json
        Add-TestResult 'personal-sync-check' ($check.ExitCode -eq 0 -and $checkData.Passed -and $checkData.DestinationMatchesSource) $check.Output
        Write-Utf8File (Join-Path $syncDestination 'SKILL.md') 'destination drift'
        $drift = Invoke-Tool $syncScript @('-Mode','Install','-SourcePath',$syncSource,'-DestinationPath',$syncDestination)
        Add-TestResult 'personal-sync-drift-rejected' ($drift.ExitCode -ne 0 -and $drift.Output -match 'Destination drift detected') $drift.Output
        $force = Invoke-Tool $syncScript @('-Mode','Install','-SourcePath',$syncSource,'-DestinationPath',$syncDestination,'-Force')
        $leftovers = @(Get-ChildItem -LiteralPath $scratch -Directory | Where-Object { $_.Name -like '.drawio-builder-stage-*' -or $_.Name -like '.drawio-builder-backup-*' })
        Add-TestResult 'personal-sync-force-repairs' ($force.ExitCode -eq 0 -and (Get-Content -LiteralPath (Join-Path $syncDestination 'SKILL.md') -Raw -Encoding UTF8) -eq $minimalSkill -and $leftovers.Count -eq 0) $force.Output
    }

    if ($CorpusRoot) {
        $corpusPath = (Resolve-Path -LiteralPath $CorpusRoot).Path
        $corpusDirectories = @('drawio-src', 'assets\drawio', 'assets\svg', 'assets\images')
        $beforeHashes = Get-TreeHashes $corpusPath $corpusDirectories
        $canonicalFiles = @(Get-ChildItem -LiteralPath (Join-Path $corpusPath 'drawio-src') -Filter '*.xml' -File | Sort-Object Name)
        $expectedNames = @(
            '01_payroll_system_flow', '02_payroll_payment_flow', '03_payroll_payment_dfd',
            '04_fresh_fruit_dfd', '05_fresh_fruit_flow', '06_purchase_context_dfd',
            '07_purchase_level0_dfd', '08_material_document_flow', '09_sales_context_dfd',
            '10_sales_level0_dfd', '11_sales_flow'
        )
        $actualNames = @($canonicalFiles | ForEach-Object { $_.BaseName })
        Add-TestResult 'corpus-inventory' ($canonicalFiles.Count -eq 11 -and (@(Compare-Object $expectedNames $actualNames)).Count -eq 0) ($actualNames -join ', ')
        $corpusFailures = [System.Collections.Generic.List[string]]::new()
        $corpusObservations = [System.Collections.Generic.List[object]]::new()
        $corpusFindings = [System.Collections.Generic.List[object]]::new()
        $validatorCommand = Get-Command (Join-Path $PSScriptRoot 'validate_drawio.ps1')
        foreach ($canonical in $canonicalFiles) {
            $base = $canonical.BaseName
            $wrapper = Join-Path $corpusPath "assets\drawio\$base.drawio"
            $svg = Join-Path $corpusPath "assets\svg\$base.svg"
            $png = Join-Path $corpusPath "assets\images\$base.png"
            if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf) -or -not (Test-Path -LiteralPath $svg -PathType Leaf) -or -not (Test-Path -LiteralPath $png -PathType Leaf)) {
                $corpusFailures.Add("missing-assets:$base")
                continue
            }
            $preflight = Invoke-Tool (Join-Path $PSScriptRoot 'preflight_drawio.ps1') @('-SourcePath',$canonical.FullName)
            if ($preflight.ExitCode -ne 0) { $corpusFailures.Add("preflight:$base") }
            $imported = Join-Path $scratch ($base + '-import.xml')
            $import = Invoke-Tool (Join-Path $PSScriptRoot 'sync_drawio.ps1') @('-Direction','FromDrawio','-CanonicalPath',$imported,'-DrawioPath',$wrapper)
            if ($import.ExitCode -ne 0 -or (Get-ModelSignature $imported) -ne (Get-ModelSignature $canonical.FullName)) { $corpusFailures.Add("wrapper-parity:$base") }
            $family = 'process'
            if ($base -match '_dfd$') { $family = 'data-flow' }
            $validationArguments = @('-SourcePath',$canonical.FullName,'-SvgPath',$svg)
            if ($validatorCommand.Parameters.ContainsKey('Family')) { $validationArguments += @('-Family',$family) }
            else { $validationArguments += @('-Profile',$family) }
            $validation = Invoke-Tool (Join-Path $PSScriptRoot 'validate_drawio.ps1') $validationArguments
            try {
                $validationData = $validation.Output | ConvertFrom-Json
                $invalidOutputs = @(foreach ($gate in @($validationData.Gates)) { if (@($gate.Result.Issues.Type) -contains 'invalid-gate-output') { $gate.Name } })
                if ($invalidOutputs.Count -gt 0) { $corpusFailures.Add("validator-contract:$base") }
                foreach ($gate in @($validationData.Gates)) {
                    foreach ($issue in @($gate.Result.Issues)) {
                        $corpusFindings.Add([pscustomobject]@{ Diagram=$base; Gate=[string]$gate.Name; Type=[string]$issue.Type; Element=[string]$issue.Element })
                    }
                }
                $corpusObservations.Add([pscustomobject]@{ Diagram=$base; FailedGateCount=[int]$validationData.FailedGateCount; ExitCode=$validation.ExitCode })
            }
            catch { $corpusFailures.Add("validator-json:$base") }
        }
        Add-TestResult 'corpus-read-only-gates' ($corpusFailures.Count -eq 0) ([pscustomobject]@{ Failures=@($corpusFailures); Observations=@($corpusObservations) } | ConvertTo-Json -Compress -Depth 5)
        $expectations = Get-Content -LiteralPath (Join-Path $SkillPath 'tests\corpus-expectations.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $expectedMap = @{}
        foreach ($expected in @($expectations.findings)) { $expectedMap["$($expected.diagram)|$($expected.gate)|$($expected.type)|$($expected.element)"] = [int]$expected.count }
        $actualMap = @{}
        foreach ($finding in @($corpusFindings)) {
            $key = "$($finding.Diagram)|$($finding.Gate)|$($finding.Type)|$($finding.Element)"
            if (-not $actualMap.ContainsKey($key)) { $actualMap[$key] = 0 }
            $actualMap[$key]++
        }
        $findingMismatches = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($expectedMap.Keys + $actualMap.Keys | Sort-Object -Unique)) {
            if (-not $actualMap.ContainsKey($key)) { $findingMismatches.Add("missing:${key}:$($expectedMap[$key])") }
            elseif (-not $expectedMap.ContainsKey($key)) { $findingMismatches.Add("unexpected:${key}:$($actualMap[$key])") }
            elseif ([int]$expectedMap[$key] -ne [int]$actualMap[$key]) { $findingMismatches.Add("count:${key}:$($expectedMap[$key])!=$($actualMap[$key])") }
        }
        if ([int]$expectations.findingCount -ne $corpusFindings.Count) { $findingMismatches.Add("total:$($expectations.findingCount)!=$($corpusFindings.Count)") }
        Add-TestResult 'corpus-expected-findings' ($findingMismatches.Count -eq 0) ($findingMismatches -join ', ')
        $afterHashes = Get-TreeHashes $corpusPath $corpusDirectories
        Add-TestResult 'corpus-inputs-unchanged' (Compare-HashMaps $beforeHashes $afterHashes) "Before=$($beforeHashes.Count); After=$($afterHashes.Count)"
    }
    else {
        Add-SkippedResult 'corpus-regression' 'CorpusRoot was not provided'
    }
}
finally {
    $resolvedBase = [System.IO.Path]::GetFullPath($scratchBase).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $resolvedScratch = [System.IO.Path]::GetFullPath($scratch)
    if ($resolvedScratch.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedScratch)) {
        Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
    }
}

$failed = @($tests | Where-Object { -not $_.Passed })
[pscustomobject]@{ Engine=$engine; TestCount=$tests.Count; FailedCount=$failed.Count; Tests=@($tests); SkippedCount=$skipped.Count; Skipped=@($skipped) } | ConvertTo-Json -Depth 8
if ($failed.Count -gt 0) { exit 1 }
