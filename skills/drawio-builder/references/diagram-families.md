# Diagram Family Selection

## Contents

- Selection rule
- Family matrix
- Standards policy
- Mixed notation

## Selection rule

Select a family from semantics, not appearance. Select a subtype and explicit standard whenever line endings, ports, symbols, containment, or relation meaning changes. Do not infer a named standard from a visually similar stencil.

## Family matrix

| Family | Core invariant | Required reference |
| --- | --- | --- |
| `process` | Directed activity/document narrative with explicit responsibility and branch meaning | `families/process.md` |
| `data-flow` | Directed data nouns, consistent entity/process/store notation, balanced boundaries | `dfd-notation.md`, `families/data-flow.md` |
| `bpmn` | BPMN element and flow semantics under an explicit standard | `families/bpmn.md` |
| `uml` | Subtype-specific nodes and relations | `families/uml.md` |
| `erd` | Explicit entity/attribute/cardinality notation | `families/erd.md` |
| `architecture` | Explicit boundaries, ownership, deployment, or dependency meaning | `families/architecture.md` |
| `cloud` | Verified provider or platform stencils and explicit connection meaning | `families/cloud.md` |
| `network` | Logical or physical topology with verified devices and link types | `families/network.md` |
| `engineering` | Explicit standard, symbols, ports, and connectivity | `families/engineering.md` |
| `electrical` | Explicit electrical standard and connection semantics | `families/electrical.md` |
| `pid` | Explicit P&ID standard, tag, line, and instrument semantics | `families/pid.md` |
| `floorplan` | Spatial containment, scale, circulation, and z-order | `families/floorplan.md` |
| `wireframe` | Screen containment, hierarchy, alignment, and interaction annotation | `families/wireframe.md` |

## Standards policy

Use authoritative primary sources for notation profiles. Require the diagram manifest to name the standard for BPMN, UML, ERD, engineering, electrical, and P&ID work. If the standard is absent, ask for it or use a notation-neutral `generic` profile with an explicit limitation. Never upgrade a generic visual pass into a notation pass.

For cloud, network, engineering, electrical, P&ID, floorplan, and wireframe stencils, use live MCP shape discovery. Store exact returned styles only with provenance and revalidate them when the MCP contract changes.

## Mixed notation

Prefer one notation. If mixing is deliberate, add a legend, enumerate each edge class in the semantic manifest, and use family-specific checks for each class. Use `generic` only for geometry that has no stronger contract.
