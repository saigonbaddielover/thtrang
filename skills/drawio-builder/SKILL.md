---
name: drawio-builder
description: Create, import, edit, relayout, audit, repair, and export production-quality Draw.io diagrams from requirements, canonical mxGraphModel XML, or .drawio files. Use for flowcharts, document flows, swimlanes, DFDs, BPMN, UML, ERDs, architecture, cloud, network, engineering, electrical, P&ID, floorplans, wireframes, or any task where notation, geometry, text fit, connector routing, page setup, artifact parity, and final SVG/PNG/PDF quality must be verified.
---

# Draw.io Builder

## Operating contract

Treat one canonical `mxGraphModel` XML file as the primary source for one page. Treat `.drawio` as the editable wrapper. Treat SVG, PNG, PDF, audit reports, and crops as derived artifacts.

When a user edits a `.drawio` file, import the selected page into canonical XML before further changes. Never recover source from a derived SVG or PNG.

Work on one page at a time:

`requirements -> semantic manifest -> notation profile -> canonical XML -> preflight -> MCP preview -> page-aware export -> automated QA -> visual QA -> repair -> APPROVED`

Do not start the next page before the current page is approved. Parallelize only independent read-only audits or isolated forward tests. Never let concurrent workers edit the same canonical source.

Use canonical XML for final precision. Use Mermaid only for a disposable draft when the user explicitly requests it. Never claim viewer-side ELK or libavoid changes are persisted unless their resulting geometry was captured into canonical XML and revalidated.

## Establish truth before drawing

Lock:

- the exact requirement narrative;
- the diagram family and subtype;
- the notation or engineering standard when variants change meaning;
- the source-to-target, relation, label, copy-lineage, and boundary-flow contract;
- page orientation, output formats, renderer, and quality profile.

Use `schemas/diagram-contract.schema.json` for semantic manifests. Use `schemas/notation-profile.schema.json` for notation profiles. If a required standard, stencil, semantic mapping, or renderer is missing, report `UNKNOWN` or `SKIPPED`; do not invent a pass.

## Load references selectively

Always read:

- [validation-contract.md](references/validation-contract.md) before validation or approval;
- [audit-recipes.md](references/audit-recipes.md) before running a read-only or approval audit;
- [failure-catalog.md](references/failure-catalog.md) during every audit or repair;
- [visual-quality.md](references/visual-quality.md) before sizing, styling, rendering, or final inspection.

Read when applicable:

- [mcp-xml-contract.md](references/mcp-xml-contract.md) before MCP, extended stencils, ELK, libavoid, or hand-authored XML;
- [layout-routing.md](references/layout-routing.md) before lanes, containers, dense fan-in/fan-out, feedback loops, or cross-container routing;
- [lifecycle.md](references/lifecycle.md) before import, sync, export, artifact manifests, or multi-page work;
- [diagram-families.md](references/diagram-families.md) before choosing a family or profile;
- [dfd-notation.md](references/dfd-notation.md) for every context or DFD task;
- [process](references/families/process.md), [data-flow](references/families/data-flow.md), [BPMN](references/families/bpmn.md), [UML](references/families/uml.md), [ERD](references/families/erd.md), [architecture](references/families/architecture.md), [cloud](references/families/cloud.md), [network](references/families/network.md), [engineering](references/families/engineering.md), [electrical](references/families/electrical.md), [P&ID](references/families/pid.md), [floorplan](references/families/floorplan.md), or [wireframe](references/families/wireframe.md) when that family applies.

## Select a family contract

Use these family identifiers:

| Family | Use for |
| --- | --- |
| `process` | Flowcharts, document flows, cross-functional processes, swimlanes |
| `data-flow` | Context diagrams and DFD decomposition |
| `bpmn` | BPMN processes, collaborations, pools, lanes, events, tasks, gateways |
| `uml` | Class, activity, state, sequence, component, deployment diagrams |
| `erd` | Crow's Foot, Chen, or IDEF1X data models |
| `architecture` | Generic system, container, component, deployment views |
| `cloud` | Provider or Kubernetes topology using verified stencils |
| `network` | Logical or physical network topology |
| `engineering` | Explicit-standard engineering schematics not covered below |
| `electrical` | Explicit-standard electrical connectivity diagrams |
| `pid` | Explicit-standard piping and instrumentation diagrams |
| `floorplan` | Spatial floor, room, furniture, and access layouts |
| `wireframe` | UI screens, components, interactions, and layout |
| `generic` | Deliberately mixed or notation-neutral diagrams |

Require an explicit notation profile for BPMN, UML, ERD, engineering, electrical, and P&ID. Use live MCP shape search for vendor, industry, brand, cloud, network, engineering, electrical, P&ID, floorplan, and mockup stencils. Never invent a stencil identifier. Revalidate cached styles when the MCP server or build changes.

## Build canonical geometry

1. Define stable page, layer, lane, node, and edge IDs.
2. Place page-level containers and lanes before children.
3. Place the semantic backbone before secondary records, stores, notes, and archives.
4. Size shapes for full labels at the quality-profile font size.
5. Reserve label whitespace, fan-in/fan-out ports, and return corridors before adding edges.
6. Create explicit perimeter anchors and orthogonal waypoints only when geometry requires them.
7. Keep each edge `mxGeometry` relative and parent cross-container edges above their containers.
8. Keep one `mxGraphModel` root per canonical page.

Resize or relayout before shrinking type. After any shape move or resize, recompute physical ports and rerender every incident edge, neighboring corridor, label, and lane boundary in the impact region.

Use MCP `create_diagram` with XML and omit post-layout/routing for final hand-crafted geometry. Use ELK or libavoid only for disposable exploration unless the result can be captured and revalidated.

## Run deterministic tooling

Resolve paths relative to the project or skill. Never hardcode a machine path.

- Run `scripts/preflight_drawio.ps1` on canonical XML.
- Run `scripts/sync_drawio.ps1` for `.drawio` import or update.
- Run `scripts/export_drawio.ps1` for page-aware SVG, PNG, PDF, and artifact provenance.
- Run `scripts/validate_drawio.ps1` in `Audit` mode while iterating and in `Approval` mode only with semantic, notation, artifact, warning-disposition, and visual-inspection evidence required by the task.
- Run `scripts/export_drawio_crops.ps1` after validation to create inspectable crops for structured findings.
- Run `scripts/test_profile_fixtures.ps1` after changing a notation profile, contract schema, or family stencil mapping.

Invoke each script as a separate `pwsh -NoProfile -File` or `powershell.exe -NoProfile -File` process. Do not dot-source or chain scripts that intentionally use exit codes.

Treat nonzero exits as failures. Treat unsupported SVG constructs, unknown outlines, missing manifests, renderer drift, and unavailable required gates explicitly. MCP acceptance proves only that the viewer accepted the request; it is not pixel-level evidence or filesystem persistence.

## Enforce rendered QA

Require automated evidence for:

- XML structure, IDs, parents, finite geometry, edge endpoints, relative geometry, containment, and page bounds;
- semantic-manifest parity and notation-profile conformance;
- rendered text ink, shape-specific safe areas, font size, glyph availability, clipping, and label collisions;
- actual source departure, target contact, arrow tip, normal approach, visible shaft, and port location;
- crossings, touches, shared or near-stacked paths, border running, self-crossing, hairpins, backtracking, detours, and micro-jogs;
- fan-in/fan-out separation, edge-label association, lane headers, dividers, z-order, and page clearance;
- canonical/wrapper/output parity, renderer version, output freshness, page dimensions, and requested formats.

Then inspect the full-resolution SVG or PNG and every generated problem crop. Check reading order, notation, hierarchy, alignment, density, whitespace, balance, contrast, label association, and any unknown-stencil safe area. Automated zero-issue output never replaces visual inspection.

## Repair by root cause

Repair canonical XML only. Prefer this order:

1. correct semantics or notation;
2. resize or move the affected shape;
3. recompute anchors and incident routes;
4. separate corridors, labels, fan-in, and fan-out;
5. restore typography and visual hierarchy;
6. rerender every impacted region and all final assets;
7. rerun every required gate.

Do not patch SVG or PNG. Do not hide a collision with a white label background. Do not replace an exact notation with a visually similar generic primitive without explicit acceptance.

## Approval

Use the report format in [validation-contract.md](references/validation-contract.md). A page is `APPROVED` only when every required gate ran, no `ERROR` remains, every `WARNING` has a recorded disposition, every manual profile rule has evidence, artifact provenance matches, and full-page plus crop inspection passed against the exact SVG hash.

Keep any page with `UNKNOWN`, `SKIPPED`, unresolved warnings, stale assets, or missing visual evidence as `NOT APPROVED`.

## Versioned source and personal installation

When a repository contains `skills/drawio-builder`, edit that versioned source instead of the personal installation. After the source is reviewed, run `scripts/sync_personal_skill.ps1 -Mode Check`, then `-Mode Install`, then `-Mode Check` again. Sync is manual and one-way. Never treat personal drift as source.
