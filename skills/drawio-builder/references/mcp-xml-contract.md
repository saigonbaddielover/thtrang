# Draw.io MCP and XML Contract

## Contents

- Live discovery
- Tool boundaries
- Canonical XML
- Layout and routing passes
- Shape discovery
- Failure behavior

## Live discovery

Discover the connected Draw.io MCP tools before work. The audited environment exposes `mcp__drawio__create_diagram` and `mcp__drawio__search_shapes`, but treat the live tool list and schemas as authoritative because deployments can change.

Compare live names, input schemas, enum values, defaults, descriptions, and shape-search results with this baseline. Record the server/build fingerprint when exposed. If the contract or build differs, invalidate cached extended styles and rerun representative renders before final work.

`mcp__drawio__create_diagram` accepts exactly one of:

- required-by-choice `xml: string`; or
- required-by-choice `mermaid: string`.

Optional XML controls are `postLayout: "elk"`, `direction: "vertical" | "horizontal"`, and `routing: "libavoid"`. `direction` only applies with XML ELK. `routing` only applies to XML. Do not combine ELK and libavoid.

`mcp__drawio__search_shapes` requires `query: string`. It optionally accepts `limit: number`; the documented default is `10` and maximum is `50`.

The live server recommends Mermaid for standard flowcharts. This skill carries an explicit user-approved override: final work is canonical XML-first, while Mermaid is disposable exploration only. Pass `xml` for final flowcharts and do not let viewer-generated layout replace the reviewed canonical source.

Use `search_shapes` only for industry, brand, pictorial, cloud, network, engineering, electrical, floorplan, or mockup symbols. Standard rectangles, documents, ellipses, decisions, cylinders, notes, containers, and swimlanes do not require a search.

## Tool boundaries

`mcp__drawio__create_diagram` displays an interactive preview and returns an MCP `CallToolResult`. It does not provide filesystem persistence, canonical readback, local save, or final export. Do not claim viewer-side changes exist in repository files.

`mcp__drawio__search_shapes` returns matching titles, exact style strings, and suggested dimensions. Verify the returned style in a render before accepting it. A search result is a stencil contract, not a layout decision.

Use XML for final work. Pass exactly one well-formed `mxGraphModel`, not an `mxfile` wrapper. Do not include XML comments. Escape attribute content and use unique IDs.

## Canonical XML

Require:

- root `mxGraphModel`;
- structural cells `0` and `1`;
- one stable ID per cell;
- existing parent IDs;
- acyclic parent hierarchy;
- positive finite vertex geometry;
- existing edge source and target vertices;
- `mxGeometry relative="1"` on every edge;
- page width and height matching the intended page;
- child coordinates relative to their container;
- edges parented to a common layer when they cross containers.

Keep source and target semantics in the edge attributes. Waypoints never repair a reversed semantic edge.

## Layout and routing passes

Use `postLayout: "elk"` only for a disposable hierarchical draft or a final flow whose returned geometry can be captured into canonical XML. ELK replaces positions.

Use `routing: "libavoid"` only for a disposable obstacle-avoiding preview or when its result can be captured. It preserves vertices but changes routes in the viewer.

Do not combine ELK and libavoid. Omit both for final hand-placed layouts, swimlanes, floorplans, architecture groupings, or any diagram where coordinates carry meaning.

When final canonical geometry is hand-authored, explicit anchors and waypoints are allowed and must pass rendered QA.

This explicit-routing rule is a user-approved override for precision work. The generic live MCP description discourages hand-routing, but the quality workflow in this skill permits it when ELK/libavoid are omitted and the final geometry is validated.

## Shape discovery

Never invent an extended shape ID. Search by domain plus object, for example `aws lambda`, `cisco router`, `pid globe valve`, `electrical transformer`, or `floorplan door`.

If no suitable stencil is returned:

1. search a more specific synonym;
2. verify the relevant library family;
3. use a generic primitive only if notation permits;
4. otherwise report the missing stencil.

## Failure behavior

Fail on malformed XML, missing MCP input, invalid tool schema, missing renderer, unsupported output, or ambiguous multi-page selection. Record MCP preview as `SKIPPED` when the server is unavailable; never convert it to a pass because local rendering succeeded.

Basic preflight only proves that a style string is nonempty and syntactically present. It does not prove an extended stencil exists or matches a named notation. Use live shape search and rendered inspection for that distinction.

MCP preview is an interaction surface, not an artifact authority. It cannot prove local save, selected-page parity, final export freshness, actual arrow attachment, label ink clearance, or page-aware visual quality.
