# Audit Recipes

## Read-only audit

Run every command as a separate process. Audit mode records missing contracts as explicit `SKIPPED` or `UNKNOWN` gates without modifying source assets.

```powershell
pwsh -NoProfile -File scripts/preflight_drawio.ps1 -SourcePath diagram.xml
pwsh -NoProfile -File scripts/validate_drawio.ps1 -SourcePath diagram.xml -SvgPath diagram.svg -Family process -NotationProfilePath profiles/document-flow-swimlane.json -QualityProfilePath assets/quality-profile.json -ValidationMode Audit -ReportDirectory audit-report
pwsh -NoProfile -File scripts/export_drawio_crops.ps1 -PngPath diagram.png -SvgPath diagram.svg -ValidationReportPath audit-report/validation-summary.json -OutputDirectory audit-report/crops -ReportPath audit-report/crop-report.json
```

Treat crop exit code `2` as incomplete evidence: at least one issue lacked rendered coordinates or recoverable label ink bounds and still requires full-page inspection. Produce the pre-visual validation report in `Approval` mode with the same family, semantic manifest, notation profile, artifact manifest, quality profile, and required artifact roles that the final approval command will use; approval rejects a crop report derived from another gate set. The report is expected to remain `NOT APPROVED` until visual evidence is supplied. The crop report PNG must also be the PNG recorded by the supplied artifact manifest.

## Approval audit

Approval mode requires semantic, notation, artifact provenance, manual-rule evidence, and exact-render visual evidence. It must not turn a missing input into a pass. Generate `visual-inspection.json` only after reviewing the full page and every required crop; set `assetSha256` to the SHA-256 of `diagram.svg`, set `cropReportSha256` to the SHA-256 of `audit-report/crop-report.json`, and record every exported crop ID and hash in `reviewedCrops`. If automated gates emit warnings, create `warning-dispositions.json` from `schemas/warning-dispositions.schema.json` and resolve every warning exactly once.

```powershell
pwsh -NoProfile -File scripts/validate_drawio.ps1 -SourcePath diagram.xml -SvgPath diagram.svg -Family process -NotationProfilePath profiles/document-flow-swimlane.json -SemanticManifestPath diagram-contract.json -ArtifactManifestPath artifact-manifest.json -RequiredArtifactRoles canonical,wrapper,svg,png,pdf -VisualInspectionPath visual-inspection.json -CropReportPath audit-report/crop-report.json -WarningDispositionPath warning-dispositions.json -QualityProfilePath assets/quality-profile.json -ValidationMode Approval -ReportDirectory audit-report
```

Inspect the full-resolution SVG or PNG and every exported crop. Record a disposition for each warning. An automated zero-issue result does not approve composition, hierarchy, reading order, or unknown stencil geometry.

## Profile selection

- Use `process.json` for a basic flowchart.
- Use `document-flow.json` for document lineage without responsibility lanes.
- Use `swimlane.json` for responsibility lanes without document lineage.
- Use `document-flow-swimlane.json` when both contracts apply.
- Use a specialized family profile only after its required standard and unresolved live-search placeholders are satisfied.
