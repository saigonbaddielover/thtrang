# Process, Document, and Swimlane Diagrams

Use `profiles/process.json` for flowcharts, `document-flow.json` when copy lineage or filing is semantic, and `swimlane.json` when responsibility alone is semantic. Use `document-flow-swimlane.json` when both document lineage and lane responsibility are semantic. Do not drop one contract merely because the validator accepts one profile. These profiles cite [ISO 5807:1985](https://www.iso.org/standard/11955.html); swimlane responsibility remains a local layout contract.

Lock the narrative and edge manifest before placement. Place lanes first, primary flow second, documents and stores third, then reserve cross-lane and return corridors. Require labels for semantically distinct decision outcomes. Record document copy lineage.

Keep archive labels below the divider and inside both slopes and the bottom border. Automated checks cannot infer business ownership or document destination from geometry.

Use `assets/templates/process-document-portrait.xml` or the three-lane landscape template.

Live discovery from Draw.io MCP server `drawio`, build `42835e3@2026-08-02T20:17:10.515Z`, on 2026-08-11 confirmed `shape=mxgraph.flowchart.document2` for Document and `shape=mxgraph.dfd.archive` for Final Report / Archive. These exact styles prove renderer availability, not business semantics or ISO conformance.
