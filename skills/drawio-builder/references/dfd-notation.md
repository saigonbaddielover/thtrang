# DFD Notation Contract

## Contents

- Notation decision
- Verified live primitives
- Semantic manifest
- Context and level-0 balancing
- Validation boundary

## Notation decision

Name the notation only when the user, assignment, repository convention, or authoritative source identifies it. Do not infer Gane-Sarson or Yourdon/DeMarco from a generic Draw.io search result.

The audited live shape search does not classify its DFD-like results by Gane-Sarson or Yourdon/DeMarco. If an exact variant matters and no authoritative reference is available, stop notation approval as `UNKNOWN` and request the missing source. A visually plausible substitute is not notation proof.

## Verified live primitives

The live MCP exposes these exact search results:

| Purpose | Exact style | Suggested size | Provenance limit |
| --- | --- | --- | --- |
| Generic activity/process/entity/external interactor | `html=1;dashed=0;whiteSpace=wrap;` | `100×50` | Generic rectangle; not variant-specific |
| Generic data process | `shape=ellipse;html=1;dashed=0;whiteSpace=wrap;perimeter=ellipsePerimeter;` | `30×30` | Generic circular process; not variant-specific |
| Data store with ID | `html=1;dashed=0;whiteSpace=wrap;shape=mxgraph.dfd.dataStoreID;align=left;spacingLeft=3;points=[[0,0],[0.5,0],[1,0],[0,0.5],[1,0.5],[0,1],[0.5,1],[1,1]];` | `100×30` | DFD-namespaced; live result does not name a notation variant |
| Open data store | `html=1;dashed=0;whiteSpace=wrap;shape=partialRectangle;right=0;left=0;` | `100×30` | Generic; notation assignment unknown |
| One-sided open data store | `html=1;dashed=0;whiteSpace=wrap;shape=partialRectangle;right=0;` | `100×30` | Generic; notation assignment unknown |

Use a consistent verified primitive set for a notation-neutral DFD only when the user accepts that contract. Preserve full style strings. Search live again when the server build changes.

## Semantic manifest

Before drawing, record every flow as:

```text
edge ID | source ID | target ID | data noun | boundary flow ID
```

Use noun phrases for data flows. Reject action/control labels such as decisions, approvals, or branch conditions unless they name actual data. Audit the manifest against the narrative before auditing geometry.

## Context and level-0 balancing

For a context/level-0 pair, compare the multisets of external boundary flows. Each item is:

```text
external entity | direction relative to system | data-flow label
```

Renaming for decomposition is allowed only when the source specification explicitly maps the names. Internal stores and internal flows do not appear in the context boundary set.

## Validation boundary

`preflight_drawio.ps1` verifies XML structure, finite geometry, parents, IDs, bounds, and basic style presence. It does not prove a stencil identifier exists or that a rendered shape is correct notation.

`validate_drawio.ps1 -Profile data-flow` verifies directed classic target arrows, anchors, rendered endpoint direction, routing, crossings, shared paths, and label geometry. It does not prove business semantics, noun quality, variant-specific shape meaning, or context/level-0 balancing. Those remain explicit semantic and notation gates.
