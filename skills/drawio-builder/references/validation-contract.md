# Validation Contract

## Contents

- Required inputs
- Gate order
- Issue model
- Approval
- Compatibility

## Required inputs

Use canonical `mxGraphModel` XML, its page-aware SVG render, and the quality profile for every automated audit. Add a diagram semantic manifest whenever the task requires source-to-target, exact-label, copy-lineage, boundary-flow, or notation claims. Add an explicit notation profile whenever a family has competing standards. Approval additionally requires an artifact manifest, visual-inspection evidence, and a warning-disposition document whenever warnings exist.

Interpret each `styleMatchers` entry as one alternative. Within an entry, every `allOf` token must be present and every optional `noneOf` token must be absent. A node matches when any entry matches.

## Gate order

Run gates in this order:

1. canonical structure and page geometry;
2. semantic manifest parity;
3. notation profile conformance;
4. manual notation-rule dispositions;
5. rendered shape, text, and containment geometry;
6. connector, arrow, corridor, and label geometry;
7. artifact parity and freshness;
8. full-page and problem-crop visual inspection;
9. warning dispositions.

A downstream pass never cancels an upstream failure.

## Issue model

Every issue has a stable type, severity, element ID, rendered coordinates when available, evidence, and a repair class.

- `ERROR` means a structural, semantic, notation, collision, clipping, attachment, boundary, or artifact-integrity failure.
- `WARNING` means a composition, association, balance, density, or unknown-outline risk that requires an explicit disposition.
- `INFO` records provenance and measurements.

Unknown standards, unknown stencils, unsupported SVG constructs, missing required renders, and skipped required gates are not passes.

`Audit` mode records omitted semantic, notation, artifact, and visual inputs as `SKIPPED` or `UNKNOWN` without blocking read-only exploration. `Approval` mode makes every omitted or unresolved required gate blocking. A supplied crop report follows `schemas/crop-report.schema.json`; `ValidationReportSha256` binds the validation report that generated its findings. That report must identify the same canonical XML and SVG, input digests, family, validation mode, required artifact roles, pre-visual gate states, and pre-visual findings as the current validation call. Generate the pre-visual report in `Approval` mode with the same semantic manifest, notation profile, artifact manifest, quality profile, and required artifact roles used for final approval; the missing visual evidence in that intermediate report is expected. Every crop row must map to exactly one reported finding by gate, type, and element, including multiplicity. A supplied visual-inspection document follows `schemas/visual-inspection.schema.json`; its `assetSha256` is the lowercase SHA-256 of the exact SVG passed through `-SvgPath`, and `cropReportSha256` binds the exact `-CropReportPath`. When an artifact manifest is supplied, the crop report PNG must be the manifest's PNG. Every exported crop ID and SHA-256 must appear exactly once in `reviewedCrops`. Stale, cross-bundle, mis-mapped, or incomplete evidence must fail even when its prose says `PASS`.

Profile fixtures under `scripts/fixtures/profiles` prove structural preflight, live-style renderability, and automated semantic/notation matching. Their `PASS` outcome does not resolve profile prose rules or replace project-specific visual inspection.

## Approval

Approve a page only when:

- every required gate ran and passed;
- no `ERROR` remains;
- every `WARNING` has a recorded disposition;
- canonical, wrapper, and requested outputs have matching artifact provenance;
- final full-page and dense-region visual inspection passed.
- the visual-inspection hash matches the exact audited SVG.

Keep the page `NOT APPROVED` while any condition is unmet.

## Compatibility

Keep `-Profile` as an alias for the validator family selector. Existing lifecycle commands and JSON keys remain valid unless a schema version explicitly changes. Reject an unsupported schema version rather than silently interpreting it.
