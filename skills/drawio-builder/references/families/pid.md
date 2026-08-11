# P&ID

Use `profiles/pid.json` with [ISO 10628-1:2014](https://www.iso.org/standard/51840.html) and the selected applicable equipment and instrument-symbol standard.

Resolve all equipment and instrument symbols live or from a verified licensed mapping. Preserve equipment tags, instrument tags, ports, flow direction, and process, utility, electrical, pneumatic, and signal line classes.

## Semantic contract

Set `diagram.context.symbolStandard`, `symbolStandardEdition`, `instrumentStandard`, `instrumentStandardEdition`, and `projectLegend`. Add a `symbolMappings` entry for every used item with node ID, semantic type, exact reference, primary source, exact tag, and named ports. Every line edge records `sourcePort`, `targetPort`, `lineClass`, and `flowDirection`. ISO 10628-1 alone does not resolve the globe-valve or instrument symbol, so an unverified live candidate remains `UNKNOWN`.

## Live MCP discovery

Query `pid globe valve` returned `Globe Valve`, `100×60`, from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11 with exact style `verticalLabelPosition=bottom;align=center;html=1;verticalAlign=top;pointerEvents=1;dashed=0;shape=mxgraph.pid2valves.valve;valveType=globe`.

This proves Draw.io renderer availability only. Validate the symbol against the selected P&ID standard and project legend.

Copy the globe-valve candidate from `assets/templates/live-mcp-style-palette.xml` into `technical-landscape.xml` only after standard and legend validation. Geometry validation cannot certify process safety, sizing, or engineering correctness.
