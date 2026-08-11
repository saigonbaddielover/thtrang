# Electrical

Use `profiles/electrical.json` with the official [IEC 60617 Database](https://webstore.iec.ch/en/publication/2723). Record every symbol reference number and resolve it through a verified licensed source or live MCP match.

Preserve orientation, ports, conductor type, and connectivity. Distinguish junctions from crossings without connection. Never substitute a visually similar generic icon.

## Semantic contract

Set `diagram.context.standardEdition`, `symbolStandard`, and `symbolStandardEdition`. Add one `symbolMappings` entry per used symbol with its canonical node ID, semantic type, exact symbol reference, source, orientation, and named ports. Every conductor edge records `sourcePort`, `targetPort`, `conductorType`, and `connectionSemantics`. A live candidate without an exact licensed symbol reference remains `UNKNOWN`.

## Live MCP discovery

Query `electrical transformer` returned `Transformer`, `64×64`, from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11 with exact style `pointerEvents=1;verticalLabelPosition=bottom;shadow=0;dashed=0;align=center;html=1;verticalAlign=top;shape=mxgraph.electrical.inductors.transformer;direction=north;`.

The MCP result contains no IEC 60617 reference number. Treat this as a renderable candidate, not IEC conformance evidence.

Copy the transformer candidate from `assets/templates/live-mcp-style-palette.xml` into `technical-landscape.xml` only after standard mapping. Geometry validation cannot certify circuit behavior, ratings, or electrical safety.
